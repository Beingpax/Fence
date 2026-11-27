import Foundation
import SQLite3

/// One reach Fence paused: what was reached for, when, what the person said was behind it,
/// and how it ended.
struct ReachEntry: Identifiable, Hashable, Sendable {
    enum Outcome: String, Sendable {
        /// The pause is still up, or Fence stopped before it was answered.
        case open
        /// They turned back: the tab closed or the app quit.
        case closed
        /// "I need it": access started after the wait.
        case breakTaken = "break"
        /// The pause was taken down for them, because the block ended or detection stopped.
        case dismissed
        /// They closed it, or went elsewhere, during the heads-up card: no pause needed.
        case leftEarly = "left_early"
    }

    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var blockID: UUID?
    var blockName: String
    /// The rule that matched, as the person would read it: "youtube.com/shorts", "Steam".
    var rule: String
    /// The site's host or the app's name.
    var target: String
    var appName: String
    var bundleID: String
    var url: String?
    var windowTitle: String?
    /// Which reach for this rule within the hour: 1, 2, 3 or more.
    var visit: Int
    var waitSeconds: Int
    var feeling: UrgeReason?
    /// What they wrote about it, in their own words.
    var reflection: String?
    var outcome: Outcome
    var breakMinutes: Int?
}

/// Every reach Fence has paused, kept on this Mac in SQLite so it can be queried later.
///
/// Lives at `~/Library/Application Support/com.prakashjoshipax.Fence/journal.sqlite`. The schema is plain on
/// purpose, so the file can be read straight from a terminal:
///
///     sqlite3 ~/Library/Application\ Support/com.prakashjoshipax.Fence/journal.sqlite \
///       "select local_day, feeling, reflection from reaches order by started_at desc limit 20"
///
/// The `daily` view sums each day. `local_day`, `hour` and `weekday` are written at the
/// time of the reach, in the Mac's time zone then, so grouping never depends on where the
/// reader is.
///
/// Both of Fence's processes (the dashboard and the background agent) can write here, so the
/// database runs in WAL mode with a busy timeout. Every call runs on one serial queue, which
/// also keeps a reach's start and finish in order.
final class ReachJournal: @unchecked Sendable {
    static let shared = ReachJournal()

    /// Posted to every Fence process after a write, so an open Journal page can refresh.
    static let changed = Notification.Name("\(AppIdentity.bundleID).journalChanged")

    private let queue = DispatchQueue(label: "\(AppIdentity.bundleID).journal")
    private let url: URL
    /// Only touched on `queue`.
    private var db: OpaquePointer?

    init(url: URL = FenceInstallation.supportDirectory.appending(path: "journal.sqlite")) {
        self.url = url
    }

    // MARK: Writing

    /// Records a reach the moment the pause goes up, so it survives even if Fence doesn't.
    func begin(_ entry: ReachEntry) {
        queue.async { [self] in
            guard let db = openIfNeeded() else { return }
            let sql = """
                insert or replace into reaches (
                    id, started_at, ended_at, local_day, hour, weekday,
                    block_id, block_name, rule, target, app_name, bundle_id, url, window_title,
                    visit, wait_seconds, feeling, reflection, reflection_words, outcome, break_minutes
                ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            let calendar = Calendar.current
            let parts = calendar.dateComponents([.hour, .weekday], from: entry.startedAt)
            run(db, sql, [
                .text(entry.id.uuidString),
                .real(entry.startedAt.timeIntervalSince1970),
                .real(entry.endedAt?.timeIntervalSince1970),
                .text(Self.dayString(entry.startedAt, calendar: calendar)),
                .int(parts.hour),
                .int(parts.weekday),
                .text(entry.blockID?.uuidString),
                .text(entry.blockName),
                .text(entry.rule),
                .text(entry.target),
                .text(entry.appName),
                .text(entry.bundleID),
                .text(entry.url),
                .text(entry.windowTitle),
                .int(entry.visit),
                .int(entry.waitSeconds),
                .text(entry.feeling?.rawValue),
                .text(entry.reflection),
                .int(entry.reflection.map(Reflection.wordCount)),
                .text(entry.outcome.rawValue),
                .int(entry.breakMinutes),
            ])
            Self.announce()
        }
    }

    /// Records how a reach ended.
    func finish(
        id: UUID,
        outcome: ReachEntry.Outcome,
        feeling: UrgeReason? = nil,
        reflection: String? = nil,
        breakMinutes: Int? = nil,
        at date: Date = .now
    ) {
        queue.async { [self] in
            guard let db = openIfNeeded() else { return }
            let reflection = reflection?.trimmingCharacters(in: .whitespacesAndNewlines)
            let written = reflection?.isEmpty == false ? reflection : nil
            run(db, """
                update reaches set
                    ended_at = ?, outcome = ?, feeling = coalesce(?, feeling),
                    reflection = coalesce(?, reflection),
                    reflection_words = coalesce(?, reflection_words),
                    break_minutes = coalesce(?, break_minutes)
                where id = ?
                """, [
                .real(date.timeIntervalSince1970),
                .text(outcome.rawValue),
                .text(feeling?.rawValue),
                .text(written),
                .int(written.map(Reflection.wordCount)),
                .int(breakMinutes),
                .text(id.uuidString),
            ])
            Self.announce()
        }
    }

    /// Waits for every pending write to land. For a process about to exit.
    func flush() {
        queue.sync {}
    }

    // MARK: Reading

    /// Reaches that started on or after `date`, newest first.
    func entries(since date: Date) async -> [ReachEntry] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: readEntries(since: date))
            }
        }
    }

    private func readEntries(since date: Date) -> [ReachEntry] {
        guard let db = openIfNeeded() else { return [] }
        let sql = """
            select id, started_at, ended_at, block_id, block_name, rule, target, app_name,
                   bundle_id, url, window_title, visit, wait_seconds, feeling, reflection,
                   outcome, break_minutes
            from reaches where started_at >= ? order by started_at desc
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)

        var result: [ReachEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = Self.text(statement, 0).flatMap(UUID.init(uuidString:)) else { continue }
            result.append(ReachEntry(
                id: id,
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                endedAt: Self.double(statement, 2).map(Date.init(timeIntervalSince1970:)),
                blockID: Self.text(statement, 3).flatMap(UUID.init(uuidString:)),
                blockName: Self.text(statement, 4) ?? "",
                rule: Self.text(statement, 5) ?? "",
                target: Self.text(statement, 6) ?? "",
                appName: Self.text(statement, 7) ?? "",
                bundleID: Self.text(statement, 8) ?? "",
                url: Self.text(statement, 9),
                windowTitle: Self.text(statement, 10),
                visit: Int(sqlite3_column_int64(statement, 11)),
                waitSeconds: Int(sqlite3_column_int64(statement, 12)),
                feeling: Self.text(statement, 13).flatMap(UrgeReason.init(rawValue:)),
                reflection: Self.text(statement, 14),
                outcome: Self.text(statement, 15).flatMap(ReachEntry.Outcome.init(rawValue:)) ?? .open,
                breakMinutes: Self.double(statement, 16).map { Int($0) }
            ))
        }
        return result
    }

