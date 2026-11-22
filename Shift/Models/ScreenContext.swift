import Foundation

/// A snapshot of what the user is looking at right now (Tier 0 signals, PRD §8).
struct ScreenContext: Equatable {
    var bundleID: String
    var appName: String
    var processID: pid_t
    var windowTitle: String?
    var url: URL?
    /// Filled by the OCR tier (P1). Always nil in the skeleton.
    var screenText: String?

    /// Lowercased host without a leading "www.".
    var host: String? {
        guard let host = url?.host()?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// "youtube.com/shorts/abc", used for path-aware rules.
    var hostAndPath: String? {
        guard let host else { return nil }
        return host + (url?.path() ?? "")
    }

    var isBrowser: Bool { Browser(bundleID: bundleID) != nil }

    /// Stable identity used by hysteresis: the same signature twice in a row means "consistent reading".
    var signature: String {
        "\(bundleID)|\(hostAndPath ?? "")|\(windowTitle ?? "")"
    }

    /// What we show in the UI as "where you are".
    var displayLocation: String {
        host ?? windowTitle ?? appName
    }
}
