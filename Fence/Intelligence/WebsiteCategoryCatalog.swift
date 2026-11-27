import Foundation
import Observation
import os

/// The bundled website lists, exactly as shipped. Edits live in `PreMadeLists`.
///
/// Category names are persisted in blocks. A leading ! excludes an otherwise inherited www alias.
struct WebsiteCategoryCatalog {
    static let shared = WebsiteCategoryCatalog()
    let domains: [String: [String]]
    private let byHost: [String: Set<String>]
    private let exclusions: [String: Set<String>]

    /// `lists` keeps only those lists (by saved name); nil keeps them all. Page checks pass
    /// the lists their blocks use, so a list is only held while a block includes it.
    init(url: URL? = Bundle.main.url(forResource: "WebsiteCategories", withExtension: "json"), only lists: Set<String>? = nil) {
        var groups: [String: [String]] = [:]
        do {
            guard let url else { throw CocoaError(.fileNoSuchFile) }
            groups = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: url))
        } catch {
            Logger(subsystem: AppIdentity.bundleID, category: "WebsiteCategories").error("Cannot load website lists: \(error.localizedDescription)")
        }
        if let lists { groups = groups.filter { lists.contains($0.key) } }
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

// MARK: - The lists a block can include

/// The pre-made lists, in the order the editor shows them (26 Nov 2026, the user's call:
/// social media (feeds, with video sites folded in, never chat apps), news, email and 18+
/// sites; search engines,
/// proxies, games, gambling, shopping and dating were dropped). Each holds sites and Mac apps.
///
/// The raw value is the key saved in blocks, so it never changes: the 18+ list is still
/// stored as "Adult sites" from before it was renamed.
enum PreMadeList: String, CaseIterable, Identifiable, Sendable {
    case socialMedia = "Social media"
    case news = "News"
    case email = "Email"
    case adult = "Adult sites"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adult: "18+ sites"
        default: rawValue
        }
    }

    var symbol: String {
        switch self {
        case .socialMedia: "bubble.left.and.bubble.right"
        case .news: "newspaper"
        case .email: "envelope"
        case .adult: "eye.slash"
        }
    }

    /// What it covers, for a tooltip.
    var help: String {
        switch self {
        case .socialMedia: "Instagram, TikTok, YouTube, Netflix and other feeds"
        case .news: "CNN, BBC, Spiegel and other big news sites"
        case .email: "Gmail, Outlook, Mail and other email"
        case .adult: "Known 18+ sites, and pages with explicit words in their address or title"
        }
    }

    /// The 18+ list's built-in sites and words are sealed: hidden, with no search, and
    /// impossible to take off (26 Nov 2026, the user's call: a searchable list of 29,000
    /// sites is a directory). People can still add their own and remove what they added.
    var isSealed: Bool { self == .adult }

    /// Words and phrases that block a page when its address or title has them in it. Since
    /// 26 Nov 2026 they do most of the 18+ list's work, with a short list of the most
    /// visited sites beside them (the user's call: 29,261 known sites missed every new and
    /// foreign one, and the words already caught 10,200 of them by name).
    ///
    /// Two kinds:
    /// - `builtInFragments` match anywhere, even inside a site's name ("freepornvids.net").
    ///   Each one has to be close to meaningless outside 18+ pages.
    /// - `builtInWholeWords` match only as words of their own, between spaces or `-` `/` `_`
    ///   `?` `=` `+` `.`, with an optional plural s. Phrases match word by word, so
    ///   "sex video" catches "sex-videos" and "sex+video" but never "same-sex".
    ///
    /// Never on their own, because they'd block ordinary pages: sex (Sussex, sex education,
    /// same-sex), cum (document, "hotel-cum-restaurant", cum laude), orgasm and oral (health),
    /// gay, lesbian, teen, mature, asian, breast, anal, naked, tits (the birds), pussy (willows),
    /// cock (roosters, cocktail), dick, ass, hardcore (music), escort (the Ford), sexy, adult.
    /// They do appear in phrases, next to a word that settles it ("teen sex", "dick pics").
    /// Sources and licences are in CREDITS.md.
    var builtInFragments: [String] { self == .adult ? Self.adultFragments : [] }
    var builtInWholeWords: [String] { self == .adult ? Self.adultPhrases : [] }
    var builtInWords: [String] { builtInFragments + builtInWholeWords }

    private static let adultFragments: [String] = [
        // The words themselves.
        "porn", "xxxvideo", "xxxmovie", "xxxsex", "hentai", "nsfw", "rule34", "bdsm", "femdom",
        "cuckold", "blowjob", "handjob", "footjob", "rimjob", "titjob", "cumshot", "creampie",
        "gangbang", "bukkake", "deepthroat", "masturbat", "softcore", "striptease", "upskirt",
        "camgirl", "camwhore", "sexcam", "livesex", "freesex", "sexvideo", "sexchat", "sextape",
        "sexmovie", "sexstories", "literotica", "jailbait", "milfs", "pussylick", "dickpic",
        // Big sites, so their mirrors and look-alikes are caught too.
        "xvideo", "xnxx", "xhamster", "redtube", "youjizz", "spankbang", "brazzers", "tnaflix",
        "onlyfans", "fansly", "chaturbate", "stripchat", "bongacams", "livejasmin", "camsoda",
        "myfreecams", "nhentai", "missav", "faphouse", "fapello",
        // Other languages: Russian, Chinese, Japanese, Korean, Arabic, Hindi, Indonesian.
        "порн", "色情", "无码", "黄色视频", "成人视频", "エロ動画", "アダルト動画", "無修正", "中出し",
        "야동", "포르노", "سكس", "चुदाई", "bokep", "ngentot", "colmek", "chudai",
    ]

    /// Phrases on their own, then every pairing of an ambiguous word with an explicit one.
    private static let adultPhrases: [String] = {
        var phrases = [
            // Explicit enough alone.
            "xxx", "nude", "milf", "boob", "dildo", "horny", "slut", "fetish", "bondage",
            "threesome", "erotic", "erotica", "ecchi", "jav", "fap", "beeg", "stepsis",
            "nangi", "ficken", "salope", "putaria", "buceta", "follando", "sikiş", "memek",
            "kantutan", "jakol",
            // Acts and positions.
            "blow job", "hand job", "foot job", "rim job", "gang bang", "cum shot", "jerk off",
            "jerking off", "jack off", "doggy style", "doggie style", "reverse cowgirl",
            "double penetration", "dry hump", "phone sex", "group sex", "anal sex", "rough sex",
            "menage a trois", "ball gag", "female squirting", "male squirting", "barely legal",
            "jail bait", "girls gone wild", "two girls one cup", "2 girls 1 cup",
            "big tits", "big boobs", "big knockers", "huge tits", "natural tits", "big black cock",
            "black cock", "big cock", "huge cock", "giant cock", "big dick", "shaved pussy",
            "wet pussy", "tight pussy", "hairy pussy", "pussy licking", "cock sucking",
            "suck dick", "suck cock", "dick pic", "only fans", "cam girl", "webcam sex",
            "live cam sex", "naked girls", "naked women", "naked men", "naked celebs",
            "hot girls naked", "adult movie", "adult film", "adult video", "adult cam",
            "adult site", "sex doll", "happy ending massage", "nuru massage",
            // South and Southeast Asian slang: "blue film" is porn in Nepal and India.
            "blue film", "bf video", "sexy video", "desi mms", "desi scandal", "indian mms",
            "mms scandal", "savita bhabhi", "pinay scandal", "phim sex", "phim heo",
            "videos de sexo", "sexo anal", "sexo gratis", "sex filme", "секс видео",
        ]

        // A word that's ordinary alone ("teen", "desi") beside one that isn't.
        let subjects = [
            "teen", "amateur", "homemade", "mature", "granny", "asian", "ebony", "latina",
            "japanese", "korean", "chinese", "indian", "desi", "nepali", "pinay", "arab",
            "lesbian", "gay", "shemale", "stepmom", "step mom", "stepsister", "step sister",
            "step sis", "bbw", "chubby", "big ass", "big tits", "hot", "rough",
            "hardcore", "massage", "cosplay", "hidden cam", "aunty", "bhabhi", "free",
        ]
        let explicit = [
            "sex", "fuck", "fucking", "fucked", "pussy", "cock", "dick", "tits", "cum",
            "squirting", "naked", "orgasm", "anal",
        ]
        for subject in subjects {
            for word in explicit { phrases.append("\(subject) \(word)") }
        }

        // An explicit word beside what it is: "sex video", "dick pics". Words with an
        // ordinary meaning get only the plainly visual ones, since "dick story" is Philip K.
        // Dick, "cock photo" a rooster, and "tits" and "ass" have none at all (birds, Kick-Ass).
        let things = ["video", "movie", "clip", "tube", "pic", "photo", "gif", "gallery", "cam", "chat", "story", "comic", "game"]
        for word in ["sex", "fuck", "fucking", "pussy", "naked", "cum", "squirting", "anal", "orgasm"] {
            for thing in things { phrases.append("\(word) \(thing)") }
        }
        for word in ["cock", "dick"] {
            for thing in ["video", "pic", "gif", "cam", "tube"] { phrases.append("\(word) \(thing)") }
        }

        var seen = Set<String>()
        return phrases.filter { seen.insert($0).inserted }
    }()

    /// Bundle IDs blocked when the list is on. Only installed ones ever matter, so an app
    /// listed here that someone doesn't have costs nothing. iPhone and iPad apps running on
    /// the Mac keep their iOS bundle IDs.
    var builtInApps: [String] {
        switch self {
        case .socialMedia:
            // Feeds only. Chat and calling apps (Discord, WhatsApp, Telegram, Messenger,
            // Viber) are communication tools, not social media (26 Nov 2026, the user's call).
            [
                "com.apple.TV",
                "com.amazon.aiv.AIVApp",
                "com.netflix.Netflix",
                "com.disney.disneyplus",
                "tv.plex.desktop",
                "com.google.ios.youtube",
                "com.burbn.instagram",
                "com.zhiliaoapp.musically",
                "com.atebits.Tweetie2",
                "com.facebook.Facebook",
                "com.reddit.Reddit",
                "com.toyopagroup.picaboo",
                "com.pinterest",
            ]
        case .news:
            ["com.apple.news"]
        case .email:
            [
                "com.apple.mail",
                "com.microsoft.Outlook",
                "com.readdle.SparkDesktop", "com.readdle.smartemail-Mac",
                "it.bloop.airmail2",
                "com.mimestream.Mimestream",
                "com.superhuman.electron",
                "org.mozilla.thunderbird",
                "io.canarymail.mac",
                "ch.protonmail.desktop",
                "com.google.Gmail",
            ]
        case .adult:
            []
        }
    }

    /// Names for the bundled apps, shown when they aren't installed.
    static let appNames: [String: String] = [
        "com.apple.TV": "TV",
        "com.amazon.aiv.AIVApp": "Prime Video",
        "com.netflix.Netflix": "Netflix",
        "com.disney.disneyplus": "Disney+",
        "tv.plex.desktop": "Plex",
        "com.google.ios.youtube": "YouTube",
        "com.burbn.instagram": "Instagram",
        "com.zhiliaoapp.musically": "TikTok",
        "com.atebits.Tweetie2": "X",
        "com.facebook.Facebook": "Facebook",
        "com.reddit.Reddit": "Reddit",
        "com.toyopagroup.picaboo": "Snapchat",
        "com.pinterest": "Pinterest",
        "com.apple.news": "News",
        "com.apple.mail": "Mail",
        "com.microsoft.Outlook": "Microsoft Outlook",
        "com.readdle.SparkDesktop": "Spark",
        "com.readdle.smartemail-Mac": "Spark (classic)",
        "it.bloop.airmail2": "Airmail",
        "com.mimestream.Mimestream": "Mimestream",
        "com.superhuman.electron": "Superhuman",
        "org.mozilla.thunderbird": "Thunderbird",
        "io.canarymail.mac": "Canary Mail",
        "ch.protonmail.desktop": "Proton Mail",
        "com.google.Gmail": "Gmail",
    ]

    /// Lists from older builds, folded into today's. Anything else is dropped.
    private static let renamed: [String: PreMadeList] = [
        "Videos": .socialMedia,
        "Distractions": .socialMedia,
    ]

    static func migrate(_ names: Set<String>) -> Set<String> {
        Set(names.compactMap { name in (PreMadeList(rawValue: name) ?? renamed[name])?.rawValue })
    }
}

