import AppKit
import Observation

/// Owns the session and wires detection → classification → enforcement.
@MainActor
@Observable
final class AppModel {
    // MARK: Observable state

    private(set) var session: FocusSession?
    private(set) var lastContext: ScreenContext?
    private(set) var lastVerdict: Verdict?
    private(set) var activity: [ActivityEvent] = []
    private(set) var accessibilityGranted = PermissionsManager.isAccessibilityTrusted

    var rules: BlockRules = .load() {
        didSet { rules.save() }
    }

    // MARK: Engine

    @ObservationIgnored private let monitor = ContextMonitor()
    @ObservationIgnored private let shield = ShieldController()
    @ObservationIgnored private var hysteresis = Hysteresis(requiredHits: 2)
    @ObservationIgnored private var expiryTimer: Timer?

    private var classifier: DistractionClassifier {
        CascadeClassifier(rules: RuleBasedClassifier(rules: rules), model: nil)
    }

    init() {
        monitor.onSample = { [weak self] context in
            self?.handle(context)
        }
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
        log("Started: \(trimmed) · \(minutes) min · \(strictness.title)", symbol: "play.fill")

        refreshPermissions()
        if !accessibilityGranted { PermissionsManager.requestAccessibility() }

        monitor.start()
        expiryTimer?.invalidate()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let session = self.session, session.isExpired else { return }
                self.finishSession(completed: true)
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
        if let session {
            let outcome = completed ? "Completed" : "Ended early"
            log("\(outcome) · \(session.strikes) strike\(session.strikes == 1 ? "" : "s")", symbol: "checkmark.seal.fill")
        }
        session = nil
        lastContext = nil
        lastVerdict = nil
    }

    // MARK: Detection → enforcement

    private func handle(_ context: ScreenContext) {
        if lastContext != context { lastContext = context }
        guard let session, !shield.isShowing else { return }

        let verdict = classifier.classify(context, session: session)
        if lastVerdict != verdict { lastVerdict = verdict }

        guard verdict.kind == .block else {
            hysteresis.reset()
            return
        }
        guard hysteresis.register(context.signature) else { return }

        enforce(verdict, on: context)
    }

    private func enforce(_ verdict: Verdict, on context: ScreenContext) {
        guard var session else { return }
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
            // TODO(P2): save (goal, context) as a local training example for the personal adapter.
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

    // MARK: Helpers

    func refreshPermissions() {
        accessibilityGranted = PermissionsManager.isAccessibilityTrusted
    }

    private func log(_ text: String, symbol: String) {
        activity.insert(ActivityEvent(text, symbol: symbol), at: 0)
        if activity.count > 20 { activity.removeLast(activity.count - 20) }
    }
}