    // MARK: Schema

    private static let schemaVersion: Int32 = 2

    private func openIfNeeded() -> OpaquePointer? {
        if let db { return db }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return nil
        }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path(percentEncoded: false), &handle, flags, nil) == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            return nil
        }
        sqlite3_busy_timeout(handle, 3000)
        sqlite3_exec(handle, "pragma journal_mode = wal", nil, nil, nil)
        migrate(handle)
        db = handle
        return handle
    }

    private func migrate(_ db: OpaquePointer) {
        var version: Int32 = 0
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "pragma user_version", -1, &statement, nil) == SQLITE_OK,
           sqlite3_step(statement) == SQLITE_ROW {
            version = sqlite3_column_int(statement, 0)
        }
        sqlite3_finalize(statement)
        guard version < Self.schemaVersion else { return }

        sqlite3_exec(db, """
            begin;
            create table if not exists reaches (
                id               text primary key,
                started_at       real not null,   -- seconds since 1970, UTC
                ended_at         real,
                local_day        text not null,   -- yyyy-MM-dd in the Mac's time zone
                hour             integer,         -- 0–23, local
                weekday          integer,         -- 1 = Sunday … 7 = Saturday
                block_id         text,
                block_name       text not null,
                rule             text not null,   -- the rule that matched
                target           text not null,   -- the host or app reached for
                app_name         text not null,
                bundle_id        text not null,
                url              text,
                window_title     text,
                visit            integer not null, -- reach number for this rule within the hour
                wait_seconds     integer not null,
                feeling          text,            -- bored, tired, stuck, anxious, lonely, needed
                reflection       text,            -- what they wrote, in their own words
                reflection_words integer,
                outcome          text not null,   -- open, closed, break, dismissed, left_early
                break_minutes    integer
            );
            create index if not exists reaches_started on reaches (started_at);
            create index if not exists reaches_day on reaches (local_day);
            create view if not exists daily as
                select local_day,
                       count(*) as reaches,
                       sum(outcome = 'closed') as turned_back,
                       sum(outcome = 'break') as breaks,
                       sum(feeling is not null) as named
                from reaches group by local_day order by local_day desc;
            pragma user_version = 1;
            commit;
            """, nil, nil, nil)
        // 2: turning back during the heads-up counts as turning back.
        sqlite3_exec(db, """
            begin;
            drop view if exists daily;
            create view daily as
                select local_day,
                       count(*) as reaches,
                       sum(outcome in ('closed', 'left_early')) as turned_back,
                       sum(outcome = 'left_early') as before_pause,
                       sum(outcome = 'break') as breaks,
                       sum(feeling is not null) as named
                from reaches group by local_day order by local_day desc;
            pragma user_version = 2;
            commit;
            """, nil, nil, nil)
    }

    // MARK: SQLite plumbing

    private enum Value {
        case text(String?)
        case real(Double?)
        case int(Int?)
    }

    /// Tells SQLite to copy bound strings, since Swift's buffers don't outlive the call.
    private static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    @discardableResult
    private func run(_ db: OpaquePointer, _ sql: String, _ values: [Value]) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let text?): sqlite3_bind_text(statement, index, text, -1, Self.transient)
            case .real(let number?): sqlite3_bind_double(statement, index, number)
            case .int(let number?): sqlite3_bind_int64(statement, index, Int64(number))
            default: sqlite3_bind_null(statement, index)
            }
        }
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    private static func double(_ statement: OpaquePointer?, _ column: Int32) -> Double? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, column)
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func announce() {
        DistributedNotificationCenter.default().postNotificationName(changed, object: nil, userInfo: nil, deliverImmediately: true)
    }
}

/// The written reason the pause asks for once an answer is picked: optional for a
/// feeling, required for "I need it". How many words each needs is `UrgeReason.minimumWords`.
enum Reflection {
    /// Words with at least one letter or digit, so a run of spaces or dashes doesn't count.
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace })
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
            .count
    }
}