/// What someone changed in one list. Stored as differences from the bundled list, so an
/// update that adds a site to the bundle still reaches people who edited it.
struct PreMadeListEdits: Codable, Equatable, Sendable {
    var addedSites: [String] = []
    var removedSites: Set<String> = []
    var addedApps: [String] = []
    var removedApps: Set<String> = []
    var addedWords: [String] = []
    var removedWords: Set<String> = []

    var isEmpty: Bool {
        addedSites.isEmpty && removedSites.isEmpty && addedApps.isEmpty && removedApps.isEmpty
            && addedWords.isEmpty && removedWords.isEmpty
    }

    init() {}

    /// Every key is optional: saves from before words existed have none of the word keys.
    init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        addedSites = try data.decodeIfPresent([String].self, forKey: .addedSites) ?? []
        removedSites = try data.decodeIfPresent(Set<String>.self, forKey: .removedSites) ?? []
        addedApps = try data.decodeIfPresent([String].self, forKey: .addedApps) ?? []
        removedApps = try data.decodeIfPresent(Set<String>.self, forKey: .removedApps) ?? []
        addedWords = try data.decodeIfPresent([String].self, forKey: .addedWords) ?? []
        removedWords = try data.decodeIfPresent(Set<String>.self, forKey: .removedWords) ?? []
    }
}

