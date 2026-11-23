import Foundation

/// What, exactly, matched. Identifies one encounter so the nudge ladder can tell
/// "still on the same thing" from "moved somewhere else that is also blocked".
enum RuleTarget: Sendable, Equatable {
    case website(String)
    case path(String)
    case app(String)

    var identifier: String {
        switch self {
        case .website(let host): "website:\(host)"
        case .path(let path): "path:\(path)"
        case .app(let bundleID): "app:\(bundleID)"
        }
    }
}

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
    /// One human-readable line. Shown in "What Shift sees" and the activity log.
    var reason: String
    /// The block responsible, when there is one.
    var blockID: UUID?
    var blockName: String?
    /// The matching rule, when a website, path, or app explicitly triggered this verdict.
    var ruleTarget: RuleTarget?
    var source: Source = .rules

    static func allow(_ reason: String = "On task") -> Verdict {
        Verdict(kind: .allow, reason: reason)
    }

    static func nudge(_ reason: String) -> Verdict {
        Verdict(kind: .nudge, reason: reason)
    }
}
