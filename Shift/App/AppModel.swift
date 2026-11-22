import AppKit
import Observation
import os.log

/// Owns the session and wires detection → classification → enforcement.
@MainActor
@Observable
final class AppModel {
    /// One instance, because `AppDelegate` and the watchdog handshake both need to reach it.
    static let shared = AppModel()

    private static let log = Logger(subsystem: "com.beingpax.Shift", category: "AppModel")

    // MARK: Observable state

    private(set) var session: FocusSession?
    private(set) var lastContext: ScreenContext?
    private(set) var lastVerdict: Verdict?
    private(set) var activity: [ActivityEvent] = []
    private(set) var accessibilityGranted = PermissionsManager.isAccessibilityTrusted
    private(set) var screenRecordingGranted = PermissionsManager.isScreenRecordingGranted

    /// Mirrors `SMAppService`, which the user can change behind our back in System Settings.
    private(set) var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    /// Whether the watchdog launch agent is currently loaded.
    private(set) var watchdogInstalled = WatchdogService.isInstalled

    var rules: BlockRules = .load() {
        didSet { rules.save() }
    }

    /// Show the HUD for `nudge` verdicts. PRD §9: nudges never raise the shield.
    var showNudges: Bool {
        didSet { Preferences.showNudges = showNudges }
    }

    /// Keep the watchdog installed outside Locked sessions too. Off by default, because
    /// a background agent the user didn't ask for is rude.
    var keepWatchdogAlways: Bool {
        didSet {
            Preferences.keepWatchdogAlways = keepWatchdogAlways
            syncWatchdogInstallation()
        }
    }

    /// Shift is a menu bar app, so it hides from the Dock by default. Some people want
    /// the Dock icon anyway, and the activation policy can be switched at runtime.
    var showInDock: Bool {
        didSet {
            Preferences.showInDock = showInDock
            applyActivationPolicy()
        }
    }

    private(set) var hasCompletedOnboarding: Bool

    // MARK: Engine

    @ObservationIgnored private let monitor = ContextMonitor()
    @ObservationIgnored private let shield = ShieldController()
    @ObservationIgnored private let nudgeHUD = NudgeHUDController()
    @ObservationIgnored private let onboarding = OnboardingController()
    @ObservationIgnored private var hysteresis = Hysteresis(requiredHits: 2)
    @ObservationIgnored private var nudgeHysteresis = Hysteresis(requiredHits: 2)
    @ObservationIgnored private var expiryTimer: Timer?
    @ObservationIgnored private var heartbeatTick = 0

    /// Rate limiting so one lingering feed can't nudge every two seconds.
    @ObservationIgnored private var lastNudgeSignature: String?
    @ObservationIgnored private var lastNudgeAt = Date.distantPast
    @ObservationIgnored private var nudgeContext: ScreenContext?
    @ObservationIgnored private let nudgeCooldown: TimeInterval = 120

    private var classifier: DistractionClassifier {
        CascadeClassifier(rules: RuleBasedClassifier(rules: rules), model: nil)
    }

    private init() {
        showNudges = Preferences.showNudges
        keepWatchdogAlways = Preferences.keepWatchdogAlways
        showInDock = Preferences.showInDock
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
        recoverLockedSessionIfNeeded()

        // A session here means the watchdog just relaunched us mid-lock. Setup can wait.
        if !hasCompletedOnboarding, session == nil {
            presentOnboarding()
        }
    }

    func applicationWillTerminate() {
        // Only reached when termination was allowed, so the lock is over.
        GuardState.clear()
        monitor.stop()
    }

    /// `AppDelegate` asks before every polite quit. PRD §9.
    func shouldAllowTermination() -> Bool {
        guard !canQuitApp else { return true }
        warnCannotQuit()
        return false
    }

    /// The watchdog relaunched us mid-lock: pick the session back up rather than
    /// starting idle, otherwise relaunching would hand the user a free pass.
    private func recoverLockedSessionIfNeeded() {
        guard session == nil, let state = GuardState.load(), state.isActive else { return }

        let remaining = state.lockedUntil.timeIntervalSinceNow
        session = FocusSession(
            goal: state.goal,
            startedAt: Date(),
            duration: remaining,
            strictness: .locked
        )
        hysteresis.reset()
        beginEnforcement()
        log("Resumed locked session after relaunch", symbol: "arrow.clockwise")
        Self.log.info("Recovered a locked session with \(Int(remaining))s remaining.")
    }

    // MARK: Session lifecycle

    var canEndSession: Bool {
        guard let session else { return false }
        return session.strictness != .locked || session.isExpired
    }

    /// Locked sessions can't quit Shift either (PRD §9, anti-bypass).
    var canQuitApp: Bool { session == nil || canEndSession }

