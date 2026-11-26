import AppKit
import Observation
import ServiceManagement
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
    private(set) var keyboardEventsGranted = PermissionsManager.canPostKeyboardEvents
    var browserAccessNeedsAttention: Bool { !accessibilityGranted || !keyboardEventsGranted }
    private(set) var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    private(set) var launchAtLoginNeedsApproval = LaunchAtLogin.requiresApproval
    private(set) var backgroundServiceStatus = EnforcementService.service.status
    private(set) var backgroundRegistrationFailed = false
    private(set) var backgroundServiceOffline = false

    var backgroundBlockingAllowed: Bool { backgroundServiceStatus == .enabled }

    private(set) var canQuitApp = true
    @ObservationIgnored private var registerAgent: @MainActor (Bool) throws -> Bool = EnforcementService.registerIfNeeded
    @ObservationIgnored private var quittingForRemoval = false
    @ObservationIgnored private var serviceWanted: Bool?
    @ObservationIgnored private var nextServiceCheck = Date.distantPast
    /// When Shift last tried to bring an offline helper back. See `repairHelperIfDue`.
    @ObservationIgnored private var lastHelperRepair = Date.distantPast
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
    /// The journal row for the pause on screen, until it's answered or taken down.
    @ObservationIgnored private var openReachID: UUID?
    /// The heads-up before the pause, running or recently ended. See `reach`.
    @ObservationIgnored private var warning: ReachWarning?
    /// When each rule last got a heads-up, for an hour, so a repeat reads differently.
    @ObservationIgnored private var warnings: [String: [Date]] = [:]
    @ObservationIgnored private var warningTask: Task<Void, Never>?
    /// Leaving the blocked page during a heads-up has to read the same twice.
    @ObservationIgnored private var leaving = Hysteresis(requiredHits: 2)
    /// When the browser started showing no page during a heads-up: a Start Page, an empty
    /// tab, a window closed with its last tab. See `noteLeaving`.
    @ObservationIgnored private var blankSince: Date?
    @ObservationIgnored private var blankCheck: Task<Void, Never>?
    /// The executable this process launched from. See `restartIfReplaced`.
    @ObservationIgnored private let launchedExecutable = ExecutableStamp.current()
    /// A replacement seen on disk, and when, so a build still being written isn't relaunched.
    @ObservationIgnored private var pendingExecutable: (stamp: ExecutableStamp, since: Date)?
    /// Helper only: the dashboard asked for a restart because this helper is out of date.
    @ObservationIgnored private var restartRequested = false
    /// Dashboard only: when it asked a stale helper to restart. See `replaceStaleHelper`.
    @ObservationIgnored private var helperRestartAskedAt: Date?
    /// "I need it": one site, let through until this time. The block itself stays on.
    @ObservationIgnored private var allowances: [String: Date] = [:]
    @ObservationIgnored private var allowanceTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var confirmingTabClose = false
    @ObservationIgnored private var lastFilteredTab: ScreenContext?
    @ObservationIgnored private var lastFilteredAt = Date.distantPast
    /// Ignore samples while handing focus back to the browser to close a tab.
    @ObservationIgnored private var closingBrowserPIDs: Set<pid_t> = []
    @ObservationIgnored private var closingPID: pid_t?
    @ObservationIgnored private var closingUntil = Date.distantPast
    @ObservationIgnored private let onboarding = OnboardingController()
    @ObservationIgnored private let mainWindow = MainWindowController()
    @ObservationIgnored private var hysteresis = Hysteresis(requiredHits: 2)
    @ObservationIgnored private var nudgeHysteresis = Hysteresis(requiredHits: 2)
    @ObservationIgnored private var engineTimer: Timer?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var tickCount = 0
    /// The handshake file as this process last wrote it. See `syncLockProtections`.
    @ObservationIgnored private var savedGuardState: GuardState?
    @ObservationIgnored private var guardStateLoaded = false
    /// Unknown until the first tick sets it, so the first tick always applies it.
    @ObservationIgnored private var ignoresSIGTERM: Bool?

    @ObservationIgnored private var lastNudgeSignature: String?
    @ObservationIgnored private var lastNudgeAt = Date.distantPast
    /// When drift hints were shown in the last half hour, so a repeat looks different.
    @ObservationIgnored private var recentHints: [Date] = []
    @ObservationIgnored private var moodTour: Task<Void, Never>?
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
        PermissionsManager.logDiagnostics()
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
        } else {
            serviceObservers.append(center.addObserver(forName: EnforcementService.restartHelper, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.restartRequested = true }
            })
        }
        #if DEBUG
        serviceObservers.append(center.addObserver(forName: EnforcementService.debugPauseClose, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pause.simulate(.close(nil, reflection: nil)) }
        })
        // Command-W to the front browser, as a person would press it: for testing the
        // heads-up from a script.
        serviceObservers.append(center.addObserver(forName: EnforcementService.debugCloseFrontTab, object: nil, queue: .main) { _ in
            Task { @MainActor in
                if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
                    _ = TabCloser.closeIfFrontmost(pid: pid)
                }
            }
        })
        // Command-T: a blank new tab, Safari's Start Page.
        serviceObservers.append(center.addObserver(forName: EnforcementService.debugNewTab, object: nil, queue: .main) { _ in
            Task { @MainActor in
                guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                      let down = CGEvent(keyboardEventSource: nil, virtualKey: 0x11, keyDown: true),
                      let up = CGEvent(keyboardEventSource: nil, virtualKey: 0x11, keyDown: false) else { return }
                for event in [down, up] {
                    event.flags = .maskCommand
                    event.postToPid(pid)
                }
            }
        })
        #endif
        store.onCommit = { [weak self] in
            EnforcementService.notify(EnforcementService.rulesChanged)
            self?.reconcileMonitoring()
        }
    }

    func applicationWillTerminate() {
        if canQuitApp {
            GuardState.clear()
            savedGuardState = nil
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
        // Both processes tick all day. A little slack lets macOS fold these wake-ups into
        // ones it was making anyway, and a schedule still starts within about a second.
        timer.tolerance = 0.1
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
        if tickCount % 5 == 0 {
            restartIfReplaced()
            replaceStaleHelper()
            if !EnforcementService.isAgent && NSApp.isActive {
                refreshSystemState()
            } else if isWatching {
                refreshPermissions()
            }
        }
    }

    /// Keeps both processes on the copy of Shift that's on disk.
    ///
    /// launchd keeps the helper alive for as long as the Mac is up, and the dashboard stays
    /// open all day in the menu bar, so after a rebuild or an update both would otherwise
    /// carry on with the old code: previews showed the new pause while real pauses showed
    /// the old one. Once the new executable has stopped changing for a few seconds:
    ///
    /// - The helper exits, and launchd (`KeepAlive`) starts it again on the new build. It
    ///   also does this when the dashboard says it's stale (`restartRequested`).
    /// - The dashboard relaunches itself quietly, but only while none of its windows is
    ///   open, so nobody loses an edit.
    ///
    /// Neither leaves while a pause is on screen or "I need it" access is running: both live
    /// only in this process, and dropping them would end access early or lose an answer.
    private func restartIfReplaced() {
        guard let launchedExecutable else { return }
        var replaced = false
        if let current = ExecutableStamp.current(), current != launchedExecutable {
            if let pending = pendingExecutable, pending.stamp == current {
                replaced = Date().timeIntervalSince(pending.since) >= 4
            } else {
                pendingExecutable = (current, Date())
            }
        } else {
            pendingExecutable = nil
        }
        let agent = EnforcementService.isAgent
        guard replaced || (agent && restartRequested),
              !pause.isShowing, allowances.isEmpty else { return }

        if agent {
            Self.log.notice("Restarting the background helper on the current build")
            monitor.stop()
            nudgeHUD.hide()
            ReachJournal.shared.flush()
            exit(0)
        } else {
            relaunchDashboard()
        }
    }

    /// Starts this copy of Shift again once this process has gone, then exits. The new one
    /// opens no window (`relaunchedFlag`), so an update in the background stays invisible.
    /// The helper keeps enforcing through the gap, locks included.
    private func relaunchDashboard() {
        // A window someone can type in is open: wait until it's closed.
        guard !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeKey }) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; exec /usr/bin/open -g \"$2\" --args \"$3\"",
            "shift-relaunch",
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundleURL.path(percentEncoded: false),
            EnforcementService.relaunchedFlag,
        ]
        do {
            try process.run()
        } catch {
            Self.log.error("Couldn’t relaunch after an update: \(error.localizedDescription, privacy: .public)")
            return
        }
        Self.log.notice("Shift was updated on disk; relaunching on the new build")
        applicationWillTerminate()
        ReachJournal.shared.flush()
        exit(0)
    }

    /// Dashboard only: makes sure the helper runs this copy of Shift, started after this copy
    /// was last built. Catches a helper from before it could restart itself, and one
    /// registered from another copy (Xcode's build folder against /Applications), which its
    /// own check can't see. It's asked first, so it can finish a pause; if it's still stale
    /// 20 seconds later, it's registered again from this copy.
    private func replaceStaleHelper() {
        guard !EnforcementService.isAgent, backgroundServiceStatus == .enabled,
              let ownExecutable = Bundle.main.executableURL?.resolvingSymlinksInPath(),
              let built = ExecutableStamp.currentBuildDate,
              // A build still being written isn't one to restart onto.
              Date().timeIntervalSince(built) >= 5,
              let bundleID = Bundle.main.bundleIdentifier else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let stale = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { helper in
            guard helper.processIdentifier != ownPID, !helper.isTerminated else { return false }
            let sameCopy = helper.executableURL?.resolvingSymlinksInPath() == ownExecutable
            let started = ExecutableStamp.startDate(of: helper.processIdentifier) ?? .distantPast
            return !sameCopy || started < built
        }
        guard !stale.isEmpty else {
            helperRestartAskedAt = nil
            return
        }
        guard let asked = helperRestartAskedAt else {
            helperRestartAskedAt = Date()
            Self.log.notice("Background helper is out of date; asking it to restart")
            EnforcementService.notify(EnforcementService.restartHelper)
            return
        }
        guard Date().timeIntervalSince(asked) >= 20 else { return }
        helperRestartAskedAt = nil
        Self.log.notice("Background helper didn’t restart; registering it again from this copy")
        repairHelperIfDue()
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
                if !agent, !accessibilityGranted, hasCompletedOnboarding,
                   PermissionsManager.BrowserAccessPane.current != .appProtectionOverride {
                    PermissionsManager.requestAccessibility()
                }
                log("Watching · \(active.count) active block\(active.count == 1 ? "" : "s")", symbol: "eye")
            } else {
                monitor.stop()
                lastContext = nil
                lastVerdict = nil
                pause.dismiss()
                finishOpenReach(.dismissed)
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
            finishOpenReach(.dismissed)
            hysteresis.reset()
            monitor.resampleSoon()
        }

        bundleRecovery?.update(protected: !mayQuit)
        if !agent { syncLockProtections(agentReady: agentReady) }
    }

    private func syncBackgroundService(agentReady: Bool) {
        let wanted = Preferences.keepBackgroundBlockingEnabled || store.blocks.contains { $0.isEnabled || $0.isLocked() }
        if backgroundServiceOffline && (agentReady || !wanted) { backgroundServiceOffline = false }
        guard serviceWanted != wanted || Date() >= nextServiceCheck else { return }
        let firstAttempt = serviceWanted != wanted
        serviceWanted = wanted
        nextServiceCheck = Date().addingTimeInterval(15)
        do {
            let enabled = try registerAgent(wanted)
            backgroundRegistrationFailed = false
            backgroundServiceOffline = wanted && enabled && !agentReady && !firstAttempt
            if backgroundServiceOffline { repairHelperIfDue() }
        } catch {
            backgroundRegistrationFailed = wanted
            backgroundServiceOffline = false
            Self.log.error("Background registration: \(error.localizedDescription, privacy: .public)")
        }
        refreshBackgroundServiceStatus()
    }

    /// Brings back a helper that macOS still allows but launchd isn't running. Without this
    /// nothing ever would: registration skips a service that already reads as enabled, and
    /// Login Items has no switch for it. At most once every two minutes, so a helper that
    /// keeps failing doesn't turn into a registration loop.
    private func repairHelperIfDue() {
        guard !EnforcementService.isAgent, Date().timeIntervalSince(lastHelperRepair) >= 120 else { return }
        lastHelperRepair = Date()
        do {
            try EnforcementService.reload()
            Self.log.notice("Background helper was allowed but not running; reloaded it")
            // Look again soon rather than in the usual 15 seconds.
            nextServiceCheck = Date().addingTimeInterval(5)
        } catch {
            Self.log.error("Background helper reload: \(error.localizedDescription, privacy: .public)")
        }
        refreshBackgroundServiceStatus()
    }

    /// "Restart helper" on the offline row: the same repair, straight away.
    func restartBackgroundHelper() {
        lastHelperRepair = .distantPast
        repairHelperIfDue()
        // The next check counts as a fresh attempt, so the row doesn't call it offline
        // while launchd is still starting it.
        serviceWanted = nil
        reconcileMonitoring()
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
            noteLeaving(context)
        case .nudge:
            hysteresis.reset()
            noteLeaving(context)
            if verdict.source == .rules, !nudgeHysteresis.register(context.signature) { return }
            considerNudge(verdict, on: context)
        case .block:
            nudgeHysteresis.reset()
            if closingBrowserPIDs.contains(context.processID) { return }
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
            reach(reachKey: reachKey, verdict: verdict, context: context)
        }
    }

    // MARK: The heads-up

    /// How long the heads-up card gives someone to close it themselves.
    private static let warningSeconds = 10
    /// Coming back to the same thing this soon after leaving it skips the heads-up, so
    /// stepping away can't restart the clock.
    private static let returnGrace: TimeInterval = 120

    /// A blocked page or app, read twice. First a heads-up card, and the page stays usable;
    /// the pause only comes if it's still open ten seconds later. The user's call
    /// (26 Nov 2026): a warning lets people turn back on their own before Shift steps in.
    private func reach(reachKey: String, verdict: Verdict, context: ScreenContext) {
        let now = Date()
        if let current = warning {
            if current.reachKey == reachKey {
                if current.leftAt == nil {
                    // Still on it: whatever looked like leaving was only a flash.
                    leaving.reset()
                    clearBlank()
                    // Still inside the heads-up: theirs to use until the deadline.
                    guard now >= current.deadline else { return }
                    endWarning()
                    beginReach(reachKey: reachKey, verdict: verdict, context: context)
                    return
                }
                if let left = current.leftAt, now.timeIntervalSince(left) < Self.returnGrace {
                    endWarning()
                    beginReach(reachKey: reachKey, verdict: verdict, context: context)
                    return
                }
            } else if current.leftAt == nil {
                // Hopped from one blocked thing to another during the heads-up.
                endWarning()
                beginReach(reachKey: reachKey, verdict: verdict, context: context)
                return
            }
        }
        startWarning(reachKey: reachKey, verdict: verdict, context: context)
    }

    private func startWarning(reachKey: String, verdict: Verdict, context: ScreenContext) {
        let now = Date()
        let recent = (warnings[reachKey] ?? []).filter { now.timeIntervalSince($0) < Self.reachWindow } + [now]
        warnings[reachKey] = recent

        let name = verdict.ruleTarget?.displayName(appName: context.appName) ?? (context.host ?? context.appName)
        // A website rule in a browser means a tab to close; anything else, an app to quit.
        var closesTab = Browser(bundleID: context.bundleID) != nil
        if case .app = verdict.ruleTarget { closesTab = false }
        warningTask?.cancel()
        leaving.reset()
        clearBlank()
        warning = ReachWarning(
            reachKey: reachKey, verdict: verdict, context: context, name: name,
            started: now, deadline: now.addingTimeInterval(TimeInterval(Self.warningSeconds)),
            count: recent.count
        )

        let copy = PauseCopy.warning(name: name, blockName: verdict.blockName ?? "Shift", count: recent.count,
                                     closesTab: closesTab)
        nudgeHUD.warning(headline: copy.headline, detail: copy.detail, mood: copy.mood, seconds: Self.warningSeconds)
        log("Heads-up · \(name)", symbol: "hand.raised")

        warningTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.warningSeconds))
            guard !Task.isCancelled else { return }
            self?.warningRanOut(reachKey)
        }
    }

    /// Time's up: read the screen again. Still on the blocked page means the pause (`reach`
    /// sees the deadline has passed); anywhere else, nothing.
    private func warningRanOut(_ reachKey: String) {
        guard let current = warning, current.reachKey == reachKey, current.leftAt == nil else { return }
        hysteresis.reset()
        monitor.resampleSoon()
    }

    /// Something other than the blocked page is in front during a heads-up: a closed tab,
    /// another site, another app, or a quit app. That's turning back on their own, and it's
    /// praised the moment it's seen, not when the ten seconds run out.
    ///
    /// Another page or app counts after two matching readings, 150 ms apart. A browser
    /// showing no page at all (Safari's Start Page, an empty tab, a window that closed with
    /// its last tab) counts once that has lasted a second: the same blank also flashes by
    /// between two pages, and that isn't leaving. Until 26 Nov 2026 a blank never counted,
    /// so closing a tab onto the Start Page went unnoticed until something else changed.
    private func noteLeaving(_ context: ScreenContext) {
        guard let current = warning, current.leftAt == nil else { return }
        let blank = context.processID == current.context.processID
            && Browser(bundleID: context.bundleID) != nil && context.url == nil
        if blank {
            leaving.reset()
            let since = blankSince ?? Date()
            blankSince = since
            if Date().timeIntervalSince(since) >= 1 {
                Self.log.notice("Heads-up: left \(current.name, privacy: .public) for a blank page")
                turnedBackDuringWarning()
            } else if blankCheck == nil {
                blankCheck = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(1050))
                    guard let self, !Task.isCancelled else { return }
                    self.blankCheck = nil
                    self.monitor.resampleSoon()
                }
            }
            return
        }
        clearBlank()
        guard leaving.register(context.signature) else {
            monitor.resampleSoon()
            return
        }
        Self.log.notice("Heads-up: left \(current.name, privacy: .public) for \(context.host ?? context.appName, privacy: .public) after \(Date().timeIntervalSince(current.started), format: .fixed(precision: 2)) s")
        turnedBackDuringWarning()
    }

    private func clearBlank() {
        blankSince = nil
        blankCheck?.cancel()
        blankCheck = nil
    }

    /// Praise, a journal line and no pause: the best way a reach can end.
    private func turnedBackDuringWarning() {
        guard var current = warning, current.leftAt == nil else { return }
        let now = Date()
        current.leftAt = now
        warning = current
        warningTask?.cancel()
        warningTask = nil
        leaving.reset()
        clearBlank()

        reward(PauseCopy.rewardForTurningBackEarly())
        log("Turned back early · \(current.name)", symbol: "arrow.uturn.backward")

        let context = current.context
        ReachJournal.shared.begin(ReachEntry(
            id: UUID(),
            startedAt: current.started,
            endedAt: now,
            blockID: current.verdict.blockID,
            blockName: current.verdict.blockName ?? "Shift",
            rule: current.name,
            target: context.host ?? context.appName,
            appName: context.appName,
            bundleID: context.bundleID,
            url: context.url?.absoluteString,
            windowTitle: context.windowTitle,
            visit: current.count,
            waitSeconds: 0,
            outcome: .leftEarly
        ))
    }

    private func endWarning() {
        warningTask?.cancel()
        warningTask = nil
        warning = nil
        leaving.reset()
        clearBlank()
    }

    private func closeMatchingTab(_ verdict: Verdict, context: ScreenContext) {
        guard !confirmingTabClose, let observedURL = context.url else { return }
        if let lastFilteredTab, lastFilteredTab.processID == context.processID,
           lastFilteredTab.windowID == context.windowID, lastFilteredTab.url == observedURL,
           Date().timeIntervalSince(lastFilteredAt) < (PermissionsManager.canPostKeyboardEvents ? 0.5 : 5) { return }

        confirmingTabClose = true
        Task {
            defer { confirmingTabClose = false }
            guard let live = await monitor.confirm(context, readWebsite: true),
                  live.url == observedURL, live.windowID == context.windowID, !pause.isShowing,
                  lastContext?.processID == live.processID, lastContext?.url == observedURL,
                  lastContext?.windowID == live.windowID,
                  let current = currentEvaluator.ruleVerdict(for: live),
                  current.closesTab, let blockID = current.blockID, blockID == verdict.blockID else { return }
            let result = TabCloser.closeIfFrontmost(pid: live.processID)
            guard result != .targetUnavailable else { return }
            lastFilteredTab = live
            lastFilteredAt = Date()
            guard result == .closed else {
                showManualTabClose()
                return
            }
            store.recordTrigger(id: blockID)
            log("Sent close shortcut · \(current.blockName ?? "Block")", symbol: "xmark.circle")
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
        let copy = PauseCopy.pause(visit: recent.count)
        let request = PauseRequest(
            blockName: verdict.blockName ?? "Shift",
            blockID: blockID,
            ruleTarget: verdict.ruleTarget,
            target: target,
            appName: context.appName,
            isBrowser: Browser(bundleID: context.bundleID) != nil,
            visit: recent.count,
            title: copy.title,
            subtitle: copy.subtitle
        )
        nudgeHUD.hide()
        if playNudgeSounds { NudgeSound.playPause() }
        log("Paused · \(target)", symbol: "wind")
        finishOpenReach(.dismissed)
        openReachID = request.journalID
        ReachJournal.shared.begin(ReachEntry(
            id: request.journalID,
            startedAt: now,
            blockID: blockID,
            blockName: request.blockName,
            rule: request.blockedTarget,
            target: target,
            appName: context.appName,
            bundleID: context.bundleID,
            url: context.url?.absoluteString,
            windowTitle: context.windowTitle,
            visit: request.visit,
            waitSeconds: request.waitSeconds,
            outcome: .open
        ))
        pause.present(request) { [weak self] event in
            self?.handlePause(event, request: request, context: context)
        }
    }

    private func handlePause(_ event: PauseEvent, request: PauseRequest, context: ScreenContext) {
        hysteresis.reset()
        let journalID = request.isPreview ? nil : request.journalID
        if openReachID == journalID { openReachID = nil }

        switch event {
        case .close(let reason, let reflection):
            // Journaled at the decision, whether or not the tab close lands.
            if let journalID {
                ReachJournal.shared.finish(id: journalID, outcome: .closed, feeling: reason, reflection: reflection)
            }
            let closesBrowserTab = request.closesTab && !request.isPreview
            pause.dismiss(animated: !closesBrowserTab)
            if closesBrowserTab {
                let pid = context.processID
                closingBrowserPIDs.insert(pid)
                Task {
                    defer { closingBrowserPIDs.remove(pid) }
                    // Still blocked means any rule still matches, wherever the page has
                    // redirected to since the pause went up.
                    let result = await TabCloser.closeFrontTab(for: context) { [weak self] live in
                        self?.currentEvaluator.ruleVerdict(for: live)?.kind == .block
                    }
                    switch result {
                    case .closed:
                        pauseBlockingAfterCloseAttempt(pid: pid)
                        recordTurnBack(reason, request: request)
                    case .keyboardAccessUnavailable:
                        pauseBlockingAfterCloseAttempt(pid: pid, seconds: 5)
                        showManualTabClose()
                    case .targetUnavailable:
                        nudgeHUD.status(headline: "Couldn’t close that tab.", detail: "Please close it yourself this time.", mood: .worried)
                        monitor.resampleSoon()
                    }
                }
            } else {
                if !request.isPreview {
                    pauseBlockingAfterCloseAttempt(pid: context.processID)
                    let pid = context.processID
                    Task { await TabCloser.quit(pid: pid) }
                }
                recordTurnBack(reason, request: request)
            }

        case .takeBreak(let minutes, let note):
            pause.dismiss()
            let ends = Date().addingTimeInterval(TimeInterval(minutes) * 60)
            guard !request.isPreview else {
                nudgeHUD.access(target: request.blockedTarget, note: note, until: ends)
                return
            }

            // The process, rule or schedule may have changed during the wait.
            guard AccessPlan.minutes.contains(minutes),
                  let app = NSRunningApplication(processIdentifier: context.processID),
                  !app.isTerminated, app.bundleIdentifier == context.bundleID,
                  let blockID = request.blockID, let block = store.block(id: blockID),
                  let verdict = BlockEvaluator(blocks: [block], driftKeywords: []).ruleVerdict(for: context),
                  verdict.ruleTarget == request.ruleTarget, let reachKey = reachKey(for: verdict) else {
                if let journalID {
                    ReachJournal.shared.finish(id: journalID, outcome: .dismissed, feeling: .needed, reflection: note)
                }
                monitor.resampleSoon()
                nudgeHUD.status(headline: "Access didn’t start.", detail: "\(request.blockedTarget) wasn’t open anymore.", mood: .worried)
                return
            }

            if let journalID {
                ReachJournal.shared.finish(id: journalID, outcome: .breakTaken, feeling: .needed, reflection: note, breakMinutes: minutes)
            }
            allow(reachKey: reachKey, minutes: minutes)
            NSApp.yieldActivation(to: app)
            app.activate()
            // Counts down for the whole access, so the end never comes as a surprise.
            nudgeHUD.access(target: request.blockedTarget, note: note, until: ends)
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

    private func showManualTabClose() {
        let path = PermissionsManager.BrowserAccessPane.current.settingsPath
        nudgeHUD.status(headline: "Please close the tab yourself.", detail: "To do it for you, I need access in \(path).", mood: .worried)
    }

    private func pauseBlockingAfterCloseAttempt(pid: pid_t, seconds: TimeInterval = 1.5) {
        closingPID = pid
        closingUntil = Date().addingTimeInterval(seconds)
    }

    // MARK: Reward

    /// Marks the pause on screen as ended without an answer, when Shift takes it down itself.
    private func finishOpenReach(_ outcome: ReachEntry.Outcome) {
        guard let id = openReachID else { return }
        openReachID = nil
        ReachJournal.shared.finish(id: id, outcome: outcome)
    }

    private func recordTurnBack(_ reason: UrgeReason?, request: PauseRequest) {
        reward(PauseCopy.reward(for: reason, visit: request.visit))
        log("Turned back · \(request.target)\(reason.map { " · \($0.shortLabel)" } ?? "")",
            symbol: "arrow.uturn.backward")
    }

    /// Praise, the moment someone turns back. This is the step that builds the habit:
    /// behaviour that's rewarded straight away repeats, and before this, turning back got
    /// nothing at all.
    ///
    /// Close to two hundred lines in `PauseCopy`, specific to the moment and to what they
    /// named, each with its mood, and dealt so none repeats soon: the same line every time
    /// stops being heard.
    private func reward(_ line: PauseCopy.Reward) {
        nudgeHUD.reward(headline: line.title, detail: line.subtitle, mood: line.mood)
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
        // A hint never covers the heads-up, praise or the access countdown.
        if let kind = nudgeHUD.showingKind, kind == .warning || kind == .reward || kind == .access { return }

        let isRepeat = context.signature == lastNudgeSignature
        let withinCooldown = Date().timeIntervalSince(lastNudgeAt) < nudgeCooldown
        guard !(isRepeat && withinCooldown) else { return }

        lastNudgeSignature = context.signature
        lastNudgeAt = Date()

        let location = context.host ?? context.appName
        // Curious the first time, cheeky the second, worried after that: the same drift
        // coming back should read differently from the first.
        let now = Date()
        recentHints = recentHints.filter { now.timeIntervalSince($0) < 30 * 60 } + [now]
        let mood: MascotMood = switch recentHints.count {
        case 1: .curious
        case 2: .cheeky
        default: .worried
        }
        nudgeHUD.hint(reason: verdict.reason, detail: location, mood: mood)
        log("Nudged · \(location)", symbol: "arrow.turn.up.left")
    }

    // MARK: Lock protections

    /// Keeps SIGTERM handling, the watchdog and the handshake file in step with whether
    /// any block is currently locked.
    private func syncLockProtections(agentReady: Bool) {
        if ignoresSIGTERM != !canQuitApp {
            ignoresSIGTERM = !canQuitApp
            signal(SIGTERM, canQuitApp ? SIG_DFL : SIG_IGN)
        }

        // Only this process writes the handshake, so remember it rather than reading and
        // decoding the file on every tick. Read once, to clear one left by a crash.
        if !guardStateLoaded {
            savedGuardState = GuardState.load()
            guardStateLoaded = true
        }
        guard let deadline = store.lockedUntil else {
            if savedGuardState != nil {
                GuardState.clear()
                savedGuardState = nil
            }
            if WatchdogService.hasConfiguration { WatchdogService.remove() }
            return
        }

        let names = store.lockedBlocks.filter(\.isEnabled).map(\.name).joined(separator: ", ")
        if savedGuardState?.lockedUntil != deadline || savedGuardState?.goal != names || tickCount % 10 == 0 {
            let state = GuardState(
                lockedUntil: deadline,
                bundlePath: Bundle.main.bundleURL.path,
                goal: names,
                heartbeat: Date()
            )
            state.save()
            savedGuardState = state
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
            isBrowser: true, visit: visit,
            title: copy.title, subtitle: copy.subtitle, isPreview: true
        )
        let context = ScreenContext(bundleID: "com.apple.Safari", appName: "Safari", processID: 0)
        if playNudgeSounds { NudgeSound.playPause() }
        pause.present(request) { [weak self] event in
            self?.handlePause(event, request: request, context: context)
        }
    }

    func previewReward() {
        reward(PauseCopy.reward(for: nil, visit: 1))
    }

    /// Settings → Previews: every mascot mood in turn on the nudge card, with its name and
    /// where it's used.
    func previewMoods() {
        moodTour?.cancel()
        moodTour = Task { [weak self] in
            for mood in MascotMood.allCases {
                guard let self, !Task.isCancelled else { return }
                self.nudgeHUD.status(headline: mood.title, detail: mood.use, mood: mood)
                try? await Task.sleep(for: .seconds(2.6))
            }
        }
    }

    /// Settings → Previews: the heads-up card as it appears before a pause.
    func previewWarning() {
        let copy = PauseCopy.warning(name: "instagram.com", blockName: "Distractions", count: 1, closesTab: true)
        nudgeHUD.warning(headline: copy.headline, detail: copy.detail, mood: copy.mood, seconds: Self.warningSeconds)
    }

    func previewHint() {
        nudgeHUD.hint(reason: "“Shorts” looks like a feed", detail: "youtube.com")
    }

    // MARK: Windows

    /// Shows a window: setup on first launch, the main window after it. Called at every
    /// launch and reopen, so a menu bar app never starts with nothing on screen.
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
        refreshSystemState()
        if let section { mainSection = section }
        mainWindow.present(model: self)
    }

    func presentOnboarding() {
        refreshSystemState()
        onboarding.present(model: self)
    }

    /// Closing setup with its close button only orders the window out, so its views live on.
    var isOnboardingVisible: Bool { onboarding.isShowing }

    func completeOnboarding(with block: Block) -> Bool {
        refreshBackgroundServiceStatus()
        guard backgroundBlockingAllowed else { return false }
        Preferences.keepBackgroundBlockingEnabled = true
        store.add(block)
        log("Created “\(block.name)”", symbol: "plus.circle")
        hasCompletedOnboarding = true
        Preferences.hasCompletedOnboarding = true
        return true
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
        let postEvents = PermissionsManager.canPostKeyboardEvents
        if postEvents != keyboardEventsGranted { keyboardEventsGranted = postEvents }
        let accessibility = PermissionsManager.isAccessibilityTrusted
        if accessibility != accessibilityGranted {
            Self.log.notice("Accessibility changed: \(accessibility, privacy: .public)")
            accessibilityGranted = accessibility
            monitor.invalidate()
            monitor.resampleSoon()
        }
    }

    func requestBrowserAccess() {
        PermissionsManager.requestBrowserAccess()
    }

    func refreshSystemState() {
        refreshPermissions()
        refreshBackgroundServiceStatus()
        let status = LaunchAtLogin.status
        let enabled = status == .enabled
        let needsApproval = status == .requiresApproval
        if launchAtLoginEnabled != enabled { launchAtLoginEnabled = enabled }
        if launchAtLoginNeedsApproval != needsApproval { launchAtLoginNeedsApproval = needsApproval }
    }

    func refreshBackgroundServiceStatus() {
        let status = EnforcementService.service.status
        if backgroundServiceStatus != status { backgroundServiceStatus = status }
    }

    func enableBackgroundBlocking() {
        refreshBackgroundServiceStatus()
        Preferences.keepBackgroundBlockingEnabled = true
        if backgroundServiceStatus == .requiresApproval {
            LaunchAtLogin.openLoginItemsSettings()
        } else {
            // Give launchd time to start the helper after an explicit retry.
            serviceWanted = nil
            reconcileMonitoring()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if enabled && LaunchAtLogin.requiresApproval {
            LaunchAtLogin.openLoginItemsSettings()
        } else {
            LaunchAtLogin.setEnabled(enabled)
        }
        refreshSystemState()
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
        static let keepBackgroundBlockingEnabled = "Shift.keepBackgroundBlockingEnabled"
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

    static var keepBackgroundBlockingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.keepBackgroundBlockingEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Key.keepBackgroundBlockingEnabled) }
    }
}

/// The heads-up before the pause: what was reached for, when, and whether they left it.
private struct ReachWarning {
    let reachKey: String
    let verdict: Verdict
    let context: ScreenContext
    /// The rule as the person reads it: "x.com", "Steam".
    let name: String
    let started: Date
    let deadline: Date
    /// Which heads-up this is for the rule within the hour: 1, 2, 3 or more.
    let count: Int
    /// When they turned back during it, if they did.
    var leftAt: Date?
}