/// The pre-made lists with the user's edits applied, saved to `lists.json` beside the
/// blocks so they survive restarts. Both processes read it: the dashboard writes, and the
/// enforcement helper notices a new file within a second.
@MainActor
@Observable
final class PreMadeLists {
    static let shared = PreMadeLists()

    private(set) var edits: [String: PreMadeListEdits] = [:]

    /// Every bundled list, decoded the first time something asks for it: the list editor,
    /// which shows each list's sites and counts. Page checks use `catalog(for:)` instead.
    /// Until 26 Nov 2026 the helper loaded all of it (then 29,631 hosts, 6.6 MB, nearly all the
    /// 18+ list) on its first page check, even when no active block included any list.
    var catalog: WebsiteCategoryCatalog {
        if let loadedCatalog { return loadedCatalog }
        let catalog = makeCatalog()
        loadedCatalog = catalog
        return catalog
    }
    @ObservationIgnored private var loadedCatalog: WebsiteCategoryCatalog?
    @ObservationIgnored private let makeCatalog: () -> WebsiteCategoryCatalog
    /// What page checks read: only the bundled lists that active blocks use. See `catalog(for:)`.
    @ObservationIgnored private var lookup: (lists: Set<String>, catalog: WebsiteCategoryCatalog)?
    @ObservationIgnored private let makeLookup: (Set<String>) -> WebsiteCategoryCatalog
    /// Added sites by list, kept as sets so a big import doesn't slow every page check.
    @ObservationIgnored private var addedIndex: [String: Set<String>] = [:]
    /// Every list's words with edits applied, ready for page checks.
    @ObservationIgnored private var wordIndex: [String: WordMatcher] = [:]
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var revision: (inode: UInt64, modified: Int)?
    @ObservationIgnored private var lastCheck = Date.distantPast
    private static let log = Logger(subsystem: AppIdentity.bundleID, category: "PreMadeLists")

