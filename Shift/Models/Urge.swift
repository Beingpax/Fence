/// The reasons offered when Shift pauses a blocked visit.
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
