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
        case .adult: "Known 18+ sites and explicit searches"
        }
    }

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

    var isEmpty: Bool { addedSites.isEmpty && removedSites.isEmpty && addedApps.isEmpty && removedApps.isEmpty }
}

/// The pre-made lists with the user's edits applied, saved to `lists.json` beside the
/// blocks so they survive restarts. Both processes read it: the dashboard writes, and the
/// enforcement helper notices a new file within a second.
@MainActor
@Observable
final class PreMadeLists {
    static let shared = PreMadeLists()

    private(set) var edits: [String: PreMadeListEdits] = [:]

    @ObservationIgnored let catalog: WebsiteCategoryCatalog
    /// Added sites by list, kept as sets so a big import doesn't slow every page check.
    @ObservationIgnored private var addedIndex: [String: Set<String>] = [:]
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var revision: (inode: UInt64, modified: Int)?
    @ObservationIgnored private var lastCheck = Date.distantPast
    private static let log = Logger(subsystem: "com.beingpax.Shift", category: "PreMadeLists")

    init(
        fileURL: URL? = ShiftInstallation.supportDirectory.appending(path: "lists.json"),
        catalog: WebsiteCategoryCatalog = .shared
    ) {
        self.fileURL = fileURL
        self.catalog = catalog
        reload()
    }

    // MARK: Reading

    /// Every list a host belongs to. Takes a lowercase hostname with its www prefix intact.
    func categories(forHost host: String) -> Set<String> {
        refreshIfDue()
        var matches = catalog.categories(forHost: host)
        guard !edits.isEmpty else { return matches }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        for (name, edit) in edits where edit.removedSites.contains(bare) { matches.remove(name) }
        for (name, sites) in addedIndex where sites.contains(bare) { matches.insert(name) }
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

    func isEdited(_ list: PreMadeList) -> Bool { !(edits[list.rawValue]?.isEmpty ?? true) }

    // MARK: Editing

    /// Lists hold whole sites. Returns why an entry can't be added, or nil once it is.
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

    func removeSite(_ host: String, from list: PreMadeList) {
        edit(list) { edit, bundled in
            edit.addedSites.removeAll { $0 == host }
            if bundled.contains(host) { edit.removedSites.insert(host) }
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
        edits = updated
        addedIndex = updated.compactMapValues { $0.addedSites.isEmpty ? nil : Set($0.addedSites) }
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
