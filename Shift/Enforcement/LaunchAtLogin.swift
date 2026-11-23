import os.log
import ServiceManagement

/// "Open at Login", through the modern `SMAppService` API.
///
/// Registering the main app is enough for a menu bar app: launchd relaunches Shift at
/// login without a separate helper bundle. The user can also revoke it in
/// System Settings → General → Login Items, so `isEnabled` always asks the system
/// rather than trusting a stored preference.
enum LaunchAtLogin {
    private static let log = Logger(subsystem: "com.beingpax.Shift", category: "LaunchAtLogin")

    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    /// True when the user switched it off in System Settings behind our back.
    static var requiresApproval: Bool { status == .requiresApproval }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                guard !isEnabled else { return true }
                try SMAppService.mainApp.register()
            } else {
                guard isEnabled || requiresApproval else { return true }
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            log.error("Could not \(enabled ? "register" : "unregister") the login item: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