    init(
        fileURL: URL? = FenceInstallation.supportDirectory.appending(path: "lists.json"),
        catalog: @autoclosure @escaping () -> WebsiteCategoryCatalog = .shared,
        lookup: @escaping (Set<String>) -> WebsiteCategoryCatalog = { WebsiteCategoryCatalog(only: $0) }
    ) {
        self.fileURL = fileURL
        makeCatalog = catalog
        makeLookup = lookup
        apply([:])
        reload()
    }

    // MARK: Reading

    /// The bundled lists named, indexed for page checks. Rebuilt only when the set of lists in
    /// use changes; while the editor has the full catalog open, that one serves.
    func catalog(for lists: Set<String>) -> WebsiteCategoryCatalog {
        if let loadedCatalog { return loadedCatalog }
        if let lookup, lookup.lists == lists { return lookup.catalog }
        let catalog = makeLookup(lists)
        lookup = (lists, catalog)
        return catalog
    }

    /// Every list a host belongs to, among `lists` (the ones active blocks use). Takes a
    /// lowercase hostname with its www prefix intact.
    func categories(forHost host: String, among lists: Set<String>) -> Set<String> {
        refreshIfDue()
        var matches = catalog(for: lists).categories(forHost: host)
        guard !edits.isEmpty else { return matches }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        for (name, edit) in edits where edit.removedSites.contains(bare) { matches.remove(name) }
        for (name, sites) in addedIndex where sites.contains(bare) { matches.insert(name) }
        return matches
    }

