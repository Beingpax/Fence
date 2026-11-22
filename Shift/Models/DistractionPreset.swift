import Foundation

/// A plain-language answer to "what steals your time?", compiled into a `BlockList`.
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

extension BlockList {
    /// Builds a list from onboarding answers. Entries containing a slash become path
    /// rules, so the useful half of a site survives; everything else is a whole site.
    static func from(presets: [DistractionPreset], custom: [String] = []) -> BlockList {
        let cleaned = custom
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return BlockList(
            hosts: unique(presets.flatMap(\.hosts) + cleaned.filter { !$0.contains("/") }),
            paths: unique(presets.flatMap(\.paths) + cleaned.filter { $0.contains("/") }),
            apps: unique(presets.flatMap(\.apps)),
            exceptions: []
        )
    }

    /// Which presets this list already covers, so the picker can be re-entered with the
    /// previous answers selected.
    var matchingPresets: [DistractionPreset] {
        DistractionPreset.all.filter { preset in
            let hostsCovered = !preset.hosts.isEmpty && preset.hosts.allSatisfy(hosts.contains)
            let pathsCovered = !preset.paths.isEmpty && preset.paths.allSatisfy(paths.contains)
            let appsCovered = !preset.apps.isEmpty && preset.apps.allSatisfy(apps.contains)
            return hostsCovered || pathsCovered || appsCovered
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

/// Words that only ever nudge. Global rather than per block, because drift isn't about
/// any one rule the user wrote.
enum DriftKeywords {
    static let `default` = ["Shorts", "Reels", "For You", "Trending", "Explore"]
}
