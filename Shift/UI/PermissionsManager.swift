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

    /// Window titles, the frontmost app, and shortcut suppression during the shield.
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that deep-links to Privacy & Security → Accessibility.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: Screen Recording

    /// Needed only by the on-screen text reader (tier 1b). Checked without prompting.
    static var isScreenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Triggers the one-time system prompt. Returns the result of the preflight after it.
    @discardableResult
    static func requestScreenRecording() -> Bool { CGRequestScreenCaptureAccess() }

    // MARK: Settings deep links

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openAutomationSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    // MARK: Diagnostics

    /// Written once at launch. If a permission looks granted in System Settings but Shift
    /// disagrees, this line and the code signature below it are where to start.
    static func logDiagnostics() {
        let bundlePath = Bundle.main.bundleURL.path
        log.notice("""
        Permission state at launch:
        accessibility=\(isAccessibilityTrusted, privacy: .public) \
        screenRecording=\(isScreenRecordingGranted, privacy: .public) \
        bundle=\(bundlePath, privacy: .public)
        """)
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
