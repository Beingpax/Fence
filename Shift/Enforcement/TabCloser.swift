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
    static func closeFrontTab(for context: ScreenContext, monitor: ContextMonitor) async {
        let pid = context.processID
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
        // Shift is the active app while the pause is up, so it has to hand
        // activation over explicitly; macOS ignores a bare activate() from elsewhere.
        NSApp.yieldActivation(to: app)
        app.activate()
        try? await Task.sleep(for: .milliseconds(180))
        // The person may have switched tabs or windows while the pause had focus.
        if let originalURL = context.url {
            guard let live = await monitor.confirm(context, readWebsite: true),
                  live.windowID == context.windowID, live.url == originalURL else { return }
        }
        _ = closeIfFrontmost(pid: pid)
    }

    /// Used directly after confirming a URL. Never bring a background browser forward here.
    static func closeIfFrontmost(pid: pid_t) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }

        let source = CGEventSource(stateID: .hidSystemState)
        let w: CGKeyCode = 0x0D
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: w, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: w, keyDown: false) else { return false }
        for event in [down, up] {
            event.flags = .maskCommand
            event.postToPid(pid)
        }
        return true
    }

    static func quit(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }
}
