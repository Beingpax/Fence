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
    /// Each process has its own model; only the monitor owner presents real block pauses.
    static let shared = AppModel()

    private static let log = Logger(subsystem: "com.beingpax.Shift", category: "AppModel")

    // MARK: Observable state

    let store: BlockStore

    private(set) var lastContext: ScreenContext?
    private(set) var lastVerdict: Verdict?
    private(set) var activity: [ActivityEvent] = []
    private(set) var accessibilityGranted = PermissionsManager.isAccessibilityTrusted
    private(set) var launchAtLoginEnabled = LaunchAtLogin.isEnabled

    private(set) var canQuitApp = true
    private(set) var backgroundServiceNotice: String?
    @ObservationIgnored private var registerAgent: @MainActor (Bool) throws -> Bool = EnforcementService.registerIfNeeded
    @ObservationIgnored private var quittingForRemoval = false
    @ObservationIgnored private var serviceWanted: Bool?
    @ObservationIgnored private var nextServiceCheck = Date.distantPast
    @ObservationIgnored private var monitorLease: ProcessLease?
    @ObservationIgnored private var serviceObservers: [NSObjectProtocol] = []

    /// Mirrors the engine so the UI can show whether Shift is actually watching.
    private(set) var isWatching = false

    /// Which section the main window is showing. Owned here so the menu bar and the
    /// Settings command can open the window straight to a section.
    var mainSection: MainSection = .dashboard
    var newBlock: Block?
    var unlockTarget: Block?

    var showNudges: Bool {
        didSet {
            if !EnforcementService.isAgent { Preferences.showNudges = showNudges }
            nudgeHysteresis.reset()
            if !showNudges { nudgeHUD.hideHint() }
        }
    }

    /// Whether the pause and the reward make their sounds.
    var playNudgeSounds: Bool {
        didSet { if !EnforcementService.isAgent { Preferences.playNudgeSounds = playNudgeSounds } }
    }

    var showInDock: Bool {
        didSet {
            Preferences.showInDock = showInDock
            applyActivationPolicy()
        }
    }

    var driftKeywords: [String] {
        didSet { if !EnforcementService.isAgent { Preferences.driftKeywords = driftKeywords } }
    }

    private(set) var hasCompletedOnboarding: Bool

    // MARK: Engine

    @ObservationIgnored private let bundleRecovery = RunningBundleRecovery()
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
    @ObservationIgnored private var confirmingTabClose = false
    @ObservationIgnored private var lastFilteredTab: ScreenContext?
    @ObservationIgnored private var lastFilteredAt = Date.distantPast
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

    func startDashboard(registerAgent: @escaping @MainActor (Bool) throws -> Bool) {
        self.registerAgent = registerAgent
        PermissionsManager.logDiagnostics()
        applyActivationPolicy()
        observeActivation()
        refreshSystemState()
        observeRuleChanges()
        startEngine()
    }

    func startAgent() {
        observeRuleChanges()
        startEngine()
    }

    private func observeRuleChanges() {
        let center = DistributedNotificationCenter.default()
        for name in [EnforcementService.rulesChanged, EnforcementService.agentReady] {
            serviceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reconcileMonitoring() }
            })
        }
        if !EnforcementService.isAgent {
            serviceObservers.append(center.addObserver(forName: EnforcementService.openDashboard, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.openApp() }
            })
        }
        store.onCommit = { [weak self] in
            EnforcementService.notify(EnforcementService.rulesChanged)
            self?.reconcileMonitoring()
        }
    }

    func applicationWillTerminate() {
        if canQuitApp {
            GuardState.clear()
            if WatchdogService.hasConfiguration { WatchdogService.remove() }
        }
        for observer in serviceObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        serviceObservers.removeAll()
        monitor.stop()
        engineTimer?.invalidate()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        monitorLease = nil
    }

    /// The app delegate asks before every polite quit.
    func shouldAllowTermination() -> Bool {
        guard store.permitsTermination() else {
            warnCannotQuit()
            return false
        }
        guard quittingForRemoval else { return true }
        let stoppedAgent = (try? registerAgent(false)) == false
        guard stoppedAgent && LaunchAtLogin.setEnabled(false) else {
            serviceWanted = nil
            reconcileMonitoring()
            let alert = NSAlert()
            alert.messageText = "Shift couldn’t turn off its login items."
            alert.informativeText = "Check Shift in System Settings → General → Login Items & Extensions, then try again."
            alert.runModal()
            return false
        }
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        return true
    }

    func requestUninstall() {
        let alert = NSAlert()
        alert.messageText = "Prepare to uninstall Shift?"
        alert.informativeText = "Shift will turn off its login items, quit, and show the app in Finder. Move it to the Trash to finish. Your saved blocks stay on this Mac."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit and Show in Finder")
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        // AppKit rechecks the rules after confirmation, including schedules that just started.
        quittingForRemoval = true
        defer { quittingForRemoval = false }
        NSApp.terminate(nil)
    }

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
        store.refreshFromDisk()
        store.tick()
        if tickCount % 60 == 0, !reaches.isEmpty {
            let cutoff = Date().addingTimeInterval(-Self.reachWindow)
            reaches = reaches.compactMapValues { dates in
                let recent = dates.filter { $0 > cutoff }
                return recent.isEmpty ? nil : recent
            }
        }

        reconcileMonitoring()
        if tickCount % 5 == 0, isWatching || NSApp.isActive { refreshPermissions() }
    }

    private func reconcileMonitoring() {
        store.refreshFromDisk()
        let active = store.activeBlocks
        let mayQuit = !store.blocks.contains { $0.protectsQuit() }
        if mayQuit != canQuitApp { canQuitApp = mayQuit }
        let agent = EnforcementService.isAgent
        let agentReady = agent || EnforcementService.hasOwner("agent.lock")
        if agent {
            // Read dashboard preference changes while the engine is in the other process.
            if showNudges != Preferences.showNudges { showNudges = Preferences.showNudges }
            if playNudgeSounds != Preferences.playNudgeSounds { playNudgeSounds = Preferences.playNudgeSounds }
            if driftKeywords != Preferences.driftKeywords { driftKeywords = Preferences.driftKeywords }
        } else {
            syncBackgroundService(agentReady: agentReady)
        }

        let shouldOwnMonitor = !active.isEmpty && (agent || !agentReady)
        if shouldOwnMonitor, monitorLease == nil {
            monitorLease = try? EnforcementService.lease("monitor.lock")
        }
        let shouldWatch = shouldOwnMonitor && monitorLease != nil

        if shouldWatch != isWatching {
            isWatching = shouldWatch
            if shouldWatch {
                monitor.start()
                refreshPermissions()
                if !agent, !accessibilityGranted, hasCompletedOnboarding { PermissionsManager.requestAccessibility() }
                log("Watching · \(active.count) active block\(active.count == 1 ? "" : "s")", symbol: "eye")
            } else {
                monitor.stop()
                lastContext = nil
                lastVerdict = nil
                pause.dismiss()
                nudgeHUD.hideHint()
                hysteresis.reset()
                log("Nothing active", symbol: "eye.slash")
            }
        }

        if !shouldOwnMonitor, monitorLease != nil {
            monitorLease = nil
            EnforcementService.notify(EnforcementService.agentReady)
        }
        if active.isEmpty, !allowances.isEmpty {
            allowanceTasks.values.forEach { $0.cancel() }
            allowanceTasks.removeAll()
            allowances.removeAll()
        }

        if let blockID = pause.blockID, !active.contains(where: { $0.id == blockID }) {
            pause.dismiss()
            hysteresis.reset()
            monitor.resampleSoon()
        }

        bundleRecovery?.update(protected: !mayQuit)
        if !agent { syncLockProtections(agentReady: agentReady) }
    }

    private func syncBackgroundService(agentReady: Bool) {
        let wanted = store.blocks.contains { $0.isEnabled || $0.isLocked() }
        guard serviceWanted != wanted || Date() >= nextServiceCheck else { return }
        let firstAttempt = serviceWanted != wanted
        serviceWanted = wanted
        nextServiceCheck = Date().addingTimeInterval(15)
        do {
            let enabled = try registerAgent(wanted)
            if wanted && !enabled {
                backgroundServiceNotice = "Allow Shift in Login Items & Extensions to keep blocks active after Force Quit."
            } else if wanted && !agentReady && !firstAttempt {
                backgroundServiceNotice = "The background service is offline. Shift is enforcing blocks in the dashboard."
            } else {
                backgroundServiceNotice = nil
            }
        } catch {
            backgroundServiceNotice = wanted ? "Background blocking could not start. Open Login Items & Extensions to check Shift." : nil
            Self.log.error("Background registration: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Detection → enforcement

    private var currentEvaluator: BlockEvaluator {
        let blocks = store.activeBlocks
        return BlockEvaluator(blocks: blocks, driftKeywords: blocks.isEmpty ? [] : driftKeywords)
    }

    private func handle(_ context: ScreenContext) {
        let locationChanged = lastContext?.signature != context.signature
        if lastContext != context { lastContext = context }
        if locationChanged {
            lastVerdict = nil
            nudgeHUD.hideHint()
        }
        guard !pause.isShowing else { return }

        let evaluator = currentEvaluator
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
            if context.processID == closingPID, Date() < closingUntil { return }
            if verdict.closesTab {
                hysteresis.reset()
                closeMatchingTab(verdict, context: context)
                return
            }
            guard let key = encounterKey(for: verdict, context: context),
                  let reachKey = reachKey(for: verdict) else { return }
            // Already pausing, closing the page this came from, or temporarily allowed.
            if pause.isShowing { return }
            if let until = allowances[reachKey], until > Date() { return }
            // A new encounter has to read the same twice, so a stray frame can't trigger
            // anything. The second reading is requested straight away instead of waiting
            // for the next poll, which keeps the pause ahead of the page load.
            guard hysteresis.register(key) else {
                monitor.resampleSoon()
                return
            }
            beginReach(reachKey: reachKey, verdict: verdict, context: context)
        }
    }

    private func closeMatchingTab(_ verdict: Verdict, context: ScreenContext) {
        guard !confirmingTabClose, let observedURL = context.url else { return }
        if let lastFilteredTab, lastFilteredTab.processID == context.processID,
           lastFilteredTab.windowID == context.windowID, lastFilteredTab.url == observedURL,
           Date().timeIntervalSince(lastFilteredAt) < 0.5 { return }

        confirmingTabClose = true
        Task {
            defer { confirmingTabClose = false }
            guard let live = await monitor.confirm(context, readWebsite: true),
                  live.url == observedURL, live.windowID == context.windowID, !pause.isShowing,
                  lastContext?.processID == live.processID, lastContext?.url == observedURL,
                  lastContext?.windowID == live.windowID,
                  let current = currentEvaluator.ruleVerdict(for: live),
                  current.closesTab, let blockID = current.blockID, blockID == verdict.blockID,
                  TabCloser.closeIfFrontmost(pid: live.processID) else { return }
            lastFilteredTab = live
            lastFilteredAt = Date()
            store.recordTrigger(id: blockID)
            log("Closed matching tab · \(current.blockName ?? "Block")", symbol: "xmark.circle")
        }
    }

    // MARK: The pause

    /// How long a reach is remembered when deciding how hard the next one should be.
    private static let reachWindow: TimeInterval = 3600

    /// One reach for a blocked site or app. Repeat reaches within the hour are counted per rule.
    private func beginReach(reachKey: String, verdict: Verdict, context: ScreenContext) {
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
        let copy = PauseCopy.pause(visit: recent.count)
        let request = PauseRequest(
            blockName: verdict.blockName ?? "Shift",
            blockID: blockID,
            ruleTarget: verdict.ruleTarget,
            target: target,
            appName: context.appName,
            isBrowser: Browser(bundleID: context.bundleID) != nil,
            visit: recent.count,
            breaksLeft: breaks.flatMap { $0.isEnabled ? $0.remaining(at: now) : nil },
            title: copy.title,
            subtitle: copy.subtitle
        )
        nudgeHUD.hide()
        if playNudgeSounds { request.visit >= 3 ? NudgeSound.playDeep() : NudgeSound.playPause() }
        log("Paused · \(target)", symbol: "wind")
        pause.present(request) { [weak self] event in
            self?.handlePause(event, request: request, context: context)
        }
    }

    private func handlePause(_ event: PauseEvent, request: PauseRequest, context: ScreenContext) {
        pause.dismiss()
        hysteresis.reset()

        switch event {
        case .close(let reason):
            closeTarget(context, isPreview: request.isPreview)
            reward(PauseCopy.reward(for: reason, visit: request.visit))
            log("Turned back · \(request.target)\(reason.map { " · \($0.shortLabel)" } ?? "")",
                symbol: "arrow.uturn.backward")

        case .takeBreak(let minutes, let note):
            let headline = "\(minutes) minutes of access."
            guard !request.isPreview else {
                nudgeHUD.status(headline: headline, detail: note)
                return
            }

            // The process, rule or schedule may have changed during the wait.
            guard BreakPlan.accessMinutes.contains(minutes),
                  let app = NSRunningApplication(processIdentifier: context.processID),
                  !app.isTerminated, app.bundleIdentifier == context.bundleID,
                  let blockID = request.blockID, let block = store.block(id: blockID),
                  let verdict = BlockEvaluator(blocks: [block], driftKeywords: []).ruleVerdict(for: context),
                  verdict.ruleTarget == request.ruleTarget, let reachKey = reachKey(for: verdict),
                  store.spendBreak(id: blockID) else {
                monitor.resampleSoon()
                nudgeHUD.status(headline: "Break didn’t start.", detail: "Access is no longer available for \(request.blockedTarget).")
                return
            }

            allow(reachKey: reachKey, minutes: minutes)
            NSApp.yieldActivation(to: app)
            app.activate()
            nudgeHUD.status(headline: headline, detail: note)
            log("\(minutes) min on \(request.target) · \(note)", symbol: "cup.and.saucer")
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

    private func closeTarget(_ context: ScreenContext, isPreview: Bool) {
        guard !isPreview else { return }
        hysteresis.reset()
        closingPID = context.processID
        closingUntil = Date().addingTimeInterval(1.5)
        if Browser(bundleID: context.bundleID) != nil {
            Task { await TabCloser.closeFrontTab(for: context, monitor: monitor) }
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
    private func syncLockProtections(agentReady: Bool) {
        signal(SIGTERM, canQuitApp ? SIG_DFL : SIG_IGN)

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
        if agentReady, WatchdogService.hasConfiguration { WatchdogService.remove() }
    }

    private func warnCannotQuit() {
        let protected = store.blocks.filter { $0.protectsQuit() }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Shift is protecting your blocks."
        alert.informativeText = protected.map { block in
            block.isLocked() ? "\(block.name) · \(block.lockStatus())" : "\(block.name) · Running"
        }.joined(separator: "\n") + "\n\nTurn off running blocks and release active locks before quitting."
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    // MARK: Previews

    /// The pause as it looks on a first, second or third reach within the hour.
    func previewPause(visit: Int = 1) {
        let site = "instagram.com"
        let copy = PauseCopy.pause(visit: visit)
        let request = PauseRequest(
            blockName: "Deep work", blockID: nil, ruleTarget: .website(site), target: site, appName: "Safari",
            isBrowser: true, visit: visit, breaksLeft: BreakPlan.dailyAllowance,
            title: copy.title, subtitle: copy.subtitle, isPreview: true
        )
        let context = ScreenContext(bundleID: "com.apple.Safari", appName: "Safari", processID: 0)
        if playNudgeSounds { visit >= 3 ? NudgeSound.playDeep() : NudgeSound.playPause() }
        pause.present(request) { [weak self] event in
            self?.handlePause(event, request: request, context: context)
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
