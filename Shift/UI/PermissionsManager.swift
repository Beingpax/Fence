import AppKit
import ApplicationServices
import CoreGraphics
import os.log

/// Live reads of the permissions Shift depends on, plus deep links to the right
/// System Settings pane.
///
/// Everything here asks the system every time. Nothing is cached, because the user can
/// change these in System Settings while Shift is running, and a stale "not granted"
/// is the most confusing state this app can be in.
enum PermissionsManager {
    private static let log = Logger(subsystem: "com.beingpax.Shift", category: "Permissions")

    // MARK: Accessibility

    /// Window titles, the frontmost app, and shortcut suppression during the pause.
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that deep-links to Privacy & Security → Accessibility.
    static func requestAccessibility() {
        // The constant is a mutable C global, which isn't concurrency-safe to touch.
        // Its value is a documented, stable key, so use the string directly.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Optional permission for reading the foreground window with OCR.
    // MARK: Settings deep links

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }


    // MARK: Diagnostics

    /// Written once at launch. If a permission looks granted in System Settings but Shift
    /// disagrees, this line and the code signature below it are where to start.
    static func logDiagnostics() {
        let bundlePath = Bundle.main.bundleURL.path
        log.notice("""
        Permission state at launch:
        accessibility=\(isAccessibilityTrusted, privacy: .public) \
        bundle=\(bundlePath, privacy: .public)
        """)
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
