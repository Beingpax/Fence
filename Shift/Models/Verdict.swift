import Foundation

/// The decision about one `ScreenContext`, and which block made it.
struct Verdict: Equatable, Sendable {
    enum Kind: String, Sendable {
        case allow, nudge, block
    }

    enum Source: String, Sendable {
        case rules = "Rules"
        case accessibility = "Accessibility text"
        case screenOCR = "Screen text (OCR)"
    }

    var kind: Kind
    /// One human-readable line. Shown on the shield and in "What Shift sees".
    var reason: String
    /// 0...1. The shield only appears for confident blocks.
    var confidence: Double = 1
    /// The block responsible, when there is one.
    var blockID: UUID?
    var blockName: String?
    /// The matching rule, when a website, path, or app explicitly triggered this verdict.
    var ruleTarget: StrikeTarget?
    /// The block's intent sentence, shown on the shield when it has one.
    var goal: String = ""
    var source: Source = .rules

    static func allow(_ reason: String = "On task") -> Verdict {
        Verdict(kind: .allow, reason: reason)
    }

    static func nudge(_ reason: String, confidence: Double = 0.6) -> Verdict {
        Verdict(kind: .nudge, reason: reason, confidence: confidence)
    }

    static func block(_ reason: String, confidence: Double = 0.95) -> Verdict {
        Verdict(kind: .block, reason: reason, confidence: confidence)
    }
}
