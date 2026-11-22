import AppKit
import Observation
import os.log

/// Wires blocks → detection → classification → enforcement.
///
/// Main-actor isolated, because it owns timers, windows and observable state that SwiftUI
/// reads. Window inspection runs off this actor.
@MainActor
@Observable
final class AppModel {
    /// One instance, because the app delegate and the watchdog handshake both need it.
    static let shared = AppModel()

    private static let log = Logger(subsystem: "com.beingpax.Shift", category: "AppModel")

    // MARK: Observable state

    let store: BlockStore

    private(set) var lastContext: ScreenContext?
    private(set) var lastVerdict: Verdict?
    private(set) var activity: [ActivityEvent] = []
    private(set) var accessibilityGranted = PermissionsManager.isAccessibilityTrusted
    private(set) var screenRecordingGranted = PermissionsManager.isScreenRecordingGranted
    private(set) var launchAtLoginEnabled = LaunchAtLogin.isEnabled

    /// Mirrors the engine so the UI can show whether Shift is actually watching.
    private(set) var isWatching = false

    /// Which section the main window is showing. Owned here so the menu bar and the
    /// Settings command can open the window straight to a section.
    var mainSection: MainSection = .dashboard
    var newBlock: Block?
    var unlockTarget: Block?

    var showNudges: Bool {
        didSet {
            Preferences.showNudges = showNudges
            intentNudges.reset()
            nudgeHysteresis.reset()
            if !showNudges { nudgeHUD.hide() }
        }
    }

    var showInDock: Bool {
        didSet {
            Preferences.showInDock = showInDock
            applyActivationPolicy()
        }
    }

    var driftKeywords: [String] {
        didSet { Preferences.driftKeywords = driftKeywords }
    }

    private(set) var hasCompletedOnboarding: Bool

    // MARK: Engine

    @ObservationIgnored private let monitor = ContextMonitor()
    @ObservationIgnored private let intentNudges = IntentNudgeMonitor()
    @ObservationIgnored private let shield = ShieldController()
    @ObservationIgnored private var resolvingProcesses: Set<pid_t> = []
    @ObservationIgnored private let nudgeHUD = NudgeHUDController()
    @ObservationIgnored private let nudgeLadder = NudgeLadder()
    @ObservationIgnored private let onboarding = OnboardingController()
    @ObservationIgnored private let mainWindow = MainWindowController()
    @ObservationIgnored private var hysteresis = Hysteresis(requiredHits: 2)
    @ObservationIgnored private var nudgeHysteresis = Hysteresis(requiredHits: 2)
    @ObservationIgnored private var engineTimer: Timer?
    @ObservationIgnored private var tickCount = 0

    @ObservationIgnored private var lastNudgeSignature: String?
    @ObservationIgnored private var lastNudgeAt = Date.distantPast
    @ObservationIgnored private let nudgeCooldown: TimeInterval = 120

    private init() {
        store = BlockStore()
        showNudges = Preferences.showNudges
        showInDock = Preferences.showInDock
        driftKeywords = Preferences.driftKeywords
        hasCompletedOnboarding = Preferences.hasCompletedOnboarding

        monitor.onSample = { [weak self] context in
            self?.handle(context)
        }
        monitor.onInvalidation = { [weak self] in
            self?.intentNudges.reset()
            self?.nudgeLadder.reset()
            self?.nudgeHUD.hide()
        }
    }

    // MARK: App lifecycle

    func applicationDidFinishLaunching() {
        PermissionsManager.logDiagnostics()
        applyActivationPolicy()
        observeActivation()
        refreshSystemState()
        startEngine()

        // Warm the app catalogue now. Scanning the application folders and pulling icons
        // takes a moment, and doing it when the picker opens makes the picker feel slow.
        InstalledApps.shared.loadIfNeeded()

        openApp()
    }

    func applicationWillTerminate() {
        // Only reached when termination was allowed, so no lock is standing.
        GuardState.clear()
        if WatchdogService.hasConfiguration { WatchdogService.remove() }
        monitor.stop()
        engineTimer?.invalidate()
        store.flushPendingSaves()
    }

