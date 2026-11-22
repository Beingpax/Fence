import Foundation

/// Tier 0 rules. Fast, deterministic, and the fallback when no AI model is installed.
struct BlockRules: Codable, Equatable {
    /// Whole sites, e.g. "instagram.com" (also matches subdomains).
    var blockedHosts: [String]
    /// Parts of a site, e.g. "youtube.com/shorts", while the rest of youtube.com stays allowed.
    var blockedPaths: [String]
    /// Native apps by bundle ID.
    var blockedApps: [String]
    /// Work apps that are never blocked (PRD: default to allow on work apps).
    var alwaysAllowedApps: [String]
    /// Window-title words that suggest drift. These only nudge, never block.
    var nudgeTitleKeywords: [String]

    static let `default` = BlockRules(
        blockedHosts: [
            "instagram.com", "facebook.com", "tiktok.com", "x.com", "twitter.com",
            "reddit.com", "netflix.com", "twitch.tv", "9gag.com",
        ],
        blockedPaths: [
            "youtube.com/shorts", "youtube.com/feed/trending", "linkedin.com/feed",
        ],
        blockedApps: [
            "com.hnc.Discord", "com.valvesoftware.steam", "com.netflix.Netflix",
        ],
        alwaysAllowedApps: [
            "com.apple.dt.Xcode", "com.apple.Terminal", "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92", "com.apple.finder", "com.apple.Notes",
        ],
        nudgeTitleKeywords: [
            "Shorts", "Reels", "For You", "Trending", "Explore",
        ]
    )

    // MARK: Persistence

    private static let defaultsKey = "Shift.BlockRules.v1"

    static func load() -> BlockRules {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let rules = try? JSONDecoder().decode(BlockRules.self, from: data)
        else { return .default }
        return rules
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
