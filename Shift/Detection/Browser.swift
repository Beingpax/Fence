import Foundation

/// Browsers Shift can read URLs from and close tabs in, via Apple Events.
/// P1 replaces this with a browser extension for exact, instant URLs (PRD §17 Q3).
enum Browser: CaseIterable {
    case safari, chrome, arc, brave, edge

    init?(bundleID: String) {
        guard let match = Self.allCases.first(where: { $0.bundleID == bundleID }) else { return nil }
        self = match
    }

    var bundleID: String {
        switch self {
        case .safari: "com.apple.Safari"
        case .chrome: "com.google.Chrome"
        case .arc: "company.thebrowser.Browser"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        }
    }

    private var urlScript: String {
        switch self {
        case .safari:
            "tell application id \"\(bundleID)\" to return URL of current tab of front window"
        default:
            "tell application id \"\(bundleID)\" to return URL of active tab of front window"
        }
    }

    private var closeTabScript: String {
        switch self {
        case .safari:
            "tell application id \"\(bundleID)\" to close current tab of front window"
        default:
            "tell application id \"\(bundleID)\" to close active tab of front window"
        }
    }

    /// The front tab's URL. Triggers the macOS Automation prompt the first time per browser.
    func currentURL() -> URL? {
        guard let string = AppleScriptRunner.run(urlScript), !string.isEmpty else { return nil }
        return URL(string: string)
    }

    func closeFrontTab() {
        AppleScriptRunner.run(closeTabScript)
    }
}

enum AppleScriptRunner {
    @discardableResult
    static func run(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result.stringValue
    }
}