    /// The lists among `lists` with a word in this page's address or title, and the word
    /// each one found. Pass `WebRuleInput.address`, which has the query decoded, so a
    /// search counts too.
    func wordMatches(in address: String, title: String? = nil, among lists: Set<String>) -> [String: String] {
        guard !lists.isEmpty else { return [:] }
        refreshIfDue()
        guard lists.contains(where: { wordIndex[$0] != nil }) else { return [:] }
        let page = WordMatcher.Page(address: address, title: title)
        // Someone looking for help to stop isn't looking for what they're stopping.
        guard page.tokens.isDisjoint(with: WordMatcher.helpWords) else { return [:] }
        var matches: [String: String] = [:]
        for name in lists {
            if let word = wordIndex[name]?.firstMatch(in: page) { matches[name] = word }
        }
        return matches
    }

    /// The bundle IDs, lowercased, that the given lists block.
    func blockedApps(for names: Set<String>) -> Set<String> {
        guard !names.isEmpty else { return [] }
        refreshIfDue()
        var result = Set<String>()
        for name in names {
            guard let list = PreMadeList(rawValue: name) else { continue }
            result.formUnion(apps(in: list).map { $0.lowercased() })
        }
        return result
    }

    func builtInSites(in list: PreMadeList) -> [String] { catalog.domains[list.rawValue] ?? [] }

    /// Sites with edits applied, bundled ones first. Costly for the 18+ list; the editor
    /// only asks for it on the small ones.
    func sites(in list: PreMadeList) -> [String] {
        let edit = edits[list.rawValue] ?? PreMadeListEdits()
        let kept = builtInSites(in: list).filter { !edit.removedSites.contains($0) }
        let bundled = Set(kept)
        return kept + edit.addedSites.filter { !bundled.contains($0) }
    }

    /// Cheap enough to show on every redraw: edits only ever remove bundled sites and add
    /// new ones, so they can be counted without scanning the 18+ list.
    func siteCount(in list: PreMadeList) -> Int {
        let edit = edits[list.rawValue] ?? PreMadeListEdits()
        return builtInSites(in: list).count - edit.removedSites.count + edit.addedSites.count
    }

    func addedSites(in list: PreMadeList) -> [String] { edits[list.rawValue]?.addedSites ?? [] }

    func apps(in list: PreMadeList) -> [String] {
        let edit = edits[list.rawValue] ?? PreMadeListEdits()
        let kept = list.builtInApps.filter { !edit.removedApps.contains($0) }
        return kept + edit.addedApps.filter { !kept.contains($0) }
    }

    /// Words with edits applied, built-in ones first.
    func words(in list: PreMadeList) -> [String] {
        let edit = edits[list.rawValue] ?? PreMadeListEdits()
        let kept = list.builtInWords.filter { !edit.removedWords.contains($0) }
        return kept + edit.addedWords.filter { !kept.contains($0) }
    }

    /// Counted without building the list, as the editor's header does on every redraw.
    func wordCount(in list: PreMadeList) -> Int {
        let edit = edits[list.rawValue] ?? PreMadeListEdits()
        let builtIn = Set(list.builtInWords)
        return builtIn.subtracting(edit.removedWords).count + edit.addedWords.filter { !builtIn.contains($0) }.count
    }

    func addedWords(in list: PreMadeList) -> [String] { edits[list.rawValue]?.addedWords ?? [] }

    func isEdited(_ list: PreMadeList) -> Bool { !(edits[list.rawValue]?.isEmpty ?? true) }

    // MARK: Editing

    /// Sites must be whole sites. Returns why an entry can't be added, or nil once it is.
    @discardableResult
    func addSite(_ entry: String, to list: PreMadeList) -> String? {
        guard let host = Self.host(from: entry) else {
            return "Enter a whole site, like example.com."
        }
        edit(list) { edit, bundled in
            edit.removedSites.remove(host)
            if !bundled.contains(host) && !edit.addedSites.contains(host) { edit.addedSites.append(host) }
        }
        return nil
    }

    /// Adds many at once with one save, as an import does: how many were new, and how many
    /// entries weren't sites at all.
    func addSites(_ entries: [String], to list: PreMadeList) -> (added: Int, skipped: Int) {
        var added = 0
        var skipped = 0
        edit(list) { edit, bundled in
            var present = Set(edit.addedSites)
            for entry in entries {
                guard let host = Self.host(from: entry) else {
                    skipped += 1
                    continue
                }
                if edit.removedSites.remove(host) != nil {
                    added += 1
                } else if !bundled.contains(host) && present.insert(host).inserted {
                    edit.addedSites.append(host)
                    added += 1
                }
            }
        }
        return (added, skipped)
    }