    func startSession(goal: String, minutes: Int, strictness: Strictness) {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        session = FocusSession(
            goal: trimmed,
            startedAt: .now,
            duration: TimeInterval(minutes * 60),
            strictness: strictness
        )
        hysteresis.reset()
        nudgeHysteresis.reset()
        lastNudgeSignature = nil
        lastNudgeAt = .distantPast
        log("Started: \(trimmed) · \(minutes) min · \(strictness.title)", symbol: "play.fill")

        refreshPermissions()
        if !accessibilityGranted { PermissionsManager.requestAccessibility() }

        beginEnforcement()
    }

    /// Everything that must be true while a session runs, whether it was just started
    /// or recovered after a relaunch.
    private func beginEnforcement() {
        guard let session else { return }

        monitor.start()

        if session.strictness == .locked {
            armLockedProtections()
        }

        expiryTimer?.invalidate()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let session = self.session else { return }
                if session.isExpired {
                    self.finishSession(completed: true)
                } else if session.strictness == .locked {
                    self.pulseGuardState()
                }
            }
        }
    }

    func endSession() {
        guard canEndSession else { return }
        finishSession(completed: false)
    }

    private func finishSession(completed: Bool) {
        monitor.stop()
        expiryTimer?.invalidate()
        expiryTimer = nil
        shield.dismiss()
        nudgeHUD.hide()

        let finished = session
        // Cleared before disarming so the watchdog sync sees no active lock.
        session = nil
        lastContext = nil
        lastVerdict = nil
        nudgeContext = nil
        disarmLockedProtections()

        if let finished {
            let outcome = completed ? "Completed" : "Ended early"
            log("\(outcome) · \(finished.strikes) strike\(finished.strikes == 1 ? "" : "s")", symbol: "checkmark.seal.fill")
        }
    }

    // MARK: Locked-session protections

    private func armLockedProtections() {
        guard let session else { return }

        // `kill` sends SIGTERM, which would bypass `applicationShouldTerminate`.
        // Ignoring it during a lock closes that route. `kill -9` still wins, by design.
        signal(SIGTERM, SIG_IGN)

        if !WatchdogService.isInstalled {
            _ = WatchdogService.install()
        }
        WatchdogService.kickstart()
        watchdogInstalled = WatchdogService.isInstalled

        GuardState(
            lockedUntil: session.hardenedDeadline,
            bundlePath: Bundle.main.bundleURL.path,
            goal: session.goal,
            heartbeat: Date()
        ).save()
    }

    private func disarmLockedProtections() {
        signal(SIGTERM, SIG_DFL)
        GuardState.clear()
        heartbeatTick = 0
        syncWatchdogInstallation()
    }

    /// Refreshes the deadline the watchdog trusts, so a clock change can't shorten it.
    private func pulseGuardState() {
        heartbeatTick += 1
        guard heartbeatTick % 10 == 0, let session else { return }
        GuardState(
            lockedUntil: session.hardenedDeadline,
            bundlePath: Bundle.main.bundleURL.path,
            goal: session.goal,
            heartbeat: Date()
        ).save()
    }

    private func warnCannotQuit() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "This session is locked."
        if let session {
            let minutes = Int(session.remaining() / 60) + 1
            alert.informativeText = "Shift can't be quit until the session ends, in about \(minutes) minute\(minutes == 1 ? "" : "s"). That's the point of Locked mode."
        } else {
            alert.informativeText = "Shift can't be quit while a locked session is running."
        }
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    // MARK: Detection → enforcement

    private func handle(_ context: ScreenContext) {
        if lastContext != context { lastContext = context }
        guard let session, !shield.isShowing else { return }

        let verdict = classifier.classify(context, session: session)
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

    /// Nudges get the same two-reading confirmation as blocks, plus a cooldown per place,
    /// so the HUD stays rare enough to mean something.
    private func considerNudge(_ verdict: Verdict, on context: ScreenContext) {
        guard showNudges, let session else { return }
        guard nudgeHysteresis.register(context.signature) else { return }

        let isRepeat = context.signature == lastNudgeSignature
        let withinCooldown = Date().timeIntervalSince(lastNudgeAt) < nudgeCooldown
        guard !(isRepeat && withinCooldown) else { return }

        lastNudgeSignature = context.signature
        lastNudgeAt = Date()
        nudgeContext = context

        nudgeHUD.show(reason: verdict.reason, goal: session.goal) { [weak self] in
            guard let self, let context = self.nudgeContext else { return }
            // The user chose this, so it isn't the AI raising a shield on a nudge.
            self.enforce(.block(verdict.reason), on: context)
        }
        log("Nudged · \(context.displayLocation)", symbol: "arrow.turn.up.left")
    }

    private func enforce(_ verdict: Verdict, on context: ScreenContext) {
        guard var session else { return }
        nudgeHUD.hide()
        session.strikes += 1
        self.session = session

        log("Blocked \(context.displayLocation)", symbol: "hand.raised.fill")

        let request = ShieldRequest(
            appName: context.appName,
            bundleID: context.bundleID,
            processID: context.processID,
            host: context.host,
            isBrowser: context.isBrowser,
            reason: verdict.reason,
            goal: session.goal,
            strike: session.strikes,
            policy: .make(strictness: session.strictness, strike: session.strikes)
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
            Browser(bundleID: request.bundleID)?.closeFrontTab()
            app?.activate()
            log("Closed tab · \(request.host ?? request.appName)", symbol: "xmark.circle")
        case .forceQuit:
            app?.forceTerminate()
            log("Force quit \(request.appName)", symbol: "power")
        case .wrongCall:
            let key = request.host ?? request.bundleID
            session?.allowances.insert(key)
            app?.activate()
            // TODO(M4): save (goal, context) as a local training example for the personal adapter.
            log("Wrong call · allowed \(key)", symbol: "arrow.uturn.backward")
        }
    }

    // MARK: Demo

    /// Shows a shield without touching any app, so you can feel each escalation level.
    func previewShield(strike: Int) {
        let strictness = session?.strictness ?? .firm
        let request = ShieldRequest(
            appName: "Safari",
            bundleID: "com.apple.Safari",
            processID: 0,
            host: "instagram.com",
            isBrowser: true,
            reason: "instagram.com isn't part of “\(session?.goal ?? "Finish my thesis chapter")”",
            goal: session?.goal ?? "Finish my thesis chapter",
            strike: strike,
            policy: .make(strictness: strictness, strike: strike),
            isPreview: true
        )
        shield.present(request) { [weak self] resolution in
            self?.resolve(resolution, for: request)
        }
    }

    /// Lets the user feel the nudge HUD from Settings without waiting for a real drift.
    func previewNudge() {
        nudgeHUD.show(
            reason: "“Shorts” looks like a feed",
            goal: session?.goal ?? "Finish my thesis chapter",
            onBlock: {}
        )
    }

    // MARK: Onboarding

    func presentOnboarding() {
        onboarding.present(model: self)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        Preferences.hasCompletedOnboarding = true
    }

    // MARK: Permissions and system state

    /// Permissions are changed in System Settings, which means they change while Shift is
    /// in the background. Re-read them the moment the user comes back to us, so the UI is
    /// never showing a stale "not granted".
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
        // Assign only on change so observation doesn't churn while polling.
        if accessibility != accessibilityGranted { accessibilityGranted = accessibility }
        if screenRecording != screenRecordingGranted { screenRecordingGranted = screenRecording }
    }

    func requestScreenRecordingPermission() {
        // The system prompt only ever appears once per app. After that this is a no-op,
        // so send the user somewhere useful as well.
        if !PermissionsManager.requestScreenRecording() {
            PermissionsManager.openScreenRecordingSettings()
        }
        refreshPermissions()
    }

    func requestAccessibilityPermission() {
        PermissionsManager.requestAccessibility()
        PermissionsManager.openAccessibilitySettings()
    }

    func refreshSystemState() {
        refreshPermissions()
        launchAtLoginEnabled = LaunchAtLogin.isEnabled
        watchdogInstalled = WatchdogService.isInstalled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LaunchAtLogin.setEnabled(enabled)
        launchAtLoginEnabled = LaunchAtLogin.isEnabled
        if enabled && !launchAtLoginEnabled {
            log("Login item needs approval in System Settings", symbol: "exclamationmark.triangle")
        }
    }

    /// Installs or removes the agent to match the preference, never touching it mid-lock.
    private func syncWatchdogInstallation() {
        let lockActive = session?.strictness == .locked && !(session?.isExpired ?? true)
        if keepWatchdogAlways || lockActive {
            if !WatchdogService.isInstalled { _ = WatchdogService.install() }
        } else if WatchdogService.isInstalled {
            _ = WatchdogService.remove()
        }
        watchdogInstalled = WatchdogService.isInstalled
    }

    // MARK: Helpers

    private func log(_ text: String, symbol: String) {
        activity.insert(ActivityEvent(text, symbol: symbol), at: 0)
        if activity.count > 20 { activity.removeLast(activity.count - 20) }
    }
}

// MARK: - Preferences

/// Thin `UserDefaults` wrapper so key strings live in exactly one place.
enum Preferences {
    private enum Key {
        static let showNudges = "Shift.showNudges"
        static let keepWatchdogAlways = "Shift.keepWatchdogAlways"
        static let showInDock = "Shift.showInDock"
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

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Key.hasCompletedOnboarding) }
        set { UserDefaults.standard.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }
}
