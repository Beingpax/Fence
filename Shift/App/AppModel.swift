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

    /// Strikes within the current stretch of active blocking, keyed by block.
    private(set) var strikes: [UUID: Int] = [:]

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

    private(set) var hasCompletedOnboarding: Bool

    // MARK: Engine

    @ObservationIgnored private let monitor = ContextMonitor()
    @ObservationIgnored private let shield = ShieldController()
    @ObservationIgnored private let nudgeHUD = NudgeHUDController()
    @ObservationIgnored private let onboarding = OnboardingController()
    @ObservationIgnored private let mainWindow = MainWindowController()
    @ObservationIgnored private var hysteresis = Hysteresis(requiredHits: 2)
    @ObservationIgnored private var nudgeHysteresis = Hysteresis(requiredHits: 2)
    @ObservationIgnored private var engineTimer: Timer?
    @ObservationIgnored private var tickCount = 0

    @ObservationIgnored private var lastNudgeSignature: String?
    @ObservationIgnored private var lastNudgeAt = Date.distantPast
    @ObservationIgnored private var nudgeContext: ScreenContext?
    @ObservationIgnored private let nudgeCooldown: TimeInterval = 120

    private init() {
        store = BlockStore()
        showNudges = Preferences.showNudges
        keepWatchdogAlways = Preferences.keepWatchdogAlways
        showInDock = Preferences.showInDock
        driftKeywords = Preferences.driftKeywords
        hasCompletedOnboarding = Preferences.hasCompletedOnboarding

        monitor.onSample = { [weak self] context in
            self?.handle(context)
        }
    }

    // MARK: App lifecycle

    func applicationDidFinishLaunching() {
        PermissionsManager.logDiagnostics()
        applyActivationPolicy()
        observeActivation()
        refreshSystemState()
        startEngine()

        if !hasCompletedOnboarding {
            presentOnboarding()
        } else if store.blocks.isEmpty {
            presentMainWindow()
        }
    }

    func applicationWillTerminate() {
        // Only reached when termination was allowed, so no lock is standing.
        GuardState.clear()
        monitor.stop()
        engineTimer?.invalidate()
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
                shield.dismiss()
                nudgeHUD.hide()
                strikes.removeAll()
                hysteresis.reset()
                log("Nothing active", symbol: "eye.slash")
            }
        }

        // Screen capture is the expensive tier, so it only turns on when a rule needs it.
        let needsScreenText = active.contains { !$0.list.keywords.isEmpty } && screenRecordingGranted
        if monitor.wantsScreenText != needsScreenText {
            monitor.wantsScreenText = needsScreenText
        }

        syncLockProtections()

        // Permissions change in System Settings; re-read occasionally while watching.
        if tickCount % 5 == 0, isWatching {
            refreshPermissions()
        }
    }

    // MARK: Detection → enforcement

    private func handle(_ context: ScreenContext) {
        if lastContext != context { lastContext = context }
        guard !shield.isShowing else { return }

        let evaluator = BlockEvaluator(blocks: store.activeBlocks, driftKeywords: driftKeywords)
        let verdict = evaluator.evaluate(context)
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
            guard hysteresis.register(context.signature) else { return }
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
        nudgeContext = context

        nudgeHUD.show(reason: verdict.reason, detail: context.displayLocation) { [weak self] in
            guard let self, let context = self.nudgeContext else { return }
            self.enforce(.block(verdict.reason), on: context)
        }
        log("Nudged · \(context.displayLocation)", symbol: "arrow.turn.up.left")
    }

    private func enforce(_ verdict: Verdict, on context: ScreenContext) {
        nudgeHUD.hide()

        let blockID = verdict.blockID
        let strike = (blockID.map { strikes[$0] ?? 0 } ?? 0) + 1
        if let blockID {
            strikes[blockID] = strike
            store.recordTrigger(id: blockID)
        }

        let block = blockID.flatMap { store.block(id: $0) }
        let offersBreak = block?.breaks.isEnabled == true && (block?.breaks.remainingToday ?? 0) > 0

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
            policy: .make(friction: verdict.friction, strike: strike),
            offersBreak: offersBreak
        )
        shield.present(request) { [weak self] resolution in
            self?.resolve(resolution, for: request)
        }
    }

    private func resolve(_ resolution: ShieldResolution, for request: ShieldRequest) {
        hysteresis.reset()
        guard !request.isPreview else { return }

        let app = NSRunningApplication(processIdentifier: request.processID)
        switch resolution {
        case .closeTab:
            let bundleID = request.bundleID
            Task { await Browser(bundleID: bundleID)?.closeFrontTab() }
            app?.activate()
            log("Closed tab · \(request.host ?? request.appName)", symbol: "xmark.circle")
        case .forceQuit:
            app?.forceTerminate()
            log("Quit \(request.appName)", symbol: "power")
        case .wrongCall:
            // Teaches the block, permanently, because the user said it was wrong.
            if let blockID = request.blockID, var block = store.block(id: blockID) {
                let entry = request.host ?? request.bundleID
                if !block.list.exceptions.contains(entry) {
                    block.list.exceptions.append(entry)
                    store.updateRuntime(block)
                }
                log("Wrong call · \(entry) added to \(block.name) exceptions", symbol: "arrow.uturn.backward")
            }
            app?.activate()
        case .takeBreak:
            if let blockID = request.blockID, store.startBreak(id: blockID) {
                monitor.invalidateScreenTextCache()
                log("Break started · \(request.blockName)", symbol: "cup.and.saucer")
            }
            app?.activate()
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
        let names = store.blocks.filter { $0.lock.isLocked() }.map(\.name)
        guard let deadline = store.lockedUntil else { return }
        GuardState(
            lockedUntil: deadline,
            bundlePath: Bundle.main.bundleURL.path,
            goal: names.joined(separator: ", "),
            heartbeat: Date()
        ).save()
    }

    private func warnCannotQuit() {
        let locked = store.blocks.filter { $0.lock.isLocked() }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = locked.count == 1
            ? "“\(locked[0].name)” is locked."
            : "\(locked.count) blocks are locked."
        alert.informativeText = locked
            .map { "\($0.name): \($0.lock.statusText())" }
            .joined(separator: "\n")
            + "\n\nShift can't be quit while a lock is standing. That's the point of locking it."
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
            policy: .make(friction: .firm, strike: strike),
            offersBreak: strike == 1,
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

    func presentMainWindow() {
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
        if accessibility != accessibilityGranted { accessibilityGranted = accessibility }
        if screenRecording != screenRecordingGranted { screenRecordingGranted = screenRecording }
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
        static let showNudges = "Shift.showNudges"
        static let keepWatchdogAlways = "Shift.keepWatchdogAlways"
        static let showInDock = "Shift.showInDock"
        static let driftKeywords = "Shift.driftKeywords"
        static let hasCompletedOnboarding = "Shift.hasCompletedOnboarding.v1"
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

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Key.hasCompletedOnboarding) }
        set { UserDefaults.standard.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }
}
