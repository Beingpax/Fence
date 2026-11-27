import Foundation
import SQLite3

/// A disk-backed, primary-key lookup with one reused statement, as in the original catalog.
private final class SQLIndex {
    let database: OpaquePointer
    let query: OpaquePointer

    init(url: URL) {
        var db: OpaquePointer?
        precondition(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        database = db!
        var statement: OpaquePointer?
        precondition(sqlite3_prepare_v2(database, "SELECT value FROM hosts WHERE host=?", -1, &statement, nil) == SQLITE_OK)
        query = statement!
    }

    func value(_ host: String) -> Int? {
        host.withCString { name in
            sqlite3_bind_text(query, 1, name, -1, nil)
            defer {
                sqlite3_reset(query)
                sqlite3_clear_bindings(query)
            }
            guard sqlite3_step(query) == SQLITE_ROW else { return nil }
            return Int(sqlite3_column_int(query, 0))
        }
    }

    deinit {
        sqlite3_finalize(query)
        sqlite3_close(database)
    }

    static func write(_ entries: [String: Int], to url: URL) {
        var db: OpaquePointer?
        precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        precondition(sqlite3_exec(db, "CREATE TABLE hosts(host TEXT PRIMARY KEY, value INTEGER NOT NULL) WITHOUT ROWID", nil, nil, nil) == SQLITE_OK)
        precondition(sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK)
        var insert: OpaquePointer?
        precondition(sqlite3_prepare_v2(db, "INSERT INTO hosts VALUES (?,?)", -1, &insert, nil) == SQLITE_OK)
        defer { sqlite3_finalize(insert) }
        for host in entries.keys.sorted() {
            host.withCString { key in
                sqlite3_bind_text(insert, 1, key, -1, nil)
                sqlite3_bind_int(insert, 2, Int32(entries[host]!))
                precondition(sqlite3_step(insert) == SQLITE_DONE)
                sqlite3_reset(insert)
                sqlite3_clear_bindings(insert)
            }
        }
        precondition(sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK)
    }
}

@main private enum CatalogBenchmark {
    typealias Lookup = (String) -> Int

    // Deterministic mix of 50% listed hosts and 50% misses, sampled with replacement.
    static func probes(_ entries: [String: Int]) -> [(String, Int)] {
        let hosts = entries.keys.sorted()
        precondition(!hosts.isEmpty)
        var seed: UInt64 = 1301
        return (0..<20_000).map { i in
            seed = seed &* 6364136223846793005 &+ 1
            let host = i.isMultiple(of: 2) ? hosts[Int((seed >> 32) % UInt64(hosts.count))] : "unlisted-\(i).invalid"
            return (host, entries[host] ?? 0)
        }
    }

    static func measure(_ label: String, probes: [(String, Int)], build: () -> Lookup) {
        var loads: [Double] = [], means: [Double] = [], tails: [Double] = []
        for _ in 0..<5 {
            let start = DispatchTime.now().uptimeNanoseconds
            let lookup = build()
            precondition(lookup(probes[0].0) == probes[0].1)
            loads.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            var durations: [UInt64] = []
            durations.reserveCapacity(probes.count)
            for (host, expected) in probes {
                let before = DispatchTime.now().uptimeNanoseconds
                let actual = lookup(host)
                durations.append(DispatchTime.now().uptimeNanoseconds - before)
                precondition(actual == expected, "Lookup disagreed for \(host)")
            }
            means.append(Double(durations.reduce(0,+)) / Double(durations.count) / 1e3)
            tails.append(Double(durations.sorted()[durations.count * 95 / 100]) / 1e3)
        }
        print(String(format: "%@: load + first lookup %.3f ms, mean %.3f µs, p95 %.3f µs",
                     label, loads.sorted()[2], means.sorted()[2], tails.sorted()[2]))
    }

    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Fence/Resources/Filtering")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let json = root.appendingPathComponent("WebsiteCategories.json")
        let groups = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: json))
        var memberships: [String: Int] = [:]
        for entries in groups.values {
            let listed = Set(entries.filter { !$0.hasPrefix("!") })
            let excluded = Set(entries.filter { $0.hasPrefix("!") }.map { String($0.dropFirst()) })
            let aliases = listed.map { "www." + $0 }
            for host in listed.union(aliases).subtracting(excluded) { memberships[host, default: 0] += 1 }
        }
        let categoryQueries = probes(memberships)
        // A precomputed membership count gives SQLite a single indexed row per probe.
        let categoryDB = directory.appendingPathComponent("categories.sqlite")
        SQLIndex.write(memberships, to: categoryDB)
        print("\(groups.count) categories, \(memberships.count) effective hosts including www aliases")
        measure("Category JSON", probes: categoryQueries) {
            let index = WebsiteCategoryCatalog(url: json)
            return { index.categories(forHost: $0).count }
        }
        measure("Category SQLite", probes: categoryQueries) {
            let index = SQLIndex(url: categoryDB)
            return { index.value($0) ?? 0 }
        }

        let adult = "Adult sites"
        let entries = groups[adult] ?? []
        let decisions = Dictionary(uniqueKeysWithValues: entries.map { entry in
            entry.hasPrefix("!") ? (String(entry.dropFirst()), 0) : (entry, 1)
        })
        let adultQueries = probes(decisions)
        let adultDB = directory.appendingPathComponent("adult.sqlite")
        SQLIndex.write(decisions, to: adultDB)
        print("\(decisions.values.reduce(0,+)) adult hosts")
        measure("Adult sites in shared JSON", probes: adultQueries) {
            let index = WebsiteCategoryCatalog(url: json)
            return { index.categories(forHost: $0).contains(adult) ? 1 : 0 }
        }
        measure("Adult SQLite", probes: adultQueries) {
            let index = SQLIndex(url: adultDB)
            return { host in
                if let hit = index.value(host) { return hit }
                return host.hasPrefix("www.") ? index.value(String(host.dropFirst(4))) ?? 0 : 0
            }
        }
    }
}
