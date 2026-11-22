import ApplicationServices

/// Reads the focused window's title through the Accessibility API.
enum WindowInspector {
    static func focusedWindowTitle(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let app = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
            let windowRef,
            CFGetTypeID(windowRef) == AXUIElementGetTypeID()
        else { return nil }

        let window = windowRef as! AXUIElement
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success else {
            return nil
        }
        let title = titleRef as? String
        return (title?.isEmpty ?? true) ? nil : title
    }
}
