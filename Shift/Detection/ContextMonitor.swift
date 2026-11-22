import AppKit

/// Watches the frontmost app and produces `ScreenContext` readings (PRD §8, Tier 0).
///
/// Samples immediately on every app switch, plus a light poll to catch tab and title
/// changes inside the same app. Every sample is emitted (not deduplicated) so that
/// hysteresis can count consistent readings.
@MainActor
final class ContextMonitor {
    var onSample: ((ScreenContext) -> Void)?
    var pollInterval: TimeInterval = 1.5

    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?

    var isRunning: Bool { timer != nil }

    func start() {
        stop()

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }

        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }

        sample()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    private func sample() {
        guard
            let app = NSWorkspace.shared.frontmostApplication,
            let bundleID = app.bundleIdentifier,
            bundleID != Bundle.main.bundleIdentifier
        else { return }

        let context = ScreenContext(
            bundleID: bundleID,
            appName: app.localizedName ?? bundleID,
            processID: app.processIdentifier,
            windowTitle: WindowInspector.focusedWindowTitle(pid: app.processIdentifier),
            url: Browser(bundleID: bundleID)?.currentURL(),
            screenText: nil
        )
        onSample?(context)
    }
}
