import AppKit

/// Owns the bits of app lifecycle SwiftUI doesn't expose: refusing to quit during a
/// running or locked block, and running first-launch work once the app is really up.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.startDashboard(registerAgent: EnforcementService.registerIfNeeded)
        // A relaunch after an update stays in the menu bar; every other launch shows a window.
        if !CommandLine.arguments.contains(EnforcementService.relaunchedFlag) {
            AppModel.shared.openApp()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        AppModel.shared.openApp()
        return false
    }

    /// AppKit asks before ordinary quits. Force Quit skips this callback.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppModel.shared.shouldAllowTermination() ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.applicationWillTerminate()
    }

    /// The app has no windows most of the time; never let AppKit quit it for that reason.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