    /// The app delegate asks before every polite quit.
    func shouldAllowTermination() -> Bool {
        guard !canQuitApp else { return true }
        warnCannotQuit()
        return false
    }

    /// Quitting is refused while any block is locked. That is what a lock means.
    var canQuitApp: Bool { !store.hasLockedBlock }

    // MARK: The engine

    /// One timer drives everything: retiring finished runs and locks, starting and
    /// stopping detection, and refreshing the watchdog handshake. Blocks change state on
    /// schedule boundaries, so something has to be watching the clock regardless.
    private func startEngine() {
        engineTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.engineTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        engineTimer = timer
        engineTick()
    }

    private func engineTick() {
        tickCount += 1
        store.tick()

        let active = store.activeBlocks
        let shouldWatch = !active.isEmpty

        if shouldWatch != isWatching {
            isWatching = shouldWatch
            if shouldWatch {
                monitor.start()
                refreshPermissions()
                if !accessibilityGranted { PermissionsManager.requestAccessibility() }
                log("Watching · \(active.count) block\(active.count == 1 ? "" : "s") active", symbol: "eye")
            } else {
                monitor.stop()
                lastContext = nil
                lastVerdict = nil
                shield.dismiss()
                nudgeLadder.reset()
                nudgeHUD.hide()
                hysteresis.reset()
                log("Nothing active", symbol: "eye.slash")
            }
        }

        syncLockProtections()

        // Permissions can change in System Settings even when no block is active.
        if tickCount % 5 == 0, isWatching || NSApp.isActive {
            refreshPermissions()
        }
    }

    // MARK: Detection → enforcement

    private func handle(_ context: ScreenContext) {
        let locationChanged = lastContext?.signature != context.signature
        if lastContext != context { lastContext = context }
        if locationChanged {
            lastVerdict = nil
            if nudgeLadder.key == nil { nudgeHUD.hide() }
        }
        guard !shield.isShowing, !resolvingProcesses.contains(context.processID) else { return }

        let evaluator = BlockEvaluator(blocks: store.activeBlocks, driftKeywords: driftKeywords)
        if let verdict = evaluator.ruleVerdict(for: context) {
            intentNudges.reset()
            apply(verdict, to: context)
            return
        }
        endLadder()
        hysteresis.reset()

        let goals = evaluator.intentGoals()
        let fallback = evaluator.fallbackVerdict(for: context, hasIntentGoals: !goals.isEmpty)
        guard let request = intentRequest(for: context, goals: goals) else {
            intentNudges.reset()
            apply(fallback, to: context)
            return
        }
        if lastVerdict == nil { apply(fallback, to: context) }

        intentNudges.observe(request) { [weak self] source in
            guard let self, !self.shield.isShowing, self.monitor.isRunning, self.lastContext == context,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == context.processID else { return false }
            let current = BlockEvaluator(blocks: self.store.activeBlocks, driftKeywords: self.driftKeywords)
            guard current.ruleVerdict(for: context) == nil,
                  self.intentRequest(for: context, goals: current.intentGoals()) == request else { return false }
            switch source {
            case .accessibility: return PermissionsManager.isAccessibilityTrusted
            case .screenOCR: return PermissionsManager.isScreenRecordingGranted
            default: return true
            }
        } onVerdict: { [weak self] verdict in
            self?.apply(verdict ?? fallback, to: context)
        }
    }

    private func intentRequest(for context: ScreenContext, goals: [IntentGoal]) -> IntentRequest? {
        guard showNudges, !goals.isEmpty, context.windowID != nil,
              accessibilityGranted || screenRecordingGranted, IntentClassifier.isModelAvailable else { return nil }
        return IntentRequest(context: context, goals: goals, accessibilityGranted: accessibilityGranted,
                             screenRecordingGranted: screenRecordingGranted)
    }

