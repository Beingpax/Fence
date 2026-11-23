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
    let urges = UrgeLog()

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
            if !showNudges { nudgeHUD.hideHint() }
        }
    }

    /// Whether the pause, the reward and the shield make their sounds.
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
    @ObservationIgnored private let intentNudges = IntentNudgeMonitor()
    @ObservationIgnored private let shield = ShieldController()
    @ObservationIgnored private var resolvingProcesses: Set<pid_t> = []
    @ObservationIgnored private let nudgeHUD = NudgeHUDController()
    @ObservationIgnored private let pause = PauseController()
    /// When each site was last reached for, per block, for escalation.
    @ObservationIgnored private var reaches: [String: [Date]] = [:]
    /// "I need it" grants, until when.
    @ObservationIgnored private var allowances: [String: Date] = [:]
    @ObservationIgnored private var allowanceTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var pausedRequest: PauseRequest?
    /// The encounter the shield is being raised for, while its last check runs.
    @ObservationIgnored private var pendingShieldKey: String?
    /// The tab is being closed in this process; ignore it until then, or a sample landing
    /// before Command-W would open a second pause for the page that's on its way out.
    @ObservationIgnored private var closingPID: pid_t?
    @ObservationIgnored private var closingUntil = Date.distantPast
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
        playNudgeSounds = Preferences.playNudgeSounds
        showInDock = Preferences.showInDock
        driftKeywords = Preferences.driftKeywords
        hasCompletedOnboarding = Preferences.hasCompletedOnboarding

        monitor.onSample = { [weak self] context in
            self?.handle(context)
        }
        monitor.onInvalidation = { [weak self] in
            self?.intentNudges.reset()
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
                pause.dismiss()
                pausedRequest = nil
                pendingShieldKey = nil
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
        guard !shield.isShowing, !resolvingProcesses.contains(context.processID) else { return }

        let evaluator = BlockEvaluator(blocks: store.activeBlocks, driftKeywords: driftKeywords)
        let ruleVerdict = evaluator.ruleVerdict(for: context)

        // Leaving while the pause is up is the right answer, and gets treated as one.
        if pause.isShowing, !pause.isCommitted, let key = pause.key, key != Self.previewKey,
           ruleVerdict.flatMap({ encounterKey(for: $0, context: context) }) != key {
            walkedAway()
        }

        if let verdict = ruleVerdict {
            intentNudges.reset()
            apply(verdict, to: context)
            return
        }
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
        case .nudge:
            hysteresis.reset()
            if verdict.source == .rules, !nudgeHysteresis.register(context.signature) { return }
            considerNudge(verdict, on: context)
        case .block:
            nudgeHysteresis.reset()
            guard let key = encounterKey(for: verdict, context: context),
                  let reachKey = reachKey(for: verdict) else { return }
            // Already pausing for this, already raising the shield, or the person asked
            // for two minutes and is using them.
            if pause.key == key || pendingShieldKey == key { return }
            if context.processID == closingPID, Date() < closingUntil { return }
            if let until = allowances[reachKey], until > Date() { return }
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
    /// Reaches per `reachWindow` that get the pause. The one after gets the shield.
    private static let pausesPerHour = 2
    /// "I need it" buys exactly this long.
    private static let allowance: TimeInterval = 120
    static let previewKey = "preview"

    /// One reach for a blocked site.
    ///
    /// The first in an hour gets a single breath, the second gets three, and the third gets
    /// the full-screen block. Every repeat costs more, so coming back is never free, and
    /// switching away and back can't reset anything: the count is per site, not per visit.
    private func beginReach(key: String, reachKey: String, verdict: Verdict, context: ScreenContext) {
        let now = Date()
        var recent = (reaches[reachKey] ?? []).filter { now.timeIntervalSince($0) < Self.reachWindow }
        recent.append(now)
        reaches[reachKey] = recent
        let target = context.host ?? context.appName

        if recent.count > Self.pausesPerHour {
            pendingShieldKey = key
            Task { await confirmAndEnforce(key: key, target: verdict.ruleTarget) }
            return
        }

        guard let blockID = verdict.blockID else { return }
        store.recordTrigger(id: blockID, now: now)
        let request = PauseRequest(
            blockName: verdict.blockName ?? "Shift",
            target: target,
            appName: context.appName,
            visit: recent.count,
            allowsNeeded: !(store.block(id: blockID)?.isLocked() ?? false),
            plans: urges.plans
        )
        pausedRequest = request
        nudgeHUD.hide()
        if playNudgeSounds { NudgeSound.playPause() }
        log("Paused · \(target)", symbol: "wind")
        pause.present(request, key: key, over: context.windowID.flatMap(WindowInspector.frame(of:))) { [weak self] event in
            self?.handlePause(event, key: key, reachKey: reachKey, request: request, context: context)
        }
    }

    private func handlePause(
        _ event: PauseEvent, key: String, reachKey: String, request: PauseRequest, context: ScreenContext
    ) {
        guard pause.key == key else { return }
        let isPreview = request.isPreview
        let record = { [weak self] (outcome: UrgeOutcome, reason: UrgeReason?, note: String?) in
            guard !isPreview else { return }
            self?.urges.record(UrgeEvent(
                date: Date(), blockName: request.blockName, target: request.target,
                reason: reason, outcome: outcome, note: note
            ))
        }

        switch event {
        case .close:
            pause.dismiss()
            closeTarget(context, isPreview: isPreview)
            record(.closed, nil, nil)
            reward(request.visit > 1 ? Self.harderReward : Self.closedRewards.randomElement() ?? Self.harderReward)
            log("Turned back · \(request.target)", symbol: "arrow.uturn.backward")

        case .beganBreak:
            // Close the page now, so nothing is waiting behind the cover when the break ends.
            pause.commit()
            closeTarget(context, isPreview: isPreview)
            log("Break instead of \(request.target)", symbol: "cup.and.saucer")

        case .finished(let reason, let outcome, let note):
            if !pause.isCommitted { closeTarget(context, isPreview: isPreview) }
            pause.dismiss()
            record(outcome, reason, note)
            reward(Self.reward(for: outcome, note: note))
            log("Turned back · \(request.target) · \(reason.shortLabel)", symbol: "arrow.uturn.backward")

        case .openMessages:
            pause.dismiss()
            closeTarget(context, isPreview: isPreview)
            if !isPreview { openMessages() }
            record(.reachedOut, .lonely, nil)
            reward(Self.reward(for: .reachedOut, note: nil))
            log("Reached out instead of \(request.target)", symbol: "message")

        case .allow(let note):
            pause.dismiss()
            record(.allowed, .needed, note)
            nudgeHUD.status(headline: "Two minutes. Go do it.", detail: note)
            guard !isPreview else { return }
            allow(reachKey: reachKey, note: note, request: request)
        }
        pausedRequest = nil
    }

    /// The person switched away while the pause was up. That's turning back too.
    private func walkedAway() {
        let request = pausedRequest
        pause.dismiss()
        pausedRequest = nil
        hysteresis.reset()
        guard let request else { return }
        urges.record(UrgeEvent(date: Date(), blockName: request.blockName, target: request.target,
                               reason: nil, outcome: .walkedAway))
        reward(Self.reward(for: .walkedAway, note: nil))
        log("Walked away from \(request.target)", symbol: "figure.walk")
    }

    /// Two minutes for a stated reason, then Shift closes it.
    private func allow(reachKey: String, note: String, request: PauseRequest) {
        allowances[reachKey] = Date().addingTimeInterval(Self.allowance)
        log("Two minutes · \(request.target) · \(note)", symbol: "timer")
        allowanceTasks[reachKey]?.cancel()
        allowanceTasks[reachKey] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.allowance - 30))
            guard !Task.isCancelled, let self else { return }
            if self.allowedContext(reachKey) != nil {
                self.nudgeHUD.status(headline: "30 seconds left.", detail: "Wrap up: \(note)")
            }
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            self.allowances[reachKey] = nil
            self.allowanceTasks[reachKey] = nil
            self.hysteresis.reset()
            guard let context = self.allowedContext(reachKey) else { return }
            self.closeTarget(context, isPreview: false)
            self.nudgeHUD.status(headline: "Time’s up.", detail: "Hope you got what you came for. Back to \(request.blockName).")
            self.log("Closed after two minutes · \(request.target)", symbol: "timer")
        }
    }

    /// The front context, if it's still the site an allowance was granted for.
    private func allowedContext(_ reachKey: String) -> ScreenContext? {
        guard let context = lastContext,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == context.processID,
              let verdict = BlockEvaluator(blocks: store.activeBlocks, driftKeywords: driftKeywords).ruleVerdict(for: context),
              self.reachKey(for: verdict) == reachKey
        else { return nil }
        return context
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

    private func openMessages() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.MobileSMS") else { return }
        Task {
            // After the tab closes, or the browser would take the front back from Messages.
            try? await Task.sleep(for: .milliseconds(450))
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: Reward

    /// Praise, the moment someone turns back. This is the step that builds the habit:
    /// behaviour that's rewarded straight away repeats, and before this, turning back got
    /// nothing at all.
    ///
    /// Several lines, picked at random, because the same line every time stops being
    /// heard. Specific to what the person just did wherever possible.
    private func reward(_ message: (headline: String, detail: String)) {
        nudgeHUD.reward(headline: message.headline, detail: message.detail)
        if playNudgeSounds { NudgeSound.playReward() }
    }

    private static let closedRewards: [(headline: String, detail: String)] = [
        ("That’s the one that counts.", "You chose your work over the feed."),
        ("Nice save.", "Every time you do this, the next one gets easier."),
        ("Back to it.", "Future you just said thank you."),
        ("Look at you.", "Walking away is a muscle. You just used it."),
    ]

    private static let harderReward = (
        headline: "That one was harder.",
        detail: "You turned back anyway. That’s exactly how habits change."
    )

    private static func reward(for outcome: UrgeOutcome, note: String?) -> (headline: String, detail: String) {
        switch outcome {
        case .tookBreak:
            ("Welcome back.", "That was real rest. Ready when you are.")
        case .wroteStep:
            ("Go do that step.", note.map { "“\($0)”" } ?? "Small steps are how hard things get done.")
        case .wroteItDown:
            ("Lighter already.", "It’s written down. You don’t have to carry it right now.")
        case .reachedOut:
            ("That’s real connection.", "Worth more than any feed.")
        case .walkedAway:
            ("Good call.", "You walked away on your own.")
        default:
            closedRewards.randomElement() ?? harderReward
        }
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

    /// Use the latest sample so a title change alone can't stall the shield.
    private func currentBlockedContext(key: String) -> ScreenContext? {
        guard !shield.isShowing, monitor.isRunning, let context = lastContext,
              !resolvingProcesses.contains(context.processID),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == context.processID
        else { return nil }
        let evaluator = BlockEvaluator(blocks: store.activeBlocks, driftKeywords: driftKeywords)
        guard let verdict = evaluator.ruleVerdict(for: context), encounterKey(for: verdict, context: context) == key
        else { return nil }
        return context
    }

    /// Third reach in an hour: read the page once more, then cover the screen.
    private func confirmAndEnforce(key: String, target: RuleTarget?) async {
        defer { if pendingShieldKey == key { pendingShieldKey = nil } }
        guard let target, let context = currentBlockedContext(key: key) else { return }
        let readWebsite: Bool
        switch target {
        case .app: readWebsite = false
        case .website, .path: readWebsite = true
        }

        guard let fresh = await monitor.confirm(context, readWebsite: readWebsite), !Task.isCancelled,
              pendingShieldKey == key, currentBlockedContext(key: key) != nil else { return }
        let evaluator = BlockEvaluator(blocks: store.activeBlocks, driftKeywords: driftKeywords)
        guard let verdict = evaluator.ruleVerdict(for: fresh), encounterKey(for: verdict, context: fresh) == key
        else { return }
        enforce(verdict, on: fresh, reason: "Third time this hour. The pull is strong today, so let’s stop here.")
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

    private func enforce(_ verdict: Verdict, on context: ScreenContext, reason: String? = nil) {
        guard verdict.kind == .block, verdict.source == .rules,
              let blockID = verdict.blockID,
              !resolvingProcesses.contains(context.processID) else { return }
        nudgeHUD.hide()
        pause.dismiss()
        pausedRequest = nil
        urges.record(UrgeEvent(date: Date(), blockName: verdict.blockName ?? "Shift",
                               target: context.host ?? context.appName, reason: nil, outcome: .shielded))

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
            reason: reason ?? verdict.reason,
            blockName: verdict.blockName ?? "Shift",
            blockID: blockID,
            breakMinutes: breakMinutes
        )
        if playNudgeSounds { NudgeSound.playShield() }
        shield.present(request) { [weak self] resolution in
            self?.resolve(resolution, for: request)
        }
    }

    private func resolve(_ resolution: ShieldResolution, for request: ShieldRequest) {
        hysteresis.reset()
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
        if playNudgeSounds { NudgeSound.playShield() }
        shield.present(request) { [weak self] resolution in
            self?.resolve(resolution, for: request)
        }
    }

    /// The pause as it looks on a first reach (`visit` 1) or a second (`visit` 2).
    func previewPause(visit: Int = 1) {
        let request = PauseRequest(
            blockName: "Deep work", target: "instagram.com", appName: "Safari",
            visit: visit, allowsNeeded: true, plans: urges.plans, isPreview: true
        )
        let context = ScreenContext(bundleID: "com.apple.Safari", appName: "Safari", processID: 0)
        if playNudgeSounds { NudgeSound.playPause() }
        pause.present(request, key: Self.previewKey, over: nil) { [weak self] event in
            self?.handlePause(event, key: Self.previewKey, reachKey: Self.previewKey, request: request, context: context)
        }
    }

    func previewReward() {
        reward(Self.closedRewards.randomElement() ?? Self.harderReward)
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
