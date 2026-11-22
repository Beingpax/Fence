import AppKit
import Observation
import os.log

/// Wires blocks → detection → classification → enforcement.
///
/// Main-actor isolated, because it owns timers, windows and observable state that SwiftUI
/// reads. Everything genuinely slow happens behind an `await`: window titles, Apple Events
/// and screen capture all run off this actor and come back as finished values.
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
    private(set) var watchdogInstalled = WatchdogService.isInstalled

    /// Mirrors the engine so the UI can show whether Shift is actually watching.
    private(set) var isWatching = false

    /// Which section the main window is showing. Owned here so the menu bar and the
    /// Settings command can open the window straight to a section.
    var mainSection: MainSection = .dashboard
    var unlockTarget: Block?

    var showNudges: Bool {
        didSet { Preferences.showNudges = showNudges }
    }

    var keepWatchdogAlways: Bool {
        didSet {
            Preferences.keepWatchdogAlways = keepWatchdogAlways
            syncWatchdogInstallation()
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

    var compareTextReaders: Bool {
        didSet {
            Preferences.compareTextReaders = compareTextReaders
            resetIntent()
            monitor.invalidate()
        }
    }

    var intentModelAvailable: Bool { IntentClassifier.isModelAvailable }

    private(set) var hasCompletedOnboarding: Bool

    // MARK: Engine

    private struct EvaluatedIntent {
        let request: IntentRequest
        let reading: IntentReading
        let verdict: Verdict?
        let needsConfirmation: Bool
    }

    @ObservationIgnored private var dailyStrikes = Preferences.dailyStrikes
    @ObservationIgnored private let monitor = ContextMonitor()
    @ObservationIgnored private let intentClassifier = IntentClassifier()
    @ObservationIgnored private var intentTask: Task<Void, Never>?
    @ObservationIgnored private var intentInFlight: IntentRequest?
    @ObservationIgnored private var evaluatedIntent: EvaluatedIntent?
    @ObservationIgnored private let shield = ShieldController()
    @ObservationIgnored private var resolvingProcesses: Set<pid_t> = []
    @ObservationIgnored private let nudgeHUD = NudgeHUDController()
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
        keepWatchdogAlways = Preferences.keepWatchdogAlways
        showInDock = Preferences.showInDock
        driftKeywords = Preferences.driftKeywords
        compareTextReaders = Preferences.compareTextReaders
        hasCompletedOnboarding = Preferences.hasCompletedOnboarding

        monitor.onSample = { [weak self] context in
            self?.handle(context)
        }
        monitor.onInvalidation = { [weak self] in
            self?.intentTask?.cancel()
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

        if !hasCompletedOnboarding {
            presentOnboarding()
        } else {
            presentMainWindow()
        }
    }

    func applicationWillTerminate() {
        // Only reached when termination was allowed, so no lock is standing.
        GuardState.clear()
        monitor.stop()
        resetIntent()
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
                resetIntent()
                lastContext = nil
                lastVerdict = nil
                shield.dismiss()
                nudgeHUD.hide()
                hysteresis.reset()
                log("Nothing active", symbol: "eye.slash")
            }
        }

        monitor.trackInteraction(active.contains { !$0.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && (accessibilityGranted || screenRecordingGranted))
        syncLockProtections()

        // Permissions change in System Settings; re-read occasionally while watching.
        if tickCount % 5 == 0, isWatching {
            refreshPermissions()
        }
    }

    // MARK: Detection → enforcement

    private func handle(_ context: ScreenContext) {
        let locationChanged = lastContext?.signature != context.signature
        if lastContext != context { lastContext = context }
        if locationChanged {
            lastVerdict = nil
            nudgeHUD.hide()
        }
        guard !shield.isShowing, !resolvingProcesses.contains(context.processID) else { return }

        let evaluator = BlockEvaluator(blocks: store.activeBlocks, driftKeywords: driftKeywords)
        if let verdict = evaluator.ruleVerdict(for: context) {
            resetIntent()
            apply(verdict, to: context)
            return
        }

        guard let request = intentRequest(for: context, evaluator: evaluator) else {
            resetIntent()
            apply(evaluator.fallbackVerdict(for: context, hasIntentGoals: !evaluator.intentGoals().isEmpty), to: context)
            return
        }

        let fallback = evaluator.fallbackVerdict(for: context, hasIntentGoals: true)
        guard monitor.interactionIsSettled else {
            intentTask?.cancel()
            hysteresis.reset()
            if lastVerdict != fallback { lastVerdict = fallback }
            return
        }

        if let result = evaluatedIntent, result.request == request, !result.needsConfirmation {
            if hasPermission(for: result.verdict?.source) {
                apply(result.verdict ?? fallback, to: context, intentConfirmed: false)
            } else {
                refreshPermissions()
                apply(fallback, to: context)
            }
            return
        }

        if intentInFlight != request { intentTask?.cancel() }
        guard intentTask == nil else { return }

        let previous = evaluatedIntent.flatMap { request.canReuse($0.request) ? $0.reading : nil }
        let confirming = evaluatedIntent?.request == request && evaluatedIntent?.needsConfirmation == true
        intentInFlight = request
        intentTask = Task { [weak self, intentClassifier] in
            let reading = await intentClassifier.classify(request, previous: previous)
            guard let self else { return }
            self.intentTask = nil
            self.intentInFlight = nil
            guard !Task.isCancelled, !self.shield.isShowing, self.monitor.isCurrent(context),
                  self.intentRequest(for: context) == request,
                  self.hasPermission(for: reading.verdict?.source)
            else { return }

            var verdict = reading.verdict
            let confirmed = confirming && verdict?.kind == .block
                && previous?.verdict?.blockID == verdict?.blockID
                && previous?.verdict?.source == verdict?.source
            if confirming, verdict?.kind == .block, !confirmed {
                verdict?.kind = .nudge
            }

            self.apply(verdict ?? fallback, to: context, intentConfirmed: confirmed)
            self.evaluatedIntent = EvaluatedIntent(
                request: request,
                reading: reading,
                verdict: verdict,
                needsConfirmation: verdict?.kind == .block && !confirming
            )
        }
    }

    private func intentRequest(for context: ScreenContext, evaluator: BlockEvaluator? = nil) -> IntentRequest? {
        let evaluator = evaluator ?? BlockEvaluator(blocks: store.activeBlocks, driftKeywords: driftKeywords)
        guard evaluator.ruleVerdict(for: context) == nil, context.windowID != nil,
              accessibilityGranted || screenRecordingGranted
        else { return nil }
        let goals = evaluator.intentGoals()
        guard !goals.isEmpty else { return nil }
        return IntentRequest(
            context: context,
            goals: goals,
            accessibilityGranted: accessibilityGranted,
            screenRecordingGranted: screenRecordingGranted,
            compareTextReaders: compareTextReaders
        )
    }

    private func hasPermission(for source: Verdict.Source?) -> Bool {
        switch source {
        case .accessibility: PermissionsManager.isAccessibilityTrusted
        case .screenOCR: PermissionsManager.isScreenRecordingGranted
        default: true
        }
    }

    private func resetIntent() {
        intentTask?.cancel()
        evaluatedIntent = nil
    }

    private func apply(
        _ verdict: Verdict, to context: ScreenContext,
        intentConfirmed: Bool? = nil
    ) {
        if lastVerdict != verdict { lastVerdict = verdict }
        switch verdict.kind {
        case .allow:
            hysteresis.reset()
            nudgeHysteresis.reset()
        case .nudge:
            hysteresis.reset()
            considerNudge(verdict, on: context)
        case .block:
            nudgeHysteresis.reset()
            if let intentConfirmed {
                guard intentConfirmed else { return }
            } else {
                let signature = "\(context.signature)|\(verdict.blockID?.uuidString ?? "")"
                guard hysteresis.register(signature) else { return }
            }
            enforce(verdict, on: context)
        }
    }

    private func considerNudge(_ verdict: Verdict, on context: ScreenContext) {
        guard showNudges else { return }
        guard nudgeHysteresis.register(context.signature) else { return }

        let isRepeat = context.signature == lastNudgeSignature
        let withinCooldown = Date().timeIntervalSince(lastNudgeAt) < nudgeCooldown
        guard !(isRepeat && withinCooldown) else { return }

        lastNudgeSignature = context.signature
        lastNudgeAt = Date()

        nudgeHUD.show(reason: verdict.reason, detail: context.displayLocation) { [weak self] in
            guard let self, self.monitor.isCurrent(context), !self.shield.isShowing,
                  self.hasPermission(for: verdict.source),
                  verdict.blockID.map({ id in self.store.activeBlocks.contains { $0.id == id } }) ?? true
            else { return }
            var block = verdict
            block.kind = .block
            self.enforce(block, on: context)
        }
        log("Nudged · \(context.displayLocation)", symbol: "arrow.turn.up.left")
    }

    private func enforce(_ verdict: Verdict, on context: ScreenContext) {
        guard !resolvingProcesses.contains(context.processID) else { return }
        nudgeHUD.hide()

        let now = Date()
        let blockID = verdict.blockID
        let target = verdict.ruleTarget ?? context.host.map(StrikeTarget.website)
            ?? .app(context.bundleID.lowercased())
        let strike = dailyStrikes.record(target, blockID: blockID, now: now)
        Preferences.dailyStrikes = dailyStrikes
        if let blockID { store.recordTrigger(id: blockID, now: now) }

        let breaks = blockID.flatMap { store.block(id: $0)?.breaks }
        let breakMinutes = breaks.flatMap { $0.remaining(at: now) > 0 ? BreakPlan.minutes : nil }

        log("Blocked \(context.displayLocation)", symbol: "hand.raised.fill")

        let request = ShieldRequest(
            appName: context.appName,
            bundleID: context.bundleID,
            processID: context.processID,
            host: context.host,
            isBrowser: context.isBrowser,
            reason: verdict.reason,
            blockName: verdict.blockName ?? "Shift",
            blockID: blockID,
            goal: verdict.goal,
            strike: strike,
            policy: .make(strike: strike),
            breakMinutes: breakMinutes
        )
        shield.present(request) { [weak self] resolution in
            self?.resolve(resolution, for: request, context: context)
        }
    }

    private func resolve(
        _ resolution: ShieldResolution, for request: ShieldRequest,
        context: ScreenContext? = nil
    ) {
        hysteresis.reset()
        guard !request.isPreview else { return }
        resetIntent()
        monitor.invalidate()

        let app = NSRunningApplication(processIdentifier: request.processID).flatMap {
            $0.bundleIdentifier == request.bundleID && !$0.isTerminated ? $0 : nil
        }
        switch resolution {
        case .closeTab:
            guard let context, let browser = Browser(bundleID: context.bundleID), let app,
                  resolvingProcesses.insert(request.processID).inserted else { return }
            app.activate()
            Task {
                defer { resolvingProcesses.remove(request.processID) }
                let snapshot = await WindowInspector.snapshot(
                    pid: context.processID, browser: browser, prepareAccessibility: false
                )
                let sameTab = !app.isTerminated && NSWorkspace.shared.frontmostApplication?.processIdentifier == context.processID
                    && context.windowID != nil && snapshot.windowID == context.windowID && snapshot.url == context.url
                    && (context.url != nil || (context.windowTitle != nil && snapshot.title == context.windowTitle))
                let closed = sameTab ? await browser.closeFrontTab(pid: context.processID, expectedURL: context.url) : false
                let result = closed ? "Close requested" : "Couldn’t close tab"
                log("\(result) · \(context.displayLocation)", symbol: "xmark.circle")
            }
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
        let locked = store.hasLockedBlock

        if locked {
            signal(SIGTERM, SIG_IGN)
            if !WatchdogService.isInstalled {
                _ = WatchdogService.install()
                watchdogInstalled = WatchdogService.isInstalled
            }
            if tickCount % 10 == 0 || GuardState.load() == nil {
                writeGuardState()
            }
        } else {
            signal(SIGTERM, SIG_DFL)
            if GuardState.load() != nil {
                GuardState.clear()
                syncWatchdogInstallation()
            }
        }
    }

    private func writeGuardState() {
        let names = store.lockedBlocks.map(\.name)
        guard let deadline = store.lockedUntil else { return }
        GuardState(
            lockedUntil: deadline,
            bundlePath: Bundle.main.bundleURL.path,
            goal: names.joined(separator: ", "),
            heartbeat: Date()
        ).save()
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

    func previewShield(strike: Int) {
        let request = ShieldRequest(
            appName: "Safari",
            bundleID: "com.apple.Safari",
            processID: 0,
            host: "instagram.com",
            isBrowser: true,
            reason: "instagram.com is blocked",
            blockName: "Deep work",
            blockID: nil,
            goal: "Finish chapter 3",
            strike: strike,
            policy: .make(strike: strike),
            breakMinutes: strike == 1 ? BreakPlan.minutes : nil,
            isPreview: true
        )
        shield.present(request) { [weak self] resolution in
            self?.resolve(resolution, for: request)
        }
    }

    func previewNudge() {
        nudgeHUD.show(reason: "“Shorts” looks like a feed", detail: "youtube.com", onBlock: {})
    }

    // MARK: Windows

    func requestBlockUnlock(id: Block.ID) {
        guard let block = store.block(id: id), block.requiresUnlockChallenge() else { return }
        presentMainWindow()
        unlockTarget = block
    }

    func presentMainWindow(section: MainSection? = nil) {
        if let section { mainSection = section }
        mainWindow.present(model: self)
    }

    func presentOnboarding() {
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
        resetIntent()
        monitor.invalidate()
    }

    func requestAccessibilityPermission() {
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
        watchdogInstalled = WatchdogService.isInstalled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LaunchAtLogin.setEnabled(enabled)
        launchAtLoginEnabled = LaunchAtLogin.isEnabled
    }

    private func syncWatchdogInstallation() {
        if keepWatchdogAlways || store.hasLockedBlock {
            if !WatchdogService.isInstalled { _ = WatchdogService.install() }
        } else if WatchdogService.isInstalled {
            _ = WatchdogService.remove()
        }
        watchdogInstalled = WatchdogService.isInstalled
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
        static let dailyStrikes = "Shift.dailyStrikes"
        static let showNudges = "Shift.showNudges"
        static let keepWatchdogAlways = "Shift.keepWatchdogAlways"
        static let showInDock = "Shift.showInDock"
        static let driftKeywords = "Shift.driftKeywords"
        static let compareTextReaders = "Shift.compareTextReaders"
        static let hasCompletedOnboarding = "Shift.hasCompletedOnboarding.v1"
    }

    static var dailyStrikes: DailyStrikeCounts {
        get {
            guard let data = UserDefaults.standard.data(forKey: Key.dailyStrikes),
                  let counts = try? JSONDecoder().decode(DailyStrikeCounts.self, from: data)
            else { return DailyStrikeCounts() }
            return counts
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Key.dailyStrikes)
            }
        }
    }

    static var showNudges: Bool {
        get { UserDefaults.standard.object(forKey: Key.showNudges) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.showNudges) }
    }

    static var keepWatchdogAlways: Bool {
        get { UserDefaults.standard.bool(forKey: Key.keepWatchdogAlways) }
        set { UserDefaults.standard.set(newValue, forKey: Key.keepWatchdogAlways) }
    }

    static var showInDock: Bool {
        get { UserDefaults.standard.bool(forKey: Key.showInDock) }
        set { UserDefaults.standard.set(newValue, forKey: Key.showInDock) }
    }

    static var driftKeywords: [String] {
        get { UserDefaults.standard.stringArray(forKey: Key.driftKeywords) ?? DriftKeywords.default }
        set { UserDefaults.standard.set(newValue, forKey: Key.driftKeywords) }
    }

    static var compareTextReaders: Bool {
        get { UserDefaults.standard.bool(forKey: Key.compareTextReaders) }
        set { UserDefaults.standard.set(newValue, forKey: Key.compareTextReaders) }
    }

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Key.hasCompletedOnboarding) }
        set { UserDefaults.standard.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }
}