    private func apply(_ verdict: Verdict, to context: ScreenContext) {
        if lastVerdict != verdict { lastVerdict = verdict }
        switch verdict.kind {
        case .allow:
            hysteresis.reset()
            nudgeHysteresis.reset()
            endLadder()
        case .nudge:
            hysteresis.reset()
            endLadder()
            if verdict.source == .rules, !nudgeHysteresis.register(context.signature) { return }
            considerNudge(verdict, on: context)
        case .block:
            nudgeHysteresis.reset()
            guard let target = verdict.ruleTarget, let blockID = verdict.blockID else { return }
            // Keyed on the rule and the app, not the window signature: a page's title can
            // churn while the user sits on the same blocked site, and that must not restart
            // the ladder — otherwise it never reaches the shield.
            let key = "\(blockID.uuidString)|\(target.identifier)|\(context.processID)"
            // A new encounter still has to read consistently once, so a stray frame can't
            // open with a nudge. After that the ladder owns the timing.
            if key != nudgeLadder.key {
                guard hysteresis.register(key) else { return }
            }
            climbLadder(key: key, verdict: verdict, on: context)
        }
    }

    /// Nudge, re-check, nudge again, and only then cover the screen.
    ///
    /// Three nudges five seconds apart, each one re-verifying that the user is still on the
    /// same blocked thing. Closing the tab yourself at any point ends it with nothing having
    /// happened, which is the whole point: the habit is worth more than the punishment.
    private func climbLadder(key: String, verdict: Verdict, on context: ScreenContext) {
        let location = context.host ?? context.appName
        nudgeLadder.begin(
            key: key,
            onStep: { [weak self] step in
                guard let self else { return }
                let copy = Self.ladderCopy(
                    step: step,
                    location: location,
                    appName: context.appName,
                    blockName: verdict.blockName ?? "Shift"
                )
                self.nudgeHUD.ladder(step: step, headline: copy.headline, detail: copy.detail)
                self.log("Nudge \(step) of \(NudgeLadder.stepCount) · \(location)", symbol: "hand.wave")
            },
            onRest: { [weak self] in
                self?.nudgeHUD.hide()
            },
            isStillHere: { [weak self] in
                self?.isStillBlocked(context) ?? false
            },
            onExhausted: { [weak self] in
                guard let self, self.isStillBlocked(context) else { return }
                self.enforce(verdict, on: context)
            }
        )
    }

    /// The ladder only advances while the user is still looking at the same blocked thing.
    private func isStillBlocked(_ context: ScreenContext) -> Bool {
        guard !shield.isShowing, monitor.isRunning, lastContext == context,
              !resolvingProcesses.contains(context.processID),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == context.processID
        else { return false }
        let evaluator = BlockEvaluator(blocks: store.activeBlocks, driftKeywords: driftKeywords)
        return evaluator.ruleVerdict(for: context)?.kind == .block
    }

    /// Drops any ladder in progress and takes its nudge down with it.
    private func endLadder() {
        guard nudgeLadder.key != nil else { return }
        nudgeLadder.reset()
        nudgeHUD.hide()
    }

    /// What the character says at each rung.
    ///
    /// No counters and no "nudge 2 of 3": the creature's ears and colour already say how
    /// far along you are, and a tally made it read as a machine keeping score. Rung 2 asks
    /// a question, rung 3 states what is about to happen.
    private static func ladderCopy(
        step: Int,
        location: String,
        appName: String,
        blockName: String
    ) -> (headline: String, detail: String) {
        switch step {
        case ...1:
            return ("\(location) is blocked", "“\(blockName)” is on. Close it and get back to it.")
        case 2:
            return ("Still on \(location)?", "Close it yourself, or I'll handle it.")
        default:
            return (
                "I'll handle it now.",
                location == appName
                    ? "Closing \(appName)."
                    : "Closing \(appName) unless you leave \(location)."
            )
        }
    }

    private func considerNudge(_ verdict: Verdict, on context: ScreenContext) {
        guard showNudges else { return }

        let isRepeat = context.signature == lastNudgeSignature
        let withinCooldown = Date().timeIntervalSince(lastNudgeAt) < nudgeCooldown
        guard !(isRepeat && withinCooldown) else { return }

        lastNudgeSignature = context.signature
        lastNudgeAt = Date()

        let location = context.host ?? context.appName
        nudgeHUD.hint(reason: verdict.reason, detail: location)
        log("Nudged · \(location)", symbol: "arrow.turn.up.left")
    }