    /// Returns why a word can't be added, or nil once it is.
    @discardableResult
    func addWord(_ entry: String, to list: PreMadeList) -> String? {
        guard let word = Self.word(from: entry) else {
            return "Use a few letters, and not a part every address has, like https."
        }
        reload()
        if words(in: list).contains(word) { return "That one’s already covered." }
        edit(list) { edit, _ in
            if list.builtInWords.contains(word) {
                edit.removedWords.remove(word)
            } else if !edit.addedWords.contains(word) {
                edit.addedWords.append(word)
            }
        }
        return nil
    }

    func removeWord(_ word: String, from list: PreMadeList) {
        edit(list) { edit, _ in
            edit.addedWords.removeAll { $0 == word }
            if list.builtInWords.contains(word) && !list.isSealed { edit.removedWords.insert(word) }
        }
    }

    /// Too short, or in nearly every address, would block everything.
    private static let everywhere: Set<String> = ["http", "https", "http://", "https://", "www", "www.", ".com", "com", "://"]

    /// Three letters at least, or two in scripts like Korean and Chinese where a word can
    /// be that short.
    static func word(from entry: String) -> String? {
        let word = entry.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        let minimum = word.unicodeScalars.allSatisfy(\.isASCII) ? 3 : 2
        guard word.count >= minimum, !everywhere.contains(word), !word.contains("://") else { return nil }
        return word
    }

    func removeSite(_ host: String, from list: PreMadeList) {
        edit(list) { edit, bundled in
            edit.addedSites.removeAll { $0 == host }
            if bundled.contains(host) && !list.isSealed { edit.removedSites.insert(host) }
        }
    }

    /// Replaces the list's apps, as the app picker hands them back.
    func setApps(_ apps: [String], in list: PreMadeList) {
        edit(list) { edit, _ in
            let builtIn = list.builtInApps
            edit.removedApps = Set(builtIn.filter { !apps.contains($0) })
            edit.addedApps = apps.filter { !builtIn.contains($0) }
        }
    }

    func removeApp(_ bundleID: String, from list: PreMadeList) {
        setApps(apps(in: list).filter { $0 != bundleID }, in: list)
    }

    func restoreDefaults(_ list: PreMadeList) {
        guard edits[list.rawValue] != nil else { return }
        var updated = edits
        updated[list.rawValue] = nil
        apply(updated)
        save()
    }

    private func edit(_ list: PreMadeList, _ change: (inout PreMadeListEdits, Set<String>) -> Void) {
        reload()
        var edit = edits[list.rawValue] ?? PreMadeListEdits()
        let bundled = Set(builtInSites(in: list))
        change(&edit, bundled)
        guard edits[list.rawValue] != (edit.isEmpty ? nil : edit) else { return }
        var updated = edits
        updated[list.rawValue] = edit.isEmpty ? nil : edit
        apply(updated)
        save()
    }

    private func apply(_ updated: [String: PreMadeListEdits]) {
        var updated = updated
        // Builds before 26 Nov 2026 let people search the 18+ list and take sites off it.
        for list in PreMadeList.allCases where list.isSealed {
            updated[list.rawValue]?.removedSites = []
            updated[list.rawValue]?.removedWords = []
            if updated[list.rawValue]?.isEmpty == true { updated[list.rawValue] = nil }
        }
        edits = updated
        addedIndex = updated.compactMapValues { $0.addedSites.isEmpty ? nil : Set($0.addedSites) }
        var words: [String: WordMatcher] = [:]
        for list in PreMadeList.allCases {
            let edit = updated[list.rawValue] ?? PreMadeListEdits()
            let matcher = WordMatcher(
                fragments: list.builtInFragments.filter { !edit.removedWords.contains($0) },
                wholeWords: list.builtInWholeWords.filter { !edit.removedWords.contains($0) },
                added: edit.addedWords
            )
            if !matcher.isEmpty { words[list.rawValue] = matcher }
        }
        wordIndex = words
    }

