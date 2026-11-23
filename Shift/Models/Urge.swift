import Foundation
import Observation

/// What the person was really after when they reached for a blocked site.
///
/// The whole pause is built on one idea from habit research: a habit can't be deleted, only
/// replaced. The cue and the craving stay; what changes is the routine that answers them.
/// So the pause asks which craving this is, then offers a routine that actually meets it.
/// Naming the feeling also weakens it (affect labelling), and it turns an automatic reach
/// into a decision.
///
/// The options are written as the person would say them to a friend, not as categories.
enum UrgeReason: String, Codable, CaseIterable, Identifiable, Sendable {
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

    /// Short label for charts and the plan editor.
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

    /// The start of an if-then plan for this craving.
    var planLead: String {
        switch self {
        case .bored: "When I’m bored, I’ll"
        case .tired: "When I’m drained, I’ll"
        case .stuck: "When the work gets hard, I’ll"
        case .anxious: "When I’m anxious, I’ll"
        case .lonely: "When I feel alone, I’ll"
        case .needed: "When I really need it, I’ll"
        }
    }

    var planExample: String {
        switch self {
        case .bored: "walk to the window and back"
        case .tired: "close my eyes for two minutes"
        case .stuck: "write the next tiny step"
        case .anxious: "write down what’s on my mind"
        case .lonely: "message someone I like"
        case .needed: "say why, and take two minutes"
        }
    }
}

/// How one reach for a blocked site ended.
enum UrgeOutcome: String, Codable, Sendable {
    /// Closed it from the pause, without answering.
    case closed
    /// Switched away while the pause was up.
    case walkedAway
    case tookBreak
    case wroteStep
    case wroteItDown
    case reachedOut
    /// Took two minutes for a stated reason.
    case allowed
    /// The old full-screen block took over. Kept so logs written before the pause
    /// replaced it still decode.
    case shielded

    /// Everything except `allowed` and `shielded` is the person turning back on their own.
    var turnedBack: Bool {
        switch self {
        case .allowed, .shielded: false
        default: true
        }
    }
}

struct UrgeEvent: Codable, Identifiable, Sendable {
    var id = UUID()
    var date: Date
    var blockName: String
    /// The site or app, as shown to the person.
    var target: String
    var reason: UrgeReason?
    var outcome: UrgeOutcome
    /// The tiny step, the worry, or the stated need, when there was one.
    var note: String?
}

/// What the dashboard shows about the last seven days.
struct UrgeWeek: Sendable {
    var total: Int
    var turnedBack: Int
    var byReason: [(UrgeReason, Int)]
    var topReason: UrgeReason?
    /// The hour of day (0–23) with the most reaches, if there's a clear one.
    var peakHour: Int?
    var topTarget: String?
}

/// Every reach for a blocked site, and the if-then plans the person has written.
///
/// Kept on disk next to the blocks, for 60 days. Nothing leaves the Mac.
@MainActor
@Observable
final class UrgeLog {
    private(set) var events: [UrgeEvent] = []
    private(set) var plans: [UrgeReason: String] = [:]

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private struct Stored: Codable {
        var events: [UrgeEvent]
        var plans: [String: String]
    }

    private nonisolated static var fileURL: URL {
        GuardState.supportDirectory.appending(path: "urges.json", directoryHint: .notDirectory)
    }

    private static let retention: TimeInterval = 60 * 24 * 3600

    init() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return }
        let cutoff = Date().addingTimeInterval(-Self.retention)
        events = stored.events.filter { $0.date > cutoff }
        plans = Dictionary(uniqueKeysWithValues: stored.plans.compactMap { key, value in
            UrgeReason(rawValue: key).map { ($0, value) }
        })
    }

    func record(_ event: UrgeEvent) {
        events.append(event)
        scheduleSave()
    }

    func plan(for reason: UrgeReason) -> String? {
        guard let plan = plans[reason]?.trimmingCharacters(in: .whitespacesAndNewlines), !plan.isEmpty else { return nil }
        return plan
    }

    func setPlan(_ text: String, for reason: UrgeReason) {
        plans[reason] = text
        scheduleSave()
    }

    func week(now: Date = Date()) -> UrgeWeek {
        let start = now.addingTimeInterval(-7 * 24 * 3600)
        let recent = events.filter { $0.date > start }

        var reasonCounts: [UrgeReason: Int] = [:]
        var hourCounts: [Int: Int] = [:]
        var targetCounts: [String: Int] = [:]
        let calendar = Calendar.current
        for event in recent {
            if let reason = event.reason { reasonCounts[reason, default: 0] += 1 }
            hourCounts[calendar.component(.hour, from: event.date), default: 0] += 1
            targetCounts[event.target, default: 0] += 1
        }

        let byReason = UrgeReason.allCases.compactMap { reason in
            reasonCounts[reason].map { (reason, $0) }
        }.sorted { $0.1 > $1.1 }

        // Only call it a peak if it really stands out: at least three reaches, and more
        // than any other hour.
        let sortedHours = hourCounts.sorted { $0.value > $1.value }
        var peakHour: Int?
        if let top = sortedHours.first, top.value >= 3,
           sortedHours.count == 1 || sortedHours[1].value < top.value {
            peakHour = top.key
        }

        return UrgeWeek(
            total: recent.count,
            turnedBack: recent.filter(\.outcome.turnedBack).count,
            byReason: byReason,
            topReason: byReason.first?.0,
            peakHour: peakHour,
            topTarget: targetCounts.max { $0.value < $1.value }?.key
        )
    }

    private func scheduleSave() {
        let cutoff = Date().addingTimeInterval(-Self.retention)
        events.removeAll { $0.date < cutoff }
        let stored = Stored(events: events, plans: Dictionary(uniqueKeysWithValues: plans.map { ($0.key.rawValue, $0.value) }))
        saveTask?.cancel()
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(stored) else { return }
            try? FileManager.default.createDirectory(
                at: GuardState.supportDirectory, withIntermediateDirectories: true
            )
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
