import AppKit
import CoreGraphics

/// Closes what the person reached for, as gently as the target allows.
///
/// In a browser that means the one tab, not the browser: the pause is a nudge, not a
/// punishment, and the other tabs are probably work. Anything else is asked to quit.
@MainActor
enum TabCloser {
    enum CloseResult: Equatable {
        case posted, keyboardAccessUnavailable, targetUnavailable
    }

    /// Brings the browser back to the front, then sends it Command-W.
    ///
    /// Activation comes first because Close Tab is a menu command that acts on the key
    /// window, and the pause panel held keyboard focus until a moment ago. Posting to the
    /// process, rather than to the system, means the keystroke can only ever reach the
    /// browser.
    static func closeFrontTab(for context: ScreenContext, monitor: ContextMonitor) async -> CloseResult {
        let pid = context.processID
        guard let app = NSRunningApplication(processIdentifier: pid),
              !app.isTerminated, app.bundleIdentifier == context.bundleID else { return .targetUnavailable }
        // Shift is the active app while the pause is up, so it has to hand
        // activation over explicitly; macOS ignores a bare activate() from elsewhere.
        NSApp.yieldActivation(to: app)
        app.activate()

        // Focus and Accessibility can become ready at different points during a Space transition.
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(1200))
        repeat {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, monitor.isRunning, !app.isTerminated else { return .targetUnavailable }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { continue }
            guard let originalURL = context.url else { return closeIfFrontmost(pid: pid) }
            guard let live = await monitor.confirm(context, readWebsite: true) else { continue }
            guard live.url == originalURL else { return .targetUnavailable }
            if context.windowID != nil, live.windowID == nil { continue }
            guard live.windowID == context.windowID else { return .targetUnavailable }
            return closeIfFrontmost(pid: pid)
        } while ContinuousClock.now < deadline
        return .targetUnavailable
    }

    /// Used directly after confirming a URL. Never bring a background browser forward here.
    static func closeIfFrontmost(pid: pid_t) -> CloseResult {
        guard PermissionsManager.canPostKeyboardEvents else { return .keyboardAccessUnavailable }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return .targetUnavailable }

        let source = CGEventSource(stateID: .hidSystemState)
        let w: CGKeyCode = 0x0D
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: w, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: w, keyDown: false) else { return .targetUnavailable }
        for event in [down, up] {
            event.flags = .maskCommand
            event.postToPid(pid)
        }
        return .posted
    }

    static func quit(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }
}
