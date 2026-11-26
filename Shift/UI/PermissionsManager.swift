import AppKit
import ApplicationServices
import CoreGraphics
import os.log

/// Browsing access is shown in different System Settings panes across macOS versions.
enum PermissionsManager {
    enum BrowserAccessPane: String {
        case accessibility = "Accessibility"
        case deviceControl = "Device Control and Data Access"
        case appProtectionOverride = "System & App Protection Override"

        static var current: Self {
            if #available(macOS 27.3, *) { return .appProtectionOverride }
            if #available(macOS 27, *) { return .deviceControl }
            return .accessibility
        }

        var settingsPath: String { "Privacy & Security → \(rawValue)" }

        var setupInstructions: String {
            switch self {
            case .accessibility, .deviceControl:
                "Turn on Shift in \(settingsPath)."
            case .appProtectionOverride:
                "Go to \(settingsPath) and add Shift with +. If macOS offers Choose Apps, select the browsers you want Shift to block."
            }
        }
    }

    private static let log = Logger(subsystem: "com.beingpax.Shift", category: "Permissions")

    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }
    /// Posting events is granted by the same Accessibility list (macOS 27 calls the pane
    /// Device Control and Data Access). `CGPreflightPostEventAccess` can keep answering
    /// false until the process relaunches, which left the row stuck after the user had
    /// already switched Shift on, so a trusted process counts as able to post.
    static var canPostKeyboardEvents: Bool { CGPreflightPostEventAccess() || isAccessibilityTrusted }

    /// Scoped app grants on 27.3 are checked by macOS when we query the target app.
    /// Process-wide trust alone cannot tell us whether a specific browser is available.
    static var canInspectApp: Bool {
        BrowserAccessPane.current == .appProtectionOverride || isAccessibilityTrusted
    }

    static func requestBrowserAccess() {
        let pane = BrowserAccessPane.current
        if pane != .appProtectionOverride {
            if !isAccessibilityTrusted {
                requestAccessibility()
            } else if !canPostKeyboardEvents {
                _ = CGRequestPostEventAccess()
            }
        }

        // The legacy anchor can open the assistive-technology pane after the split.
        let settings = pane == .appProtectionOverride
            ? "com.apple.settings.PrivacySecurity.extension"
            : "com.apple.preference.security?Privacy_Accessibility"
        guard let url = URL(string: "x-apple.systempreferences:\(settings)") else { return }
        NSWorkspace.shared.open(url)
    }

    static func requestAccessibility() {
        // The constant is a mutable C global, which isn't concurrency-safe to touch.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func logDiagnostics() {
        let bundlePath = Bundle.main.bundleURL.path
        log.notice("""
        Permission state at launch:
        accessibility=\(isAccessibilityTrusted, privacy: .public) \
        postKeyboardEvents=\(canPostKeyboardEvents, privacy: .public) \
        bundle=\(bundlePath, privacy: .public)
        """)
    }
}
