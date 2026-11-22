import CoreGraphics
import Foundation

/// A snapshot of what the user is looking at right now (Tier 0 signals, PRD §8).
struct ScreenContext: Equatable, Sendable {
    var bundleID: String
    var appName: String
    var processID: pid_t
    var windowTitle: String?
    var url: URL?
    var windowID: CGWindowID?
    /// Advances when focus or a mouse interaction may have changed visible content.
    var revision: UInt64

    var websiteAddress: WebsiteAddress? { url.flatMap(WebsiteAddress.init(url:)) }
    var host: String? { websiteAddress?.host }

    var isBrowser: Bool { Browser(bundleID: bundleID) != nil }

    /// Stable identity used by hysteresis: the same signature twice in a row means "consistent reading".
    var signature: String {
        "\(bundleID)|\(processID)|\(windowID ?? 0)|\(url?.absoluteString ?? "")|\(windowTitle ?? "")"
    }

    /// What we show in the UI as "where you are".
    var displayLocation: String {
        host ?? windowTitle ?? appName
    }
}
