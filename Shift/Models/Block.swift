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

    /// Optional goal that gives focus nudges context.
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

    var canStartTimedRun: Bool { schedule.isManual && !isEnabled && !isLocked() }

    func requiresUnlockChallenge(at date: Date = Date()) -> Bool {
        guard isEnabled, lock.method == .randomString else { return false }
        return !schedule.isManual || manualRunEndsAt.map { $0 > date } == true
    }

    func isLocked(at date: Date = Date()) -> Bool {
        lock.isLocked(at: date) || requiresUnlockChallenge(at: date)
    }

    func lockStatus(at date: Date = Date()) -> String {
        if requiresUnlockChallenge(at: date) { return "Typing challenge required" }
        return lock.statusText(at: date)
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
        case .manual:
            if let manualRunEndsAt, manualRunEndsAt > Date() {
                return "Running until \(manualRunEndsAt.formatted(date: .omitted, time: .shortened))"
            }
            return "Start from the block menu"
        }
    }

    /// What the block covers, for the block row.
    var contentsSummary: String {
        var parts: [String] = []
        if list.siteCount > 0 { parts.append("\(list.siteCount) site\(list.siteCount == 1 ? "" : "s")") }
        if !list.apps.isEmpty { parts.append("\(list.apps.count) app\(list.apps.count == 1 ? "" : "s")") }
        if parts.isEmpty { return "Nothing blocked yet" }
        return parts.joined(separator: " · ")
    }
}

// MARK: - What a block covers

struct BlockList: Codable, Equatable {
    /// Whole sites, subdomains included.
    var hosts: [String] = []
    /// Parts of sites, e.g. "youtube.com/shorts".
    var paths: [String] = []
    /// Native apps by bundle identifier.
    var apps: [String] = []

    var isEmpty: Bool { hosts.isEmpty && paths.isEmpty && apps.isEmpty }

    var siteCount: Int { hosts.count + paths.count }

    mutating func addWebsite(_ address: WebsiteAddress) {
        guard !(hosts + paths).contains(where: { WebsiteAddress(entry: $0) == address }) else { return }
        if address.isDomainOnly {
            hosts.append(address.entry)
        } else {
            paths.append(address.entry)
        }
    }
}

// MARK: - When a block applies

enum BlockSchedule: Codable, Equatable {
    /// Always on while enabled. The global block.
    case always
    /// Recurring weekly windows.
    case scheduled([ScheduleWindow])
    /// No automatic schedule. The associated value remains decodable from older blocks.
    case manual(minutes: Int?)

    var isManual: Bool {
        if case .manual = self { return true }
        return false
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
        if days.isEmpty {
            dayPart = "No days selected"
        } else if days == Weekday.weekdays {
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
    static let minutes = 2
    static let dailyAllowance = 2

    /// Runtime: when the current break ends.
    var currentBreakEndsAt: Date?
    var breaksTakenToday: Int = 0
    var lastResetDay: Date?

    func isOnBreak(at date: Date = Date()) -> Bool {
        guard isEnabled, let currentBreakEndsAt else { return false }
        return date < currentBreakEndsAt
    }

    func remaining(at date: Date = Date()) -> Int {
        guard isEnabled else { return 0 }
        let usedToday = lastResetDay.map { Calendar.current.isDate($0, inSameDayAs: date) } == true
            ? breaksTakenToday : 0
        return max(0, Self.dailyAllowance - usedToday)
    }

    /// Uses one of today's breaks. `minutes` is capped at `Self.minutes`: the pause offers
    /// a shorter one-minute break, never a longer one.
    mutating func start(at date: Date, minutes: Int = Self.minutes) -> Bool {
        let available = remaining(at: date)
        guard available > 0, !isOnBreak(at: date) else { return false }
        breaksTakenToday = Self.dailyAllowance - available + 1
        lastResetDay = date
        currentBreakEndsAt = date.addingTimeInterval(TimeInterval(min(max(minutes, 1), Self.minutes)) * 60)
        return true
    }
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
        case .duration: "Lock for a duration"
        case .untilTime: "Lock until a time"
        case .randomString: "Typing challenge"
        case .restart: "Lock until restart"
        }
    }

    var detail: String {
        switch self {
        case .none: "Switch this block off whenever you want."
        case .duration: "The countdown starts when the block is switched on. You can turn it off when the timer ends."
        case .untilTime: "Choose the next time the block can be turned off. If that time has passed today, the lock ends tomorrow."
        case .randomString: "Enter a generated code exactly as shown to turn off the block early."
        case .restart: "The block stays locked until this Mac restarts. At restart, Shift switches the block off."
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
    static let challengeLengths = [32, 64, 80, 100]

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
    /// Used on newer saves to identify a reboot independently of the wall clock.
    var engagedBootSessionID: String?

    /// Resolves older settings to a length offered by the picker.
    var challengeLength: Int {
        Self.challengeLengths.first { $0 >= stringLength } ?? 100
    }

    func hasSameSettings(as other: Self) -> Bool {
        method == other.method && duration == other.duration
            && untilTime == other.untilTime && stringLength == other.stringLength
    }

    func isLocked(at date: Date = Date()) -> Bool {
        if engagedUntilRestart { return true }
        if let engagedUntil, date < engagedUntil { return true }
        return false
    }

    /// What the row shows on the right-hand side.
    func statusText(at date: Date = Date()) -> String {
        if engagedUntilRestart { return "Locked until restart" }
        if let engagedUntil, date < engagedUntil {
            let sameDay = Calendar.current.isDate(engagedUntil, inSameDayAs: date)
            let deadline = engagedUntil.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened)
            return "Locked until \(deadline)"
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
