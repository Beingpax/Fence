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
    /// Every reach for a blocked site, and the plans written in the weekly review.
    @ObservationIgnored private(set) lazy var urges = UrgeLog()

    private(set) var lastContext: ScreenContext?
    private(set) var lastVerdict: Verdict?
    private(set) var activity: [ActivityEvent] = []
    private(set) var accessibilityGranted = PermissionsManager.isAccessibilityTrusted
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
            nudgeHysteresis.reset()
            if !showNudges { nudgeHUD.hideHint() }
        }
    }

    /// Whether the pause and the reward make their sounds.
    var playNudgeSounds: Bool {
        didSet { Preferences.playNudgeSounds = playNudgeSounds }
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
    @ObservationIgnored private let nudgeHUD = NudgeHUDController()
    @ObservationIgnored private let pause = PauseController()
    /// When each site was last reached for, per block, for escalation.
    @ObservationIgnored private var reaches: [String: [Date]] = [:]
    /// The tab is being closed in this process; ignore it until then, or a sample landing
    /// before Command-W would open a second pause for the page that's on its way out.
    /// "I need it": one site, let through until this time. The block itself stays on.
    @ObservationIgnored private var allowances: [String: Date] = [:]
    @ObservationIgnored private var allowanceTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var closingPID: pid_t?
    @ObservationIgnored private var closingUntil = Date.distantPast
    @ObservationIgnored private let onboarding = OnboardingController()
    @ObservationIgnored private let mainWindow = MainWindowController()
    @ObservationIgnored private var hysteresis = Hysteresis(requiredHits: 2)
    @ObservationIgnored private var nudgeHysteresis = Hysteresis(requiredHits: 2)
    @ObservationIgnored private var engineTimer: Timer?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var tickCount = 0

    @ObservationIgnored private var lastNudgeSignature: String?
    @ObservationIgnored private var lastNudgeAt = Date.distantPast
    @ObservationIgnored private let nudgeCooldown: TimeInterval = 120

    private init() {
        store = BlockStore()
        showNudges = Preferences.showNudges
        playNudgeSounds = Preferences.playNudgeSounds
        showInDock = Preferences.showInDock
        driftKeywords = Preferences.driftKeywords
        hasCompletedOnboarding = Preferences.hasCompletedOnboarding

        monitor.onSample = { [weak self] context in
            self?.handle(context)
        }
        monitor.onInvalidation = { [weak self] in
            self?.nudgeHUD.hideHint()
        }
    }

    // MARK: App lifecycle

    func applicationDidFinishLaunching() {
        PermissionsManager.logDiagnostics()
        applyActivationPolicy()
        observeActivation()
        refreshSystemState()
        startEngine()

        if !CommandLine.arguments.contains(WatchdogService.backgroundLaunchFlag) { openApp() }
    }

    func applicationWillTerminate() {
        // Only reached when termination was allowed, so no lock is standing.
        GuardState.clear()
        if WatchdogService.hasConfiguration { WatchdogService.remove() }
        monitor.stop()
        engineTimer?.invalidate()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
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
        if tickCount % 60 == 0, !reaches.isEmpty {
            let cutoff = Date().addingTimeInterval(-Self.reachWindow)
            reaches = reaches.compactMapValues { dates in
                let recent = dates.filter { $0 > cutoff }
                return recent.isEmpty ? nil : recent
            }
        }

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
                pause.dismiss()
                allowanceTasks.values.forEach { $0.cancel() }
                allowanceTasks.removeAll()
                allowances.removeAll()
                nudgeHUD.hideHint()
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
            nudgeHUD.hideHint()
        }
        guard !pause.isShowing else { return }

        let evaluator = BlockEvaluator(blocks: store.activeBlocks, driftKeywords: driftKeywords)
        if let verdict = evaluator.ruleVerdict(for: context) {
            apply(verdict, to: context)
            return
        }
        hysteresis.reset()
        apply(evaluator.fallbackVerdict(for: context), to: context)
    }

    private func apply(_ verdict: Verdict, to context: ScreenContext) {
        if lastVerdict != verdict { lastVerdict = verdict }
        switch verdict.kind {
        case .allow:
            hysteresis.reset()
            nudgeHysteresis.reset()
        case .nudge:
            hysteresis.reset()
            if verdict.source == .rules, !nudgeHysteresis.register(context.signature) { return }
            considerNudge(verdict, on: context)
        case .block:
            nudgeHysteresis.reset()
            guard let key = encounterKey(for: verdict, context: context),
                  let reachKey = reachKey(for: verdict) else { return }
            // Already pausing, closing the page this came from, or let through for a minute.
            if pause.isShowing { return }
            if let until = allowances[reachKey], until > Date() { return }
            if context.processID == closingPID, Date() < closingUntil { return }
            // A new encounter has to read the same twice, so a stray frame can't trigger
            // anything. The second reading is requested straight away instead of waiting
            // for the next poll, which keeps the pause ahead of the page load.
            guard hysteresis.register(key) else {
                monitor.resampleSoon()
                return
            }
            beginReach(key: key, reachKey: reachKey, verdict: verdict, context: context)
        }
    }

    // MARK: The pause

    /// How long a reach is remembered when deciding how hard the next one should be.
    private static let reachWindow: TimeInterval = 3600
    static let previewKey = "preview"

    /// One reach for a blocked site.
    ///
    /// The first in an hour gets a five-second breath before the choices open, the second
    /// fifteen, and every one after that thirty. Every repeat costs more, so coming back is
    /// never free, and switching away and back can't reset anything: the count is per site.
    private func beginReach(key: String, reachKey: String, verdict: Verdict, context: ScreenContext) {
        let now = Date()
        var recent = (reaches[reachKey] ?? []).filter { now.timeIntervalSince($0) < Self.reachWindow }
        // Every reach from the third onward uses the same escalation level.
        if recent.count == 3 { recent.removeFirst() }
        recent.append(now)
        reaches[reachKey] = recent
        let target = context.host ?? context.appName

        guard let blockID = verdict.blockID else { return }
        store.recordTrigger(id: blockID, now: now)
        let breaks = store.block(id: blockID)?.breaks
        let copy = PauseCopy.pause(visit: recent.count, target: target)
        let request = PauseRequest(
            blockName: verdict.blockName ?? "Shift",
            blockID: blockID,
            ruleTarget: verdict.ruleTarget,
            target: target,
            appName: context.appName,
            isBrowser: Browser(bundleID: context.bundleID) != nil,
            visit: recent.count,
            breaksLeft: breaks.flatMap { $0.isEnabled ? $0.remaining(at: now) : nil },
            plans: urges.plans,
            title: copy.title,
            subtitle: copy.subtitle
        )
        nudgeHUD.hide()
        if playNudgeSounds { request.visit >= 3 ? NudgeSound.playDeep() : NudgeSound.playPause() }
        log("Paused · \(target)", symbol: "wind")
        pause.present(request, key: key) { [weak self] event in
            self?.handlePause(event, key: key, request: request, context: context)
        }
    }

    private func handlePause(_ event: PauseEvent, key: String, request: PauseRequest, context: ScreenContext) {
        guard pause.key == key else { return }
        pause.dismiss()
        hysteresis.reset()

        switch event {
        case .close(let reason):
            closeTarget(context, isPreview: request.isPreview)
            if !request.isPreview {
                urges.record(UrgeEvent(date: Date(), blockName: request.blockName, target: request.target,
                                       reason: reason, outcome: .closed))
            }
            reward(PauseCopy.reward(for: reason, visit: request.visit))
            log("Turned back · \(request.target)\(reason.map { " · \($0.shortLabel)" } ?? "")",
                symbol: "arrow.uturn.backward")

        case .takeBreak(let minutes, let note):
            let headline = "\(minutes) minute\(minutes == 1 ? "" : "s"). Go do it."
            guard !request.isPreview else {
                nudgeHUD.status(headline: headline, detail: note)
                return
            }
            guard let blockID = request.blockID, store.spendBreak(id: blockID) else {
                // No break left after all (or the block went quiet meanwhile), so this is
                // a close.
                closeTarget(context, isPreview: false)
                nudgeHUD.status(headline: "No breaks left today.", detail: "Closed it for you. Back to \(request.blockName).")
                return
            }
            urges.record(UrgeEvent(date: Date(), blockName: request.blockName, target: request.target,
                                   reason: .needed, outcome: .allowed, note: note))
            nudgeHUD.status(headline: headline, detail: note)
            log("\(minutes) min on \(request.target) · \(note)", symbol: "cup.and.saucer")
            if let reachKey = reachKey(for: request) {
                allow(reachKey: reachKey, minutes: minutes)
            }
        }
    }

    /// Lets one site through for `minutes`. The block stays on and keeps blocking
    /// everything else. When the time is up, Shift reads the screen again: still there means
    /// a new reach, so the pause comes back.
    private func allow(reachKey: String, minutes: Int) {
        allowances[reachKey] = Date().addingTimeInterval(TimeInterval(minutes) * 60)
        allowanceTasks[reachKey]?.cancel()
        allowanceTasks[reachKey] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled, let self else { return }
            self.allowances[reachKey] = nil
            self.allowanceTasks[reachKey] = nil
            self.hysteresis.reset()
            self.monitor.resampleSoon()
        }
    }

    /// The same key `reachKey(for: Verdict)` builds, from what the pause was shown for.
    private func reachKey(for request: PauseRequest) -> String? {
        guard let blockID = request.blockID, let target = request.ruleTarget else { return nil }
        return "\(blockID.uuidString)|\(target.identifier)"
    }

    private func closeTarget(_ context: ScreenContext, isPreview: Bool) {
        guard !isPreview else { return }
        hysteresis.reset()
        closingPID = context.processID
        closingUntil = Date().addingTimeInterval(1.5)
        if Browser(bundleID: context.bundleID) != nil {
            Task { await TabCloser.closeFrontTab(pid: context.processID) }
        } else {
            TabCloser.quit(pid: context.processID)
        }
    }

    // MARK: Reward

    /// Praise, the moment someone turns back. This is the step that builds the habit:
    /// behaviour that's rewarded straight away repeats, and before this, turning back got
    /// nothing at all.
    ///
    /// Over a hundred lines in `PauseCopy`, specific to what they named where possible and
    /// dealt so none repeats soon, because the same line every time stops being heard.
    private func reward(_ message: PauseCopy.Line) {
        nudgeHUD.reward(headline: message.title, detail: message.subtitle)
        if playNudgeSounds { NudgeSound.playReward() }
    }

    // MARK: Encounters

    /// One encounter: this block's rule, in this process. Not the window signature, because
    /// a page's title churns while the person sits on the same blocked site.
    private func encounterKey(for verdict: Verdict, context: ScreenContext) -> String? {
        guard verdict.kind == .block, verdict.source == .rules,
              let blockID = verdict.blockID, let target = verdict.ruleTarget else { return nil }
        return "\(blockID.uuidString)|\(target.identifier)|\(context.processID)"
    }

    /// The thing reached for, across visits and processes. Escalation and allowances
    /// key on this, so quitting and reopening the browser doesn't reset them.
    private func reachKey(for verdict: Verdict) -> String? {
        guard let blockID = verdict.blockID, let target = verdict.ruleTarget else { return nil }
        return "\(blockID.uuidString)|\(target.identifier)"
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

    /// The pause as it looks on a first, second or third reach within the hour.
    func previewPause(visit: Int = 1) {
        let copy = PauseCopy.pause(visit: visit, target: "instagram.com")
        let request = PauseRequest(
            blockName: "Deep work", blockID: nil, ruleTarget: nil, target: "instagram.com", appName: "Safari",
            isBrowser: true, visit: visit, breaksLeft: BreakPlan.dailyAllowance,
            plans: urges.plans,
            title: copy.title, subtitle: copy.subtitle, isPreview: true
        )
        let context = ScreenContext(bundleID: "com.apple.Safari", appName: "Safari", processID: 0)
        if playNudgeSounds { visit >= 3 ? NudgeSound.playDeep() : NudgeSound.playPause() }
        pause.present(request, key: Self.previewKey) { [weak self] event in
            self?.handlePause(event, key: Self.previewKey, request: request, context: context)
        }
    }

    func previewReward() {
        reward(PauseCopy.reward(for: nil, visit: 1))
    }

    func previewHint() {
        nudgeHUD.hint(reason: "“Shorts” looks like a feed", detail: "youtube.com")
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
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
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
        guard accessibility != accessibilityGranted else { return }
        accessibilityGranted = accessibility
        monitor.invalidate()
    }

    func requestAccessibilityPermission() {
        refreshPermissions()
        guard !accessibilityGranted else { return }
        PermissionsManager.requestAccessibility()
        PermissionsManager.openAccessibilitySettings()
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
        static let playNudgeSounds = "Shift.playNudgeSounds"
        static let driftKeywords = "Shift.driftKeywords"
        static let hasCompletedOnboarding = "Shift.hasCompletedOnboarding.v1"
    }

    static var showNudges: Bool {
        get { UserDefaults.standard.object(forKey: Key.showNudges) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.showNudges) }
    }

    static var playNudgeSounds: Bool {
        get { UserDefaults.standard.object(forKey: Key.playNudgeSounds) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.playNudgeSounds) }
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
