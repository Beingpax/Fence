import Foundation

/// Ready-made blocks.
///
/// Starting from a blank block means staring at an empty list and trying to remember
/// every domain that wastes your time. These are the blocks people actually build, already
/// filled in, and every one of them is still fully editable afterwards.
struct BlockTemplate: Identifiable {
    let id: String
    let name: String
    let tagline: String
    let symbol: String
    let tint: BlockTint
    let hosts: [String]
    let paths: [String]
    let apps: [String]
    let schedule: BlockSchedule
    let friction: Friction
    let suggestedLock: LockMethod

    func makeBlock() -> Block {
        var block = Block(name: name)
        block.symbol = symbol
        block.tint = tint
        block.list = BlockList(hosts: hosts, paths: paths, apps: apps)
        block.schedule = schedule
        block.friction = friction
        block.lock.method = suggestedLock
        return block
    }

    static let all: [BlockTemplate] = [
        BlockTemplate(
            id: "social",
            name: "Social media",
            tagline: "The feeds, all of them, all the time.",
            symbol: "bubble.left.and.bubble.right.fill",
            tint: .pink,
            hosts: ["instagram.com", "x.com", "twitter.com", "facebook.com", "tiktok.com", "threads.net", "snapchat.com"],
            paths: ["linkedin.com/feed"],
            apps: [],
            schedule: .always,
            friction: .firm,
            suggestedLock: .none
        ),
        BlockTemplate(
            id: "deepwork",
            name: "Deep work",
            tagline: "Everything noisy, for a stretch you choose.",
            symbol: "brain.head.profile",
            tint: .indigo,
            hosts: ["instagram.com", "x.com", "twitter.com", "reddit.com", "news.ycombinator.com", "youtube.com", "tiktok.com"],
            paths: [],
            apps: ["com.hnc.Discord", "com.tinyspeck.slackmacgap", "com.apple.MobileSMS"],
            schedule: .manual(minutes: 50),
            friction: .severe,
            suggestedLock: .duration
        ),
        BlockTemplate(
            id: "rabbithole",
            name: "Rabbit holes",
            tagline: "Shorts, Reels and the endless scroll, without losing the useful parts.",
            symbol: "arrow.trianglehead.2.clockwise.rotate.90",
            tint: .orange,
            hosts: ["tiktok.com", "9gag.com", "imgur.com"],
            paths: ["youtube.com/shorts", "youtube.com/feed/trending", "instagram.com/reels", "reddit.com/r/all"],
            apps: [],
            schedule: .always,
            friction: .firm,
            suggestedLock: .none
        ),
        BlockTemplate(
            id: "news",
            name: "News and doomscrolling",
            tagline: "Headlines can wait until you've done something.",
            symbol: "newspaper.fill",
            tint: .teal,
            hosts: ["news.ycombinator.com", "news.google.com", "cnn.com", "bbc.com", "nytimes.com", "theguardian.com", "reddit.com"],
            paths: [],
            apps: ["com.apple.news"],
            schedule: .scheduled([
                ScheduleWindow(days: Weekday.weekdays, start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 12, minute: 0))
            ]),
            friction: .firm,
            suggestedLock: .none
        ),
        BlockTemplate(
            id: "evening",
            name: "Evening wind-down",
            tagline: "Screens get quieter after ten.",
            symbol: "moon.stars.fill",
            tint: .purple,
            hosts: ["youtube.com", "netflix.com", "twitch.tv", "instagram.com", "tiktok.com", "x.com"],
            paths: [],
            apps: ["com.netflix.Netflix"],
            schedule: .scheduled([
                ScheduleWindow(
                    days: Set(Weekday.allCases),
                    start: TimeOfDay(hour: 22, minute: 0),
                    end: TimeOfDay(hour: 6, minute: 0)
                )
            ]),
            friction: .severe,
            suggestedLock: .untilTime
        ),
        BlockTemplate(
            id: "entertainment",
            name: "Entertainment",
            tagline: "Streaming and games, off the table.",
            symbol: "tv.fill",
            tint: .blue,
            hosts: ["netflix.com", "hulu.com", "disneyplus.com", "primevideo.com", "twitch.tv"],
            paths: [],
            apps: ["com.valvesoftware.steam", "com.netflix.Netflix", "com.spotify.client"],
            schedule: .always,
            friction: .firm,
            suggestedLock: .none
        ),
        BlockTemplate(
            id: "shopping",
            name: "Shopping",
            tagline: "For the browsing that ends in a parcel.",
            symbol: "cart.fill",
            tint: .green,
            hosts: ["amazon.com", "ebay.com", "aliexpress.com", "etsy.com", "temu.com"],
            paths: [],
            apps: [],
            schedule: .always,
            friction: .gentle,
            suggestedLock: .none
        ),
        BlockTemplate(
            id: "blank",
            name: "Blank block",
            tagline: "Start from nothing and build it yourself.",
            symbol: "square.dashed",
            tint: .graphite,
            hosts: [],
            paths: [],
            apps: [],
            schedule: .always,
            friction: .firm,
            suggestedLock: .none
        ),
    ]
}
