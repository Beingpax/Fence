import AppKit

/// Owns the bits of app lifecycle SwiftUI doesn't expose: refusing to quit during a
/// Locked session, and running first-launch work once the app is really up.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.applicationDidFinishLaunching()
    }

    /// PRD §9: a Locked session can't be ended, and Shift can't be quit, until it runs out.
    /// This catches every polite route out, including Cmd+Q, the Quit menu item, AppleScript
    /// `quit`, Activity Monitor's "Quit", and a `SIGTERM` from `kill`.
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
