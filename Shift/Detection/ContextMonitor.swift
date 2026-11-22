import AppKit
import Foundation

/// Produces `ScreenContext` readings while any block is active.
///
/// Threading: the monitor itself is main-actor, because it owns a timer and talks to
/// `NSWorkspace`. The expensive parts of a reading are not. Window titles, Apple Events
/// and screen capture each run off the main actor and are awaited, so a slow browser or a
/// busy capture never stalls the UI. Overlapping samples are dropped rather than queued,
/// which keeps a slow reading from building a backlog behind it.
@MainActor
final class ContextMonitor {
    var onSample: ((ScreenContext) -> Void)?

    /// How often to re-read within the same app. App switches are event-driven and
    /// immediate; this only exists to catch tab and title changes.
    var pollInterval: TimeInterval = 1.5

    /// Screen capture is skipped entirely unless this is on. It stays off until the
    /// intent tier gives the captured text a consumer.
    var wantsScreenText = false

    private let screenReader = ScreenTextReader()
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var samplingTask: Task<Void, Never>?

    var isRunning: Bool { timer != nil }

    func start() {
        guard !isRunning else { return }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }

        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        // Common mode so readings continue while a menu or resize loop is running.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        sample()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        samplingTask?.cancel()
        samplingTask = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    /// Forces the next screen-text read to do real work rather than trusting the change gate.
    func invalidateScreenTextCache() {
        Task { await screenReader.invalidateChangeGate() }
    }

    private func sample() {
        // A reading still in flight means the previous one is slow. Skip rather than pile up.
        guard samplingTask == nil else { return }

        guard
            let app = NSWorkspace.shared.frontmostApplication,
            let bundleID = app.bundleIdentifier,
            bundleID != Bundle.main.bundleIdentifier
        else { return }

        let appName = app.localizedName ?? bundleID
        let pid = app.processIdentifier
        let needsScreenText = wantsScreenText

        samplingTask = Task { [weak self] in
            defer { self?.samplingTask = nil }

            // Each of these hops off the main actor on its own.
            async let title = WindowInspector.focusedWindowTitle(pid: pid)
            async let url = Browser(bundleID: bundleID)?.currentURL()

            var screenText: String?
            if needsScreenText {
                screenText = await self?.screenReader.readFrontmostWindowText(pid: pid)
            }

            let context = await ScreenContext(
                bundleID: bundleID,
                appName: appName,
                processID: pid,
                windowTitle: title,
                url: url,
                screenText: screenText
            )

            guard !Task.isCancelled else { return }
            self?.onSample?(context)
        }
    }
}
