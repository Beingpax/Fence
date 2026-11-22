import Foundation

/// A named, independently configured block. This is the unit the whole app is built on,
/// in the spirit of Cold Turkey: you create blocks, each carries its own list, schedule
/// and lock, and you switch them on and off one at a time.
///
/// A block is not a timer. A timer is just one of the schedules a block can have.
struct Block: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var symbol: String = "shield.lefthalf.filled"
    var tint: BlockTint = .indigo

    /// The switch on the block's row. Honoured only when the block isn't locked on.
    var isEnabled: Bool = false

    var list: BlockList = BlockList()
    var schedule: BlockSchedule = .always
    var lock: BlockLock = BlockLock()
    var breaks: BreakPlan = BreakPlan()

    /// How hard the shield pushes back. Separate from locking: friction is about the
    /// moment you hit a block, the lock is about whether you can switch it off at all.
    var friction: Friction = .firm

    /// Optional intent sentence. When set, Shift can judge ambiguous pages against it
    /// rather than only matching the list.
    var goal: String = ""

    /// When a `.manual` block is running, the instant it stops. Runtime state, persisted
    /// so a relaunch mid-run doesn't hand out a free pass.
    var manualRunEndsAt: Date?

    var stats: BlockStats = BlockStats()
    var createdAt: Date = Date()

    // MARK: Activity

    /// Is this block policing the screen right now?
    func isActive(at date: Date = Date()) -> Bool {
        guard isEnabled || lock.isLocked(at: date) else { return false }
        guard !breaks.isOnBreak(at: date) else { return false }

        switch schedule {
        case .always:
            return true
        case .scheduled(let windows):
            return windows.contains { $0.contains(date) }
        case .manual:
            guard let manualRunEndsAt else { return false }
            return date < manualRunEndsAt
        }
    }

    /// One line describing when it applies, for the block row.
    var scheduleSummary: String {
        switch schedule {
        case .always:
            return "Blocked at all times"
        case .scheduled(let windows):
            if windows.isEmpty { return "No times set" }
            if windows.count == 1 { return windows[0].summary }
            return "\(windows.count) time windows"
        case .manual(let minutes):
            if let manualRunEndsAt, manualRunEndsAt > Date() {
                return "Running until \(manualRunEndsAt.formatted(date: .omitted, time: .shortened))"
            }
            return minutes.map { "Start on demand · \($0) min" } ?? "Start on demand"
        }
    }

    /// What the block covers, for the block row.
    var contentsSummary: String {
        var parts: [String] = []
        let sites = list.hosts.count + list.paths.count
        if sites > 0 { parts.append("\(sites) site\(sites == 1 ? "" : "s")") }
        if !list.apps.isEmpty { parts.append("\(list.apps.count) app\(list.apps.count == 1 ? "" : "s")") }
        if !list.keywords.isEmpty { parts.append("\(list.keywords.count) keyword\(list.keywords.count == 1 ? "" : "s")") }
        if parts.isEmpty { return list.mode == .allowlist ? "Everything except exceptions" : "Nothing yet" }
        return parts.joined(separator: " · ")
    }
}

// MARK: - What a block covers

struct BlockList: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        /// Block what's listed, allow everything else.
        case blocklist
        /// Allow only what's listed, block everything else. Cold Turkey calls this
        /// "allowance only"; it's the nuclear option for writing days.
        case allowlist

        var id: String { rawValue }
        var title: String { self == .blocklist ? "Block these" : "Allow only these" }
    }

    var mode: Mode = .blocklist
    /// Whole sites, subdomains included.
    var hosts: [String] = []
    /// Parts of sites, e.g. "youtube.com/shorts".
    var paths: [String] = []
    /// Native apps by bundle identifier.
    var apps: [String] = []
    /// Words that trigger on *on-screen text*, read via Screen Recording. This is the
    /// one rule that can see inside a page the address doesn't describe.
    var keywords: [String] = []
    /// Always allowed, even when something else here matches.
    var exceptions: [String] = []

    var isEmpty: Bool {
        hosts.isEmpty && paths.isEmpty && apps.isEmpty && keywords.isEmpty
    }
}

// MARK: - When a block applies

enum BlockSchedule: Codable, Equatable {
    /// Always on while enabled. The global block.
    case always
    /// Recurring weekly windows.
    case scheduled([ScheduleWindow])
    /// Started by hand, optionally for a fixed number of minutes.
    case manual(minutes: Int?)

    var kindTitle: String {
        switch self {
        case .always: "All the time"
        case .scheduled: "On a schedule"
        case .manual: "Start on demand"
        }
    }
}

/// Minutes since midnight, so a window is comparable without timezone surprises.
struct TimeOfDay: Codable, Equatable, Comparable, Hashable {
    var minutes: Int

    init(minutes: Int) { self.minutes = max(0, min(24 * 60, minutes)) }
    init(hour: Int, minute: Int) { self.init(minutes: hour * 60 + minute) }

    var hour: Int { minutes / 60 }
    var minute: Int { minutes % 60 }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool { lhs.minutes < rhs.minutes }

    var formatted: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

enum Weekday: Int, Codable, CaseIterable, Identifiable, Hashable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    var shortTitle: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }

    var letter: String { String(shortTitle.prefix(1)) }

    static let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
}

