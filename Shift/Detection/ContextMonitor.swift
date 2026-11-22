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
                if !Task.isCancelled { self?.samplingTask = nil }
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
