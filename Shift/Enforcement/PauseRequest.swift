import Foundation

/// What the pause needs to know about one reach for a blocked site.
struct PauseRequest {
    var blockName: String
    var blockID: UUID?
    /// The rule that matched, so "I need it" can let exactly this site through.
    var ruleTarget: RuleTarget?
    /// The site or app, as the person would name it: "instagram.com", "Steam".
    var target: String
    var appName: String
    var isBrowser: Bool
    /// Which reach this is within the hour: 1, 2, 3 or more.
    var visit: Int
    /// Breaks left today on this block, or `nil` when the block has breaks switched off.
    /// "I need it" spends one of these, so it only appears when the block allows breaks.
    var breaksLeft: Int?
    /// The headline and line under it, dealt from `PauseCopy` for this visit.
    var title: String
    var subtitle: String
    var isPreview = false

    /// The rule as it appears on screen, including any path that narrows a website block.
    var blockedTarget: String {
        switch ruleTarget {
        case .website(let entry), .path(let entry):
            WebsiteAddress(entry: entry)?.entry ?? entry
        case .app:
            appName
        case nil:
            target
        }
    }

    /// How long the choices stay out of reach. Two slow breaths the first time, four the
    /// second, six from the third on: each repeat costs more, so coming back is never free.
    /// Closing it never waits.
    var waitSeconds: Int {
        switch visit {
        case ...1: 10
        case 2: 20
        default: 30
        }
    }

    /// Closing the tab is the whole point in a browser; the other tabs are probably work.
    var closeTitle: String {
        if isPreview { return "Dismiss preview" }
        return isBrowser ? "Close the tab" : "Quit \(appName)"
    }
}

/// What the person chose in the pause.
enum PauseEvent {
    /// Close it, with the craving they named, if they named one.
    case close(UrgeReason?)
    /// "I need it": the wait has ended and access can start.
    case takeBreak(minutes: Int, note: String)
}
