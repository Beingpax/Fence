/// Browser identities used during window inspection.
enum Browser: String, CaseIterable, Sendable {
    case safari, chrome, arc, brave, edge, firefox

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
        case .firefox: "org.mozilla.firefox"
        }
    }

    var displayName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .arc: "Arc"
        case .brave: "Brave"
        case .edge: "Edge"
        case .firefox: "Firefox"
        }
    }

    var isChromium: Bool {
        switch self {
        case .chrome, .arc, .brave, .edge: true
        case .safari, .firefox: false
        }
    }
}
