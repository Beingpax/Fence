import AppKit
import CoreGraphics

/// Closes what the person reached for, as gently as the target allows.
///
/// In a browser that means the one tab, not the browser: the pause is a nudge, not a
/// punishment, and the other tabs are probably work. Anything else is asked to quit.
@MainActor
enum TabCloser {
    /// Brings the browser back to the front, then sends it Command-W.
    ///
    /// Activation comes first because Close Tab is a menu command that acts on the key
    /// window, and the pause panel held keyboard focus until a moment ago. Posting to the
    /// process, rather than to the system, means the keystroke can only ever reach the
    /// browser. Needs the Accessibility permission, which Shift already holds.
    static func closeFrontTab(pid: pid_t) async {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
        app.activate()
        try? await Task.sleep(for: .milliseconds(180))
        guard !app.isTerminated, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }

        let source = CGEventSource(stateID: .hidSystemState)
        let w: CGKeyCode = 0x0D
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: w, keyDown: keyDown) else { continue }
            event.flags = .maskCommand
            event.postToPid(pid)
        }
    }

    static func quit(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }
}
