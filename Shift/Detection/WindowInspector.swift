import ApplicationServices
import Foundation

/// Reads the focused window's title through the Accessibility API.
///
/// Deliberately `nonisolated`: these are synchronous cross-process calls that can block,
/// so callers run them off the main actor. The messaging timeout is the important part.
/// Without it, one unresponsive app freezes whatever thread asked.
enum WindowInspector {
    /// Longest we'll wait on another process to answer. Detection is best-effort; a
    /// hung app should cost us a sample, not a thread.
    private static let messagingTimeout: Float = 0.5

    /// Off-main wrapper. The synchronous call below can block for the length of the
    /// messaging timeout, which is far too long to spend on the main actor.
    static func focusedWindowTitle(pid: pid_t) async -> String? {
        await Task.detached(priority: .userInitiated) { focusedWindowTitle(pid: pid) }.value
    }

    static func focusedWindowTitle(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)

        var windowRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
            let windowRef,
            CFGetTypeID(windowRef) == AXUIElementGetTypeID()
        else { return nil }

        let window = windowRef as! AXUIElement
        AXUIElementSetMessagingTimeout(window, messagingTimeout)

        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success else {
            return nil
        }
        let title = titleRef as? String
        return (title?.isEmpty ?? true) ? nil : title
    }
}
