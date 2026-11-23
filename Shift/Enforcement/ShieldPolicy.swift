import Foundation

/// How the shield behaves on the third reach for a blocked site within an hour.
///
/// There are no escalation tiers. Friction used to grow with the day's repeat count, which
/// meant the first slip was free and the fourth was punitive for no reason the user could
/// see. The ladder is the escalation now, and it runs identically every time: three nudges,
/// then this. So the shield is one fixed, serious thing — a wait, and a sentence you have
/// to mean.
enum ShieldPolicy {
    /// How long the shield's actions stay disabled. Long enough to be a decision.
    static let countdownSeconds = 10

    /// How much you have to write before the shield will let you act.
    ///
    /// This replaced copying out a fixed sentence. Transcribing "I am choosing to get
    /// distracted" is friction you can perform without reading it — by the third time it
    /// is muscle memory. Writing your own sentences about what you were doing and what
    /// pulled you away cannot be performed absently, and it leaves you with the answer.
    static let minimumWords = 20

    /// Counts words the way a person would: runs of non-whitespace.
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

/// Everything the shield needs to render and act.
struct ShieldRequest: Equatable {
    var appName: String
    var bundleID: String
    var processID: pid_t
    var host: String?
    var reason: String
    /// The block responsible, shown so the user knows which rule they set is biting.
    var blockName: String
    var blockID: UUID?
    /// Length of the break available from this shield.
    var breakMinutes: Int?
    /// Demo shields from the menu bar don't touch any real app.
    var isPreview: Bool = false

    var primaryActionTitle: String {
        "Quit \(appName)"
    }
}

enum ShieldResolution: Equatable {
    case quitApp
    case takeBreak
}