    private func enforce(_ verdict: Verdict, on context: ScreenContext) {
        guard verdict.kind == .block, verdict.source == .rules,
              let blockID = verdict.blockID,
              !resolvingProcesses.contains(context.processID) else { return }
        nudgeHUD.hide()

        let now = Date()
        store.recordTrigger(id: blockID, now: now)

        let breaks = store.block(id: blockID)?.breaks
        let breakMinutes = breaks.flatMap { $0.remaining(at: now) > 0 ? BreakPlan.minutes : nil }

        log("Blocked \(context.displayLocation)", symbol: "hand.raised.fill")

        let request = ShieldRequest(
            appName: context.appName,
            bundleID: context.bundleID,
            processID: context.processID,
            host: context.host,
            reason: verdict.reason,
            blockName: verdict.blockName ?? "Shift",
            blockID: blockID,
            breakMinutes: breakMinutes
        )
        shield.present(request) { [weak self] resolution in
            self?.resolve(resolution, for: request)
        }
    }

    private func resolve(_ resolution: ShieldResolution, for request: ShieldRequest) {
        hysteresis.reset()
        nudgeLadder.reset()
        guard !request.isPreview else { return }
        monitor.invalidate()

        let app = NSRunningApplication(processIdentifier: request.processID).flatMap {
            $0.bundleIdentifier == request.bundleID && !$0.isTerminated ? $0 : nil
        }
        switch resolution {
        case .quitApp:
            guard let app, resolvingProcesses.insert(request.processID).inserted else { return }
            Task { await quit(app, for: request) }
        case .takeBreak:
            if let blockID = request.blockID, store.startBreak(id: blockID) {
                log("Break started · \(request.blockName)", symbol: "cup.and.saucer")
            }
            app?.activate()
        }
    }

    private func quit(_ app: NSRunningApplication, for request: ShieldRequest) async {
        let pid = request.processID
        defer { resolvingProcesses.remove(pid) }

        app.activate()
        _ = app.terminate()
        for _ in 0..<12 {
            guard !app.isTerminated else { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard !app.isTerminated else {
            log("Quit \(request.appName)", symbol: "power")
            return
        }

        let dialog = await WindowInspector.quitDialog(pid: pid)
        if dialog == .present {
            log("Finish quitting \(request.appName) in its dialog", symbol: "power")
            while !app.isTerminated {
                try? await Task.sleep(for: .seconds(1))
                guard await WindowInspector.quitDialog(pid: pid) == .present else { break }
            }
            if app.isTerminated { log("Quit \(request.appName)", symbol: "power") }
            return
        }

        if app.isTerminated {
            log("Quit \(request.appName)", symbol: "power")
        } else if dialog == .absent, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  app.forceTerminate() {
            log("Force quit requested · \(request.appName)", symbol: "power")
        } else {
            log("Couldn’t quit \(request.appName)", symbol: "power")
        }
    }

    // MARK: Lock protections

    /// Keeps SIGTERM handling, the watchdog and the handshake file in step with whether
    /// any block is currently locked.
    private func syncLockProtections() {
        signal(SIGTERM, store.hasLockedBlock ? SIG_IGN : SIG_DFL)

        let guardState = GuardState.load()
        guard let deadline = store.lockedUntil else {
            if guardState != nil { GuardState.clear() }
            if WatchdogService.hasConfiguration { WatchdogService.remove() }
            return
        }

        let names = store.lockedBlocks.filter(\.isEnabled).map(\.name).joined(separator: ", ")
        if guardState?.lockedUntil != deadline || guardState?.goal != names || tickCount % 10 == 0 {
            GuardState(
                lockedUntil: deadline,
                bundlePath: Bundle.main.bundleURL.path,
                goal: names,
                heartbeat: Date()
            ).save()
        }
        if !WatchdogService.isInstalled { WatchdogService.install() }
    }

    private func warnCannotQuit() {
        let locked = store.lockedBlocks
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = locked.count == 1
            ? "“\(locked[0].name)” is locked."
            : "\(locked.count) blocks are locked."
        alert.informativeText = locked
            .map { "\($0.name): \($0.lockStatus())" }
            .joined(separator: "\n")
            + "\n\nRelease the active locks before quitting Shift."
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    // MARK: Previews

    func previewShield() {
        let request = ShieldRequest(
            appName: "Safari",
            bundleID: "com.apple.Safari",
            processID: 0,
            host: "instagram.com",
            reason: "instagram.com is blocked",
            blockName: "Deep work",
            blockID: nil,
            breakMinutes: BreakPlan.minutes,
            isPreview: true
        )
        shield.present(request) { [weak self] resolution in
            self?.resolve(resolution, for: request)
        }
    }

    /// `step` previews a rung of the escalation ladder; `nil` previews a soft hint.
    func previewNudge(step: Int? = nil) {
        guard let step else {
            nudgeHUD.hint(reason: "“Shorts” looks like a feed", detail: "youtube.com")
            return
        }
        let copy = Self.ladderCopy(step: step, location: "instagram.com", appName: "Safari", blockName: "Deep work")
        nudgeHUD.ladder(step: step, headline: copy.headline, detail: copy.detail)
    }

    // MARK: Windows

    func openApp() {
        if !hasCompletedOnboarding || onboarding.isShowing {
            presentOnboarding()
        } else {
            presentMainWindow()
        }
    }

    func presentNewBlock() {
        if newBlock == nil { newBlock = Block(name: "") }
        presentMainWindow()
    }

    func requestBlockUnlock(id: Block.ID) {
        guard let block = store.block(id: id), block.requiresUnlockChallenge() else { return }
        presentMainWindow()
        unlockTarget = block
    }

    func presentMainWindow(section: MainSection? = nil) {
        refreshPermissions()
        if let section { mainSection = section }
        mainWindow.present(model: self)
    }

    func presentOnboarding() {
        refreshPermissions()
        onboarding.present(model: self)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        Preferences.hasCompletedOnboarding = true
    }

    // MARK: Permissions and system state

    private func observeActivation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSystemState() }
        }
    }

    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    func refreshPermissions() {
        let accessibility = PermissionsManager.isAccessibilityTrusted
        let screenRecording = PermissionsManager.isScreenRecordingGranted
        guard accessibility != accessibilityGranted || screenRecording != screenRecordingGranted else { return }
        accessibilityGranted = accessibility
        screenRecordingGranted = screenRecording
        monitor.invalidate()
    }

