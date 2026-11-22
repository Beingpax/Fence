import Foundation

/// A plain-language answer to "what steals your time?", compiled into `BlockRules`.
///
/// Onboarding never shows the user a hostname or a bundle ID. They pick the things they
/// recognise, and Shift turns those into the rules the tier-0 classifier actually runs.
struct DistractionPreset: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let symbol: String
    /// Whole sites, subdomains included.
    var hosts: [String] = []
    /// Parts of sites, so the useful half of a site survives.
    var paths: [String] = []
    /// Native apps by bundle ID.
    var apps: [String] = []
    /// One line explaining what picking this actually does.
    var effect: String

    static let all: [DistractionPreset] = [
        DistractionPreset(
            id: "instagram",
            title: "Instagram",
            symbol: "camera",
            hosts: ["instagram.com"],
            effect: "Blocks all of Instagram."
        ),
        DistractionPreset(
            id: "tiktok",
            title: "TikTok",
            symbol: "music.note",
            hosts: ["tiktok.com"],
            effect: "Blocks all of TikTok."
        ),
        DistractionPreset(
            id: "x",
            title: "X / Twitter",
            symbol: "bubble.left.and.bubble.right",
            hosts: ["x.com", "twitter.com"],
            effect: "Blocks both x.com and twitter.com."
        ),
        DistractionPreset(
            id: "facebook",
            title: "Facebook",
            symbol: "person.2",
            hosts: ["facebook.com"],
            effect: "Blocks all of Facebook."
        ),
        DistractionPreset(
            id: "reddit",
            title: "Reddit",
            symbol: "text.bubble",
            hosts: ["reddit.com"],
            effect: "Blocks all of Reddit."
        ),
        DistractionPreset(
            id: "shorts",
            title: "YouTube Shorts",
            symbol: "play.rectangle",
            paths: ["youtube.com/shorts", "youtube.com/feed/trending"],
            effect: "Blocks Shorts and Trending. Lectures and search still work."
        ),
        DistractionPreset(
            id: "linkedin",
            title: "The LinkedIn feed",
            symbol: "briefcase",
            paths: ["linkedin.com/feed"],
            effect: "Blocks the feed. Messages and profiles still work."
        ),
        DistractionPreset(
            id: "news",
            title: "News and Hacker News",
            symbol: "newspaper",
            hosts: ["news.ycombinator.com", "news.google.com", "cnn.com", "bbc.com/news"],
            effect: "Blocks the usual news stops."
        ),
        DistractionPreset(
            id: "streaming",
            title: "Netflix and streaming",
            symbol: "tv",
            hosts: ["netflix.com", "hulu.com", "disneyplus.com", "primevideo.com"],
            apps: ["com.netflix.Netflix"],
            effect: "Blocks streaming sites and the Netflix app."
        ),
        DistractionPreset(
            id: "twitch",
            title: "Twitch",
            symbol: "gamecontroller",
            hosts: ["twitch.tv"],
            effect: "Blocks all of Twitch."
        ),
        DistractionPreset(
            id: "chat",
            title: "Discord",
            symbol: "message",
            apps: ["com.hnc.Discord"],
            effect: "Force quits Discord when it comes up."
        ),
        DistractionPreset(
            id: "games",
            title: "Games and Steam",
            symbol: "arcade.stick",
            apps: ["com.valvesoftware.steam"],
            effect: "Force quits Steam when it comes up."
        ),
        DistractionPreset(
            id: "shopping",
            title: "Shopping",
            symbol: "cart",
            hosts: ["amazon.com", "ebay.com", "aliexpress.com"],
            effect: "Blocks the big shopping sites."
        ),
        DistractionPreset(
            id: "memes",
            title: "Meme sites",
            symbol: "face.smiling",
            hosts: ["9gag.com", "imgur.com"],
            effect: "Blocks 9GAG and Imgur."
        ),
    ]
}

extension BlockRules {
    /// Builds rules from onboarding answers, keeping the work-app allowlist and nudge
    /// keywords from the defaults because those are safety rails rather than preferences.
    static func from(presets: [DistractionPreset], custom: [String] = []) -> BlockRules {
        let defaults = BlockRules.default
        let cleanedCustom = custom
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        // A custom entry containing a slash is a path rule; otherwise it's a whole site.
        let customPaths = cleanedCustom.filter { $0.contains("/") }
        let customHosts = cleanedCustom.filter { !$0.contains("/") }

        return BlockRules(
            blockedHosts: unique(presets.flatMap(\.hosts) + customHosts),
            blockedPaths: unique(presets.flatMap(\.paths) + customPaths),
            blockedApps: unique(presets.flatMap(\.apps)),
            alwaysAllowedApps: defaults.alwaysAllowedApps,
            nudgeTitleKeywords: defaults.nudgeTitleKeywords
        )
    }

    /// Which presets the current rules already cover, so onboarding can be re-entered
    /// with the user's previous answers selected.
    var matchingPresets: [DistractionPreset] {
        DistractionPreset.all.filter { preset in
            let hostsCovered = !preset.hosts.isEmpty && preset.hosts.allSatisfy(blockedHosts.contains)
            let pathsCovered = !preset.paths.isEmpty && preset.paths.allSatisfy(blockedPaths.contains)
            let appsCovered = !preset.apps.isEmpty && preset.apps.allSatisfy(blockedApps.contains)
            return hostsCovered || pathsCovered || appsCovered
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
