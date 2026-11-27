import AppKit
import ServiceManagement

/// A bundled, user-approved login agent runs the same rule engine and pause UI
/// independently of the dashboard. The main app can still enforce locally while
/// macOS is waiting for approval.
@MainActor
enum EnforcementService {
    static let agentFlag = "--enforcement-agent"
    static let isAgent = CommandLine.arguments.contains(agentFlag)
    /// One plist per build (`AppIdentity.helperPlistName`), so Fence and Fence Dev each
    /// run their own helper under their own label.
    static let service = SMAppService.agent(plistName: AppIdentity.helperPlistName)
    private static let notificationPrefix = AppIdentity.bundleID
    static let rulesChanged = Notification.Name("\(notificationPrefix).rulesChanged")
    static let openDashboard = Notification.Name("\(notificationPrefix).openDashboard")
    static let agentReady = Notification.Name("\(notificationPrefix).enforcementReady")
    /// Sent by the dashboard when the helper is running an older or different copy of
    /// Fence. The helper restarts as soon as no pause or break is in progress.
    static let restartHelper = Notification.Name("\(notificationPrefix).restartHelper")
    /// Passed when Fence relaunches itself after an update, so it comes back quietly
    /// instead of opening its window.
    static let relaunchedFlag = "--relaunched-after-update"
    #if DEBUG
    /// Presses Close on the pause on screen. Debug builds only, for scripted testing.
    static let debugPauseClose = Notification.Name("\(notificationPrefix).debugPauseClose")
    /// Presses Command-W in the front browser. Debug builds only, for scripted testing.
    static let debugCloseFrontTab = Notification.Name("\(notificationPrefix).debugCloseFrontTab")
    /// Presses Command-T in the front browser. Debug builds only, for scripted testing.
    static let debugNewTab = Notification.Name("\(notificationPrefix).debugNewTab")
    #endif

    @discardableResult
    static func registerIfNeeded(enabled: Bool) throws -> Bool {
        switch (enabled, service.status) {
        // `.notFound` is what macOS reports for an agent that has never been registered
        // (its login-items record doesn't exist yet), so it needs registering too.
        // Treating only `.notRegistered` as "not yet" meant the helper was never set up.
        case (true, .notRegistered), (true, .notFound): try service.register()
        case (false, .enabled), (false, .requiresApproval): try service.unregister()
        default: break
        }
        return service.status == .enabled
    }

    /// Loads the helper again when macOS still lists it as allowed but launchd isn't running
    /// it: unloaded by hand (`launchctl bootout`), or given up on after crashing repeatedly.
    /// `register()` refuses a service that's already registered, so it has to be
    /// unregistered first; registering again is what asks launchd to start it. The approval
    /// in Login Items is kept, because it belongs to the app rather than to the job.
    static func reload() throws {
        try? service.unregister()
        try service.register()
    }

    static func lease(_ name: String) throws -> ProcessLease {
        let directory = FenceInstallation.supportDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try ProcessLease(url: directory.appending(path: name))
    }

    /// Descriptors kept open for `hasOwner`, by lock name, with the file they were opened on.
    private static var probes: [String: (descriptor: Int32, file: UInt64)] = [:]

    /// Whether another process holds the named lease. The dashboard asks about the helper
    /// once a second, so the probe stays open between calls: before 26 Nov 2026 each call
    /// created the folder, opened the file and closed it again, the largest part of the
    /// dashboard's idle work in Instruments. A lock file replaced or deleted since is
    /// opened afresh, so a helper that starts on a new file is never missed.
    static func hasOwner(_ name: String) -> Bool {
        let path = FenceInstallation.supportDirectory.appending(path: name).path
        var onDisk = stat()
        // No file, no owner: every lease creates its file before locking it.
        guard stat(path, &onDisk) == 0 else {
            closeProbe(name)
            return false
        }
        if let probe = probes[name], probe.file != UInt64(onDisk.st_ino) { closeProbe(name) }
        if probes[name] == nil {
            let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            guard descriptor >= 0 else { return false }
            var opened = stat()
            guard fstat(descriptor, &opened) == 0 else {
                close(descriptor)
                return false
            }
            probes[name] = (descriptor, UInt64(opened.st_ino))
        }
        guard let descriptor = probes[name]?.descriptor else { return false }
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            if errno == EINTR { continue }
            return errno == EWOULDBLOCK
        }
        // Free again at once: holding it would stop the owner from starting.
        flock(descriptor, LOCK_UN)
        return false
    }

    private static func closeProbe(_ name: String) {
        guard let probe = probes.removeValue(forKey: name) else { return }
        close(probe.descriptor)
    }

    static func notify(_ name: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    }

    static func runDashboard() {
        do {
            let presence = try lease("dashboard.lock")
            withExtendedLifetime(presence) { FenceApp.main() }
        } catch let error as POSIXError where error.code == .EWOULDBLOCK {
            notify(openDashboard)
        } catch {
            FenceApp.main()
        }
    }

    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AgentDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    private final class AgentDelegate: NSObject, NSApplicationDelegate {
        private var presence: ProcessLease?

        // Finder and the Dock deliver an explicit user reopen here when only the agent is running.
        func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
            if EnforcementService.hasOwner("dashboard.lock") {
                EnforcementService.notify(EnforcementService.openDashboard)
            } else {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = true
                NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
            }
            return false
        }

        func applicationDidFinishLaunching(_ notification: Notification) {
            do {
                presence = try EnforcementService.lease("agent.lock")
                AppModel.shared.startAgent()
                EnforcementService.notify(EnforcementService.agentReady)
            } catch {
                NSApp.terminate(nil)
            }
        }
    }
}