    /// `instagram.com`, `www.instagram.com` and `https://instagram.com/reels` all become
    /// `instagram.com`. A path alone (`/shorts`) isn't a site.
    static func host(from entry: String) -> String? {
        var text = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let host = URL(string: text)?.host(), host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else {
            return nil
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: Persistence

    private func refreshIfDue(now: Date = Date()) {
        guard now.timeIntervalSince(lastCheck) >= 1 else { return }
        lastCheck = now
        reload()
    }

    private func reload() {
        guard let fileURL else { return }
        var info = stat()
        guard stat(fileURL.path, &info) == 0 else {
            if !edits.isEmpty { apply([:]) }
            revision = nil
            return
        }
        let stamp = (inode: UInt64(info.st_ino), modified: info.st_mtimespec.tv_sec)
        guard revision?.inode != stamp.inode || revision?.modified != stamp.modified else { return }
        do {
            let latest = try JSONDecoder().decode([String: PreMadeListEdits].self, from: Data(contentsOf: fileURL))
            if latest != edits { apply(latest) }
            revision = stamp
        } catch {
            Self.log.error("Could not read list edits: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(edits).write(to: fileURL, options: .atomic)
            var info = stat()
            if stat(fileURL.path, &info) == 0 {
                revision = (inode: UInt64(info.st_ino), modified: info.st_mtimespec.tv_sec)
            }
        } catch {
            Self.log.error("Could not save list edits: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Finds a list's words in a page's address and title.
struct WordMatcher: Sendable {
    /// Found anywhere, even inside another word.
    let fragments: [String]
    /// Found only as words of their own, each phrase split into its words, filed under
    /// its first word so a page's words are looked up rather than compared with all 700.
    let phrases: [String: [[String]]]

    /// A page that has any of these as a word of its own isn't matched by words at all:
    /// "how to quit porn" is someone trying to stop, and health, news and reference pages
    /// use the same words for other reasons ("gay sex legislation", "what does nsfw mean").
    /// Known sites are still blocked. Each one has to be rare in 18+ titles, which is why
    /// "doctor", "medical" and "police" aren't here.
    static let helpWords: Set<String> = [
        // Trying to stop.
        "addiction", "addicted", "addict", "recovery", "recover", "quit", "quitting",
        "nofap", "therapy", "therapist", "counseling", "counselling",
        // Health and sex education.
        "health", "healthline", "webmd", "nhs", "mayoclinic", "symptoms", "hiv", "std", "stds",
        "sti", "stis", "contraception", "education", "educator",
        // News, law and looking something up.
        "news", "wikipedia", "offender", "offenders", "trafficking", "harassment", "legislation",
        "lawsuit", "mean", "meaning", "definition",
    ]

    /// The text a page is matched on, lowercased once, and its words.
    struct Page {
        let text: String
        let tokens: Set<String>
        let words: [Substring]

        init(address: String, title: String?) {
            text = (address + "\n" + (title ?? "")).lowercased()
            words = WordMatcher.words(in: text)
            tokens = Set(words.map(String.init))
        }
    }

    /// Someone's own words match anywhere when they're one word, and word by word when
    /// they're a phrase, so "sex video" can't match inside another word.
    init(fragments: [String], wholeWords: [String], added: [String]) {
        let addedPhrases = added.filter { $0.contains(" ") }
        self.fragments = (fragments + added.filter { !$0.contains(" ") }).map { $0.lowercased() }
        var byFirstWord: [String: [[String]]] = [:]
        for phrase in wholeWords + addedPhrases {
            let words = Self.words(in: phrase.lowercased()).map(String.init)
            guard let first = words.first else { continue }
            byFirstWord[first, default: []].append(words)
        }
        phrases = byFirstWord
    }

    var isEmpty: Bool { fragments.isEmpty && phrases.isEmpty }

    func firstMatch(in page: Page) -> String? {
        if let fragment = fragments.first(where: { page.text.contains($0) }) { return fragment }
        let words = page.words
        for start in words.indices {
            // A one-word phrase can be plural too, so "nudes" is looked up as "nude".
            let word = String(words[start])
            let candidates = (phrases[word] ?? []) + (word.hasSuffix("s") ? phrases[String(word.dropLast())] ?? [] : [])
            for phrase in candidates where start + phrase.count <= words.count {
                if zip(phrase.indices, phrase).allSatisfy({ index, expected in
                    let found = words[start + index]
                    // The last word may be plural: "nudes", "sex videos".
                    return found == expected || (index == phrase.count - 1 && found == expected + "s")
                }) {
                    return phrase.joined(separator: " ")
                }
            }
        }
        return nil
    }

    /// Letters and digits between anything else: spaces, - / _ ? = + . and the like.
    static func words(in text: String) -> [Substring] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }
}