    func requestAccessibilityPermission() {
        refreshPermissions()
        guard !accessibilityGranted else { return }
        PermissionsManager.requestAccessibility()
        PermissionsManager.openAccessibilitySettings()
    }

    func requestScreenRecordingPermission() {
        if !PermissionsManager.requestScreenRecording() {
            PermissionsManager.openScreenRecordingSettings()
        }
        refreshPermissions()
    }

    func refreshSystemState() {
        refreshPermissions()
        launchAtLoginEnabled = LaunchAtLogin.isEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LaunchAtLogin.setEnabled(enabled)
        launchAtLoginEnabled = LaunchAtLogin.isEnabled
    }

    // MARK: Activity log

    func log(_ text: String, symbol: String) {
        activity.insert(ActivityEvent(text, symbol: symbol), at: 0)
        if activity.count > 40 { activity.removeLast(activity.count - 40) }
    }
}

// MARK: - Preferences

/// Thin `UserDefaults` wrapper so key strings live in exactly one place.
enum Preferences {
    private enum Key {
        static let showNudges = "Shift.showNudges"
        static let showInDock = "Shift.showInDock"
        static let driftKeywords = "Shift.driftKeywords"
        static let hasCompletedOnboarding = "Shift.hasCompletedOnboarding.v1"
    }

    static var showNudges: Bool {
        get { UserDefaults.standard.object(forKey: Key.showNudges) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.showNudges) }
    }

    static var showInDock: Bool {
        get { UserDefaults.standard.bool(forKey: Key.showInDock) }
        set { UserDefaults.standard.set(newValue, forKey: Key.showInDock) }
    }

    static var driftKeywords: [String] {
        get { UserDefaults.standard.stringArray(forKey: Key.driftKeywords) ?? DriftKeywords.default }
        set { UserDefaults.standard.set(newValue, forKey: Key.driftKeywords) }
    }

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Key.hasCompletedOnboarding) }
        set { UserDefaults.standard.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }
}
