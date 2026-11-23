import AppKit
import ServiceManagement

/// A bundled, user-approved login agent runs the same rule engine and pause UI
/// independently of the dashboard. The main app can still enforce locally while
/// macOS is waiting for approval.
@MainActor
enum EnforcementService {
    static let agentFlag = "--enforcement-agent"
    static let isAgent = CommandLine.arguments.contains(agentFlag)
    static let service = SMAppService.agent(plistName: "com.beingpax.Shift.enforcement.plist")
    private static let notificationPrefix = Bundle.main.bundleIdentifier ?? "com.beingpax.Shift"
    static let rulesChanged = Notification.Name("\(notificationPrefix).rulesChanged")
    static let openDashboard = Notification.Name("\(notificationPrefix).openDashboard")
    static let agentReady = Notification.Name("\(notificationPrefix).enforcementReady")

    @discardableResult
    static func registerIfNeeded(enabled: Bool) throws -> Bool {
        switch (enabled, service.status) {
        case (true, .notRegistered): try service.register()
        case (false, .enabled), (false, .requiresApproval): try service.unregister()
        default: break
        }
        return service.status == .enabled
    }

    static func lease(_ name: String) throws -> ProcessLease {
        let directory = ShiftInstallation.supportDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try ProcessLease(url: directory.appending(path: name))
    }

    static func hasOwner(_ name: String) -> Bool {
        do {
            let probe = try lease(name)
            probe.release()
            return false
        } catch let error as POSIXError {
            return error.code == .EWOULDBLOCK
        } catch { return false }
    }

    static func notify(_ name: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    }

    static func runDashboard() {
        do {
            let presence = try lease("dashboard.lock")
            withExtendedLifetime(presence) { ShiftApp.main() }
        } catch let error as POSIXError where error.code == .EWOULDBLOCK {
            notify(openDashboard)
        } catch {
            ShiftApp.main()
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
                if WatchdogService.hasConfiguration { WatchdogService.remove() }
                EnforcementService.notify(EnforcementService.agentReady)
            } catch {
                NSApp.terminate(nil)
            }
        }
    }
}
