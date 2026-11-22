import AppKit
import Foundation

/// Samples the foreground app and its window while blocks are active.
@MainActor
final class ContextMonitor {
    var onSample: ((ScreenContext) -> Void)?
    var onInvalidation: (() -> Void)?

    private let pollInterval: TimeInterval = 1.5
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var samplingTask: Task<Void, Never>?
    private var revision: UInt64 = 0
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
        accessibilityPreparedPID = nil

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    func invalidate() {
        revision &+= 1
        onInvalidation?()
    }

    /// Checks the live foreground app and, for a site rule, reads the browser again.
    func confirm(_ context: ScreenContext, readWebsite: Bool) async -> ScreenContext? {
        guard isRunning, !Task.isCancelled,
              let app = NSWorkspace.shared.frontmostApplication, !app.isTerminated,
              app.processIdentifier == context.processID, app.bundleIdentifier == context.bundleID else { return nil }
        if !readWebsite { return context }

        guard let browser = Browser(bundleID: context.bundleID) else { return nil }
        let expectedRevision = revision
        let snapshot = await WindowInspector.snapshot(
            pid: context.processID, browser: browser, prepareAccessibility: false, verifyURL: true
        )
        guard isRunning, !Task.isCancelled, revision == expectedRevision, !app.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == context.processID,
              let url = snapshot.url else { return nil }

        var refreshed = context
        refreshed.url = url
        refreshed.windowTitle = snapshot.title
        refreshed.windowID = snapshot.windowID
        return refreshed
    }

    private func sample() {
        guard samplingTask == nil, isRunning else { return }

        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier
        else { return }

        let appName = app.localizedName ?? bundleID
        let pid = app.processIdentifier
        let browser = Browser(bundleID: bundleID)
        let prepareAccessibility = browser?.isChromium == true && accessibilityPreparedPID != pid
            && PermissionsManager.isAccessibilityTrusted
        if prepareAccessibility { accessibilityPreparedPID = pid }

        let sampleRevision = revision
        samplingTask = Task { [weak self] in
            defer {
                // A cancelled sample may finish after a new timer has started.
                if !Task.isCancelled, let self {
                    self.samplingTask = nil
                    if self.revision != sampleRevision { self.sample() }
                }
            }
            let snapshot = await WindowInspector.snapshot(pid: pid, browser: browser, prepareAccessibility: prepareAccessibility)

            guard let self, !Task.isCancelled, self.isRunning, self.revision == sampleRevision,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            else { return }

            let context = ScreenContext(
                bundleID: bundleID,
                appName: appName,
                processID: pid,
                windowTitle: snapshot.title,
                url: snapshot.url,
                windowID: snapshot.windowID
            )
            self.onSample?(context)
        }
    }
}
