/// The reasons offered when Fence pauses a blocked visit.
///
/// Five feelings and "I need it", which is last and always shown. The user keeps it to
/// these six: no extra options or categories. Raw values are
/// stored in the journal: never rename one.
enum UrgeReason: String, CaseIterable, Identifiable, Sendable {
    case bored, tired, stuck, anxious, lonely, needed

    var id: String { rawValue }

    /// The button, in the first person.
    var title: String {
        switch self {
        case .bored: "I’m bored"
        case .tired: "I’m drained"
        case .stuck: "This is hard"
        case .anxious: "I’m anxious"
        case .lonely: "I feel alone"
        case .needed: "I need it"
        }
    }

    /// The line under the button: the feeling, so it's recognisable at a glance.
    var feeling: String {
        switch self {
        case .bored: "I want something to happen"
        case .tired: "My brain needs a rest"
        case .stuck: "I hit a wall and wanted out"
        case .anxious: "Something’s weighing on me"
        case .lonely: "I want to feel connected"
        case .needed: "For something specific"
        }
    }

    /// How many words the written reason needs before anything moves on. Only "I need it"
    /// asks for any: friction belongs on the way in, never the way back. Closing the tab is
    /// the behaviour Fence wants, so after naming a feeling it's one click, and writing is
    /// optional (26 Nov 2026, the user's call; feelings needed 10 words before that).
    var minimumWords: Int { self == .needed ? 20 : 0 }

    /// Whether this answer has to be written about before it moves on.
    var requiresWriting: Bool { minimumWords > 0 }

    /// Asked above the written reason once this is picked: what, why or how, so the journal
    /// holds what actually set the pull off rather than the label again.
    var prompt: String {
        switch self {
        case .bored: "What were you doing, and why did it feel dull?"
        case .tired: "What wore you out, and what’s next on your list?"
        case .stuck: "What are you working on, and where exactly is it hard?"
        case .anxious: "What’s on your mind, and why now?"
        case .lonely: "Who or what were you hoping to find here?"
        case .needed: "What exactly do you need there, why can’t it wait, and how long will it take?"
        }
    }

    var symbol: String {
        switch self {
        case .bored: "hourglass"
        case .tired: "moon.zzz"
        case .stuck: "puzzlepiece"
        case .anxious: "cloud.rain"
        case .lonely: "person"
        case .needed: "arrow.up.forward"
        }
    }

    /// Short label for recent activity.
    var shortLabel: String {
        switch self {
        case .bored: "Bored"
        case .tired: "Drained"
        case .stuck: "Stuck"
        case .anxious: "Anxious"
        case .lonely: "Lonely"
        case .needed: "Needed it"
        }
    }
}
