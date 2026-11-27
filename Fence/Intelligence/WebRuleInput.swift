import Foundation

/// Text visible in the current HTTP(S) address. Query values are decoded individually,
/// so escaped delimiters stay in the value and phrases never span unrelated parameters.
struct WebRuleInput {
    let host: String
    let address: String
    let searches: [String]
    private let adultSearchQuery: String?

    init?(url: URL) {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let hostname = url.host(), !hostname.isEmpty else { return nil }
        host = hostname.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        parts.user = nil
        parts.password = nil
        let encodedQuery = parts.percentEncodedQuery
        let encodedFragment = parts.percentEncodedFragment
        parts.query = nil
        parts.fragment = nil
        adultSearchQuery = Self.searchQuery(host: host, path: parts.percentEncodedPath, query: encodedQuery)
        // Hash routers can expose a second query, such as #/results?q=live+scores or #q=live+scores.
        let hash = encodedFragment ?? ""
        let hashParts = hash.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let hashIsQuery = hashParts.count == 1 && hash.contains("=") && !hash.hasPrefix("/")
        let fragmentQuery = hashParts.count == 2 ? String(hashParts[1]) : (hashIsQuery ? hash : nil)
        let fragmentPath = hashIsQuery ? "" : Self.decode(String(hashParts.first ?? ""))
        var text = Self.decode(parts.string ?? "")
        if let encodedQuery { text += "?" + Self.formValue(encodedQuery) }
        if encodedFragment != nil {
            text += "#" + fragmentPath
            if let fragmentQuery {
                text += (hashIsQuery ? "" : "?") + Self.formValue(fragmentQuery)
            }
        }
        address = text

        let querySearches: [String] = [encodedQuery, fragmentQuery].compactMap { $0 }.flatMap { query in
            query.split(separator: "&").compactMap { item -> String? in
                let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard pair.count == 2, Self.searchKeys.contains(Self.formValue(String(pair[0])).lowercased())
                else { return nil }
                return Self.formValue(String(pair[1]))
            }
        }
        // Some sites put a submitted search after a /search/ or /searches/ path segment.
        let pathSegments = parts.percentEncodedPath.split(separator: "/").map { Self.decode(String($0)) }
        let pathSearches = zip(pathSegments, pathSegments.dropFirst()).compactMap { segment, value in
            ["search", "searches"].contains(segment.lowercased()) ? value : nil
        }
        searches = querySearches + pathSearches
    }

    private static let searchKeys: Set<String> = [
        "q", "query", "search", "search_query", "search_term", "searchterm", "searchtermtext",
        "keyword", "keywords", "term", "text", "p", "s", "wd", "k",
    ]

    private static func decode(_ string: String) -> String { string.removingPercentEncoding ?? string }

    private static func formValue(_ string: String) -> String {
        decode(string.replacingOccurrences(of: "+", with: " "))
    }

    func matches(_ rule: WebTextRule) -> Bool {
        guard !rule.text.isEmpty else { return false }
        switch rule.scope {
        case .url: return address.localizedCaseInsensitiveContains(rule.text)
        case .urlPattern:
            // Match the literal pieces in order. Only * is special, including in a query.
            let pieces = rule.text.split(separator: "*")
            guard !pieces.isEmpty else { return false }
            var remaining = address[...]
            for piece in pieces {
                guard let match = remaining.range(of: piece, options: .caseInsensitive) else { return false }
                remaining = remaining[match.upperBound...]
            }
            return true
        case .search: return searches.contains { $0.localizedCaseInsensitiveContains(rule.text) }
        }
    }

    /// A whole submitted query on a known results page is a stronger signal than a mention in a URL.
    private static func searchQuery(host: String, path: String, query: String?) -> String? {
        guard let query else { return nil }
        let key: String
        switch (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host, path) {
        case ("google.com", "/search"), ("bing.com", "/search"), ("search.brave.com", "/search"),
             ("duckduckgo.com", "/"), ("duckduckgo.com", ""):
            key = "q"
        case ("youtube.com", "/results"):
            key = "search_query"
        default:
            return nil
        }
        let values = query.split(separator: "&").compactMap { item -> String? in
            let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, Self.formValue(String(pair[0])) == key else { return nil }
            return Self.formValue(String(pair[1])).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return values.count == 1 ? values[0] : nil
    }

    private static let explicitQueries: Set<String> = [
        "nsfw", "porn", "porno", "porn videos", "xxx videos", "pornhub", "xvideos", "xnxx", "xhamster",
    ]

    func matchesAdultSearch(in catalog: WebsiteCategoryCatalog) -> Bool {
        guard let query = adultSearchQuery else { return false }
        return Self.explicitQueries.contains(query) || catalog.categories(forHost: query).contains(BlockList.adultSitesCategory)
    }
}