struct ScheduleWindow: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var days: Set<Weekday> = Weekday.weekdays
    var start = TimeOfDay(hour: 9, minute: 0)
    var end = TimeOfDay(hour: 17, minute: 0)

    /// Handles windows that run past midnight, where end is "earlier" than start.
    func contains(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard
            let weekdayValue = components.weekday,
            let weekday = Weekday(rawValue: weekdayValue),
            let hour = components.hour,
            let minute = components.minute
        else { return false }

        let now = TimeOfDay(hour: hour, minute: minute)

        if start <= end {
            return days.contains(weekday) && now >= start && now < end
        }

        // Overnight window: 22:00 to 06:00 belongs to the day it started on.
        if days.contains(weekday) && now >= start { return true }
        let previous = Weekday(rawValue: weekdayValue == 1 ? 7 : weekdayValue - 1)
        if let previous, days.contains(previous), now < end { return true }
        return false
    }

    var summary: String {
        let dayPart: String
        if days == Weekday.weekdays {
            dayPart = "Weekdays"
        } else if days.count == Weekday.allCases.count {
            dayPart = "Every day"
        } else {
            dayPart = Weekday.allCases.filter(days.contains).map(\.shortTitle).joined(separator: " ")
        }
        return "\(dayPart) · \(start.formatted) to \(end.formatted)"
    }
}

// MARK: - Breaks

/// Cold Turkey's "breaks": a block can let you off the hook briefly, on your terms,
/// set in advance rather than in the moment of weakness.
struct BreakPlan: Codable, Equatable {
    var isEnabled: Bool = false
    /// Length of each break.
    var minutes: Int = 5
    /// How many breaks are allowed per active stretch.
    var allowance: Int = 2

    /// Runtime: when the current break ends.
    var currentBreakEndsAt: Date?
    var breaksTakenToday: Int = 0
    var lastResetDay: Date?

    func isOnBreak(at date: Date = Date()) -> Bool {
        guard isEnabled, let currentBreakEndsAt else { return false }
        return date < currentBreakEndsAt
    }

    var remainingToday: Int { max(0, allowance - breaksTakenToday) }
}

// MARK: - Locking

enum LockMethod: String, Codable, CaseIterable, Identifiable {
    case none
    case duration
    case untilTime
    case randomString
    case restart

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "No lock"
        case .duration: "Locked for a while"
        case .untilTime: "Locked until a time"
        case .randomString: "Type a random string"
        case .restart: "Locked until restart"
        }
    }

    var detail: String {
        switch self {
        case .none: "You can switch this block off whenever you like."
        case .duration: "Once on, it stays on for the length you choose."
        case .untilTime: "Once on, it stays on until a time you choose today."
        case .randomString: "You can switch it off, but only after typing a random string."
        case .restart: "Only a restart of this Mac will switch it off."
        }
    }

    var symbol: String {
        switch self {
        case .none: "lock.open"
        case .duration: "hourglass"
        case .untilTime: "clock"
        case .randomString: "keyboard"
        case .restart: "restart.circle"
        }
    }
}

struct BlockLock: Codable, Equatable {
    var method: LockMethod = .none
    /// For `.duration`, in seconds.
    var duration: TimeInterval = 60 * 60
    /// For `.untilTime`, only the time-of-day part is used.
    var untilTime = TimeOfDay(hour: 17, minute: 0)
    /// For `.randomString`.
    var stringLength: Int = 32

    // Runtime state, written when the lock engages.
    var engagedUntil: Date?
    var engagedUntilRestart: Bool = false
    /// Boot time when a restart lock engaged, so we can tell a real restart happened.
    var engagedAtBootTime: Date?

    func isLocked(at date: Date = Date()) -> Bool {
        if engagedUntilRestart { return true }
        if let engagedUntil, date < engagedUntil { return true }
        return false
    }

    /// What the row shows on the right-hand side.
    func statusText(at date: Date = Date()) -> String {
        if engagedUntilRestart { return "Locked until restart" }
        if let engagedUntil, date < engagedUntil {
            return "Locked until \(engagedUntil.formatted(date: .omitted, time: .shortened))"
        }
        return method == .none ? "Unlocked" : "Unlocked · \(method.title)"
    }

    /// Computes the end of the lock from the method, as of now.
    func engagementDeadline(from date: Date = Date()) -> Date? {
        switch method {
        case .none, .randomString, .restart:
            return nil
        case .duration:
            return date.addingTimeInterval(duration)
        case .untilTime:
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = untilTime.hour
            components.minute = untilTime.minute
            guard let target = calendar.date(from: components) else { return nil }
            // A time already past today means tomorrow.
            return target > date ? target : calendar.date(byAdding: .day, value: 1, to: target)
        }
    }
}

// MARK: - Stats

struct BlockStats: Codable, Equatable {
    var timesTriggered: Int = 0
    var lastTriggered: Date?
    /// Seconds this block has spent active. Updated by the engine's tick.
    var activeSeconds: TimeInterval = 0
}

// MARK: - Presentation

enum BlockTint: String, Codable, CaseIterable, Identifiable {
    case indigo, blue, teal, green, orange, pink, purple, graphite

    var id: String { rawValue }
}

/// How hard the shield pushes back when you hit a block. Distinct from the lock.
enum Friction: String, Codable, CaseIterable, Identifiable {
    case gentle, firm, severe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gentle: "Gentle"
        case .firm: "Firm"
        case .severe: "Severe"
        }
    }

    var summary: String {
        switch self {
        case .gentle: "The shield appears and you can leave right away."
        case .firm: "Friction grows with every strike."
        case .severe: "A wait every time, and a phrase to type after the second."
        }
    }

    var symbol: String {
        switch self {
        case .gentle: "leaf"
        case .firm: "hand.raised"
        case .severe: "exclamationmark.shield"
        }
    }
}
