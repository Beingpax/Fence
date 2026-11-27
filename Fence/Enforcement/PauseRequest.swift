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
    /// The headline and line under it, dealt from `PauseCopy` for this visit.
    var title: String
    var subtitle: String
    var isPreview = false
    /// The row in `ReachJournal` this pause writes to.
    var journalID = UUID()

    /// The rule as it appears on screen, including any path that narrows a website block.
    var blockedTarget: String {
        ruleTarget?.displayName(appName: appName) ?? target
    }

    /// The breath before the question: one full breath of the constellation (in over 3 s,
    /// out over 2 s). The same every time; the escalating 10, 20 and 30 seconds were removed
    /// on 26 Nov 2026 along with the rest of the ladder.
    var waitSeconds: Int { 5 }

    /// Whether turning back closes one tab rather than quitting. Only when a website rule
    /// matched in a browser: a block that lists the browser app itself (Arc, say) quits it,
    /// like any other app.
    var closesTab: Bool {
        guard isBrowser else { return false }
        if case .app = ruleTarget { return false }
        return true
    }

    /// Closing the tab is the whole point in a browser; the other tabs are probably work.
    var closeTitle: String {
        if isPreview { return "Dismiss preview" }
        return closesTab ? "Close the tab" : "Quit \(appName)"
    }
}

/// What the person chose in the pause.
enum PauseEvent {
    /// Close it, with the feeling they named and what they wrote about it, if they named one.
    /// Closing before naming a feeling carries neither.
    case close(UrgeReason?, reflection: String?)
    /// "I need it": the wait has ended and access can start. `note` is what they wrote.
    case takeBreak(minutes: Int, note: String)
}

extension RuleTarget {
    /// The rule as the person would read it: "youtube.com/shorts", or the app's name.
    func displayName(appName: String) -> String {
        switch self {
        case .website(let entry), .path(let entry):
            WebsiteAddress(entry: entry)?.entry ?? entry
        case .app:
            appName
        }
    }
}
