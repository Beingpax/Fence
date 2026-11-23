import AppKit
import Foundation

/// Samples the foreground app and its window while blocks are active.
///
/// Two triggers. `AddressObserver` asks for a sample the instant the front app navigates,
/// switches windows or moves focus, which is what lets the pause land before a feed has
/// loaded. The 1.5 s poll is the backstop for apps that post no Accessibility notifications.
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
    private let addressObserver = AddressObserver()
    /// A trigger arrived while a sample was in flight; take another once it lands.
    private var wantsResample = false
    private var resampleTask: Task<Void, Never>?

    var isRunning: Bool { timer != nil }

    func start() {
        guard !isRunning else { return }

        addressObserver.onChange = { [weak self] in self?.sample() }
        observeFrontmost()

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.observeFrontmost()
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
        // Keep ownership until the in-flight AX call returns. A restart queues a fresh sample.
        samplingTask?.cancel()
        resampleTask?.cancel()
        resampleTask = nil
        wantsResample = false
        addressObserver.stop()
        invalidate()
        accessibilityPreparedPID = nil

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    func invalidate() {
        revision &+= 1
        samplingTask?.cancel()
        onInvalidation?()
    }

    /// A second reading shortly after the first, so a new match can be confirmed in a
    /// fraction of a second instead of waiting a whole poll interval.
    func resampleSoon() {
        guard isRunning, resampleTask == nil else { return }
        resampleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled else { return }
            self.resampleTask = nil
            self.sample()
        }
    }

    /// Follows the front app with the address observer. Shift itself is skipped, so a
    /// Shift panel taking focus never unhooks the browser underneath it.
    private func observeFrontmost() {
        guard PermissionsManager.isAccessibilityTrusted else {
            if addressObserver.pid != nil { addressObserver.stop() }
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier
        else { return }
        addressObserver.observe(pid: app.processIdentifier)
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
        guard isRunning else { return }
        observeFrontmost()
        guard samplingTask == nil else {
            wantsResample = true
            return
        }

        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier
        else { return }

        let appName = app.localizedName ?? bundleID
        let pid = app.processIdentifier
        let browser = Browser(bundleID: bundleID)
        let prepareAccessibility = browser?.isChromium == true && accessibilityPreparedPID != pid
            && PermissionsManager.isAccessibilityTrusted

        let sampleRevision = revision
        samplingTask = Task { [weak self] in
            defer {
                if let self {
                    self.samplingTask = nil
                    if self.isRunning, self.revision != sampleRevision || self.wantsResample {
                        self.wantsResample = false
                        self.sample()
                    }
                }
            }
            let snapshot = await WindowInspector.snapshot(pid: pid, browser: browser, prepareAccessibility: prepareAccessibility)

            guard let self, !Task.isCancelled, self.isRunning, self.revision == sampleRevision,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            else { return }
            if prepareAccessibility { self.accessibilityPreparedPID = pid }

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
