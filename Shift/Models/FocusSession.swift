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
///
/// The session tracks time twice: once against the wall clock, and once against the
/// monotonic uptime clock. Remaining time is the *longer* of the two, which means
/// winding the system clock forward can't end a session early. This is the practical
/// substitute for PRD §9's "block clock changes", which would need admin rights.
/// The cost is that time spent asleep doesn't burn session time, which is the
/// friendlier side to err on.
struct FocusSession: Equatable {
    let goal: String
    let startedAt: Date
    let duration: TimeInterval
    let strictness: Strictness
    /// Monotonic anchor, captured at creation. Unaffected by clock changes.
    let startedUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    var strikes: Int = 0
    /// Hosts or bundle IDs the user marked as "wrong call" during this session.
    var allowances: Set<String> = []

    var endsAt: Date { startedAt.addingTimeInterval(duration) }

    /// Wall-clock time left. Can be manipulated by changing the system clock.
    private func wallRemaining(at now: Date) -> TimeInterval {
        endsAt.timeIntervalSince(now)
    }

    /// Uptime-based time left. Immune to clock changes, pauses while the Mac sleeps.
    private var monotonicRemaining: TimeInterval {
        duration - (ProcessInfo.processInfo.systemUptime - startedUptime)
    }

    func remaining(at now: Date = .now) -> TimeInterval {
        max(0, max(wallRemaining(at: now), monotonicRemaining))
    }

    var isExpired: Bool { remaining() <= 0 }

    /// The deadline the watchdog should trust: whichever clock says "later".
    var hardenedDeadline: Date {
        Date().addingTimeInterval(remaining())
    }
}
