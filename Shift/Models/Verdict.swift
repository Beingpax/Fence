import Foundation

/// The classifier's decision about one `ScreenContext`.
struct Verdict: Equatable {
    enum Kind: String {
        case allow, nudge, block
    }

    var kind: Kind
    /// One human-readable line. Shown on the shield and in "What Shift sees".
    var reason: String
    /// 0...1. The shield only appears for confident blocks.
    var confidence: Double

    static func allow(_ reason: String = "On task") -> Verdict {
        Verdict(kind: .allow, reason: reason, confidence: 1)
    }

    static func nudge(_ reason: String, confidence: Double = 0.6) -> Verdict {
        Verdict(kind: .nudge, reason: reason, confidence: confidence)
    }

    static func block(_ reason: String, confidence: Double = 0.95) -> Verdict {
        Verdict(kind: .block, reason: reason, confidence: confidence)
    }
}
