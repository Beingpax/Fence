import Foundation

/// How hard Shift makes it to escape a block. See PRD §9.
enum Strictness: String, CaseIterable, Identifiable, Codable {
    case gentle, firm, locked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gentle: "Gentle"
        case .firm: "Firm"
        case .locked: "Locked"
        }
    }

    var summary: String {
        switch self {
        case .gentle: "Shield appears, you can leave right away."
        case .firm: "Friction grows with every strike."
        case .locked: "Can't end early or quit Shift. Cold Turkey mode."
        }
    }

    var symbol: String {
        switch self {
        case .gentle: "leaf"
        case .firm: "hand.raised"
        case .locked: "lock.fill"
        }
    }
}

/// A single focus session. Everything Shift decides is relative to `goal`.
struct FocusSession: Equatable {
    let goal: String
    let startedAt: Date
    let duration: TimeInterval
    let strictness: Strictness
    var strikes: Int = 0
    /// Hosts or bundle IDs the user marked as "wrong call" during this session.
    var allowances: Set<String> = []

    var endsAt: Date { startedAt.addingTimeInterval(duration) }

    func remaining(at now: Date = .now) -> TimeInterval {
        max(0, endsAt.timeIntervalSince(now))
    }

    var isExpired: Bool { remaining() <= 0 }
}
