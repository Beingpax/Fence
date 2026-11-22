import AppKit
import Foundation

/// Samples cheap signals while blocks are active. Interaction invalidates semantic
/// readings, and the next stable context can trigger a fresh on-demand text reading.
@MainActor
final class ContextMonitor {
    var onSample: ((ScreenContext) -> Void)?
    var onInvalidation: (() -> Void)?

    private let pollInterval: TimeInterval = 1.5
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var interactionMonitor: Any?
    private var tracksInteraction = false
    private var samplingTask: Task<Void, Never>?
    private var latestContext: ScreenContext?
    private var revision: UInt64 = 0
    private var lastInteraction: ContinuousClock.Instant?
    private var accessibilityPreparedPID: pid_t?

    var isRunning: Bool { timer != nil }

    func start() {
        guard !isRunning else { return }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.invalidate()
                self?.sample()
            }
        }

        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sample()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        samplingTask?.cancel()
        samplingTask = nil
        invalidate()
        latestContext = nil
        accessibilityPreparedPID = nil
        lastInteraction = nil

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        trackInteraction(false)
    }

    func trackInteraction(_ enabled: Bool) {
        guard tracksInteraction != enabled else { return }
        tracksInteraction = enabled

        guard enabled else {
            if let interactionMonitor { NSEvent.removeMonitor(interactionMonitor) }
            interactionMonitor = nil
            lastInteraction = nil
            return
        }

        // Mouse events provide a change signal for same-page scrolling and navigation.
        // The event's contents are unused, and there is no keyboard event monitor.
        interactionMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.scrollWheel, .leftMouseUp, .rightMouseUp]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lastInteraction = .now
                self?.invalidate()
            }
        }
    }

    func invalidate() {
        revision &+= 1
        onInvalidation?()
    }

    var interactionIsSettled: Bool {
        guard let lastInteraction else { return true }
        return lastInteraction.duration(to: .now) >= .milliseconds(450)
    }

    func isCurrent(_ context: ScreenContext) -> Bool {
        isRunning && latestContext == context && context.revision == revision
            && NSWorkspace.shared.frontmostApplication?.processIdentifier == context.processID
    }

    private func sample() {
        guard samplingTask == nil, isRunning else { return }

        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier
        else {
            latestContext = nil
            return
        }

        let appName = app.localizedName ?? bundleID
        let pid = app.processIdentifier
        let browser = Browser(bundleID: bundleID)
        let prepareAccessibility = browser?.isChromium == true && accessibilityPreparedPID != pid
            && PermissionsManager.isAccessibilityTrusted
        if prepareAccessibility { accessibilityPreparedPID = pid }

        samplingTask = Task { [weak self] in
            defer {
                // A cancelled sample may finish after a new timer has started.
                if !Task.isCancelled { self?.samplingTask = nil }
            }
            let snapshot = await WindowInspector.snapshot(pid: pid, browser: browser, prepareAccessibility: prepareAccessibility)

            guard let self, !Task.isCancelled, self.isRunning,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            else { return }

            let context = ScreenContext(
                bundleID: bundleID,
                appName: appName,
                processID: pid,
                windowTitle: snapshot.title,
                url: snapshot.url,
                windowID: snapshot.windowID,
                revision: self.revision
            )
            self.latestContext = context
            self.onSample?(context)
        }
    }
}
