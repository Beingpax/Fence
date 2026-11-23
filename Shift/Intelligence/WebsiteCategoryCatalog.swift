import Foundation
import os

/// Category names are persisted in blocks. A leading ! excludes an otherwise inherited www alias.
struct WebsiteCategoryCatalog {
    static let shared = WebsiteCategoryCatalog()
    let domains: [String: [String]]
    private let byHost: [String: Set<String>]
    private let exclusions: [String: Set<String>]

    init(url: URL? = Bundle.main.url(forResource: "WebsiteCategories", withExtension: "json")) {
        var groups: [String: [String]] = [:]
        do {
            guard let url else { throw CocoaError(.fileNoSuchFile) }
            groups = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: url))
        } catch {
            Logger(subsystem: "com.beingpax.Shift", category: "WebsiteCategories").error("Cannot load website lists: \(error.localizedDescription)")
        }
        var index: [String: Set<String>] = [:]
        var excluded: [String: Set<String>] = [:]
        for (name, hosts) in groups {
            let membership: Set<String> = [name]
            for host in hosts {
                if host.hasPrefix("!") {
                    excluded[String(host.dropFirst()), default: []].insert(name)
                } else if index[host] == nil {
                    index[host] = membership
                } else {
                    index[host, default: []].insert(name)
                }
            }
        }
        domains = excluded.isEmpty ? groups : groups.mapValues { $0.filter { !$0.hasPrefix("!") } }
        byHost = index
        exclusions = excluded
    }

    /// Takes a lowercase hostname with its www prefix intact. Other subdomains need their own listing.
    func categories(forHost host: String) -> Set<String> {
        guard host.utf8.count <= 253 else { return [] }
        var matches = byHost[host] ?? []
        if host.hasPrefix("www."), let inherited = byHost[String(host.dropFirst(4))] {
            matches.formUnion(inherited)
        }
        if let excluded = exclusions[host] { matches.subtract(excluded) }
        return matches
    }
}
