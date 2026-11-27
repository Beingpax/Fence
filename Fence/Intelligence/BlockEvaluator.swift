import Foundation

/// Judges one screen reading against every block that is currently active.
///
/// Explicit block rules take precedence over the title-based drift hint.
struct BlockEvaluator {
    /// Only blocks that are active right now. The caller does the schedule maths.
    var blocks: [Block]
    /// Words that merely suggest drift. These nudge, they never block.
    var driftKeywords: [String]

    /// System apps Fence leaves available so users can manage the Mac.
    /// Every Fence build is on it too, release and dev, so neither can block the other.
    private static let neverBlocked: Set<String> = Set([
        "com.apple.finder",
        "com.apple.systempreferences",
        "com.apple.systemsettings",
        "com.apple.loginwindow",
    ] + AppIdentity.ownBundleIDs.map { $0.lowercased() })

    @MainActor
    func ruleVerdict(for context: ScreenContext) -> Verdict? {
        if Self.neverBlocked.contains(context.bundleID.lowercased()) {
            return .allow("\(context.appName) is never blocked")
        }

        // A blocked app outranks every page inside it, in any active block. Arc on x.com,
        // with both Arc and x.com blocked, quits Arc: closing the one tab would leave a
        // blocked app open, only to pause again on whatever tab came next.
        // Pre-made lists carry apps too, with the user's edits.
        let lists = PreMadeLists.shared
        for block in blocks {
            if let verdict = appMatch(context, in: block, listApps: lists.blockedApps(for: block.list.categoryNames)) {
                return verdict
            }
        }

        let address = context.websiteAddress
        let input = context.url.flatMap(WebRuleInput.init(url:))
        var categories: Set<String> = []
        /// A pre-made list's word found in the address, by list.
        var wordMatches: [String: String] = [:]
        if let input, blocks.contains(where: { !$0.list.categoryNames.isEmpty }) {
            // Only the lists these blocks use are loaded and searched.
            let inUse = blocks.reduce(into: Set<String>()) { $0.formUnion($1.list.categoryNames) }
            categories = lists.categories(forHost: input.host, among: inUse)
            wordMatches = lists.wordMatches(in: input.address, title: context.windowTitle, among: inUse)
            if inUse.contains(BlockList.adultSitesCategory),
               input.matchesAdultSearch(in: lists.catalog(for: inUse)) {
                categories.insert(BlockList.adultSitesCategory)
            }
        }
        var firstPause: Verdict?

        for block in blocks {
            let list = block.list
            var website = address
            if let address, let input {
                // An exception waives only this block's website rules. Its app rules still apply.
                if list.exempts(address, input: input) {
                    website = nil
                } else {
                    let reason: String?
                    if list.categoryNames.contains(BlockList.adultSitesCategory) && categories.contains(BlockList.adultSitesCategory) {
                        reason = "Adult content filter matched"
                    } else if let word = list.categoryNames.sorted().lazy.compactMap({ wordMatches[$0] }).first {
                        // Like a keyword: the tab closes, since the word, not the site, is the problem.
                        reason = "“\(word)” in the address or title"
                    } else {
                        reason = list.textRules.first(where: input.matches).map { "\($0.scope.title) “\($0.text)”" }
                    }
                    if let reason {
                        return Verdict(kind: .block, reason: reason, blockID: block.id, blockName: block.name, closesTab: true)
                    }
                }
            }
            if firstPause == nil {
                firstPause = ruleMatch(context, website: website, categories: categories, against: block)
            }
        }
        return firstPause
    }

    func fallbackVerdict(for context: ScreenContext) -> Verdict {
        if let title = context.windowTitle,
           let keyword = driftKeywords.first(where: { title.localizedCaseInsensitiveContains($0) }) {
            return .nudge("“\(keyword)” looks like a feed")
        }

        return .allow("No blocking rule matched")
    }

    private func ruleMatch(_ context: ScreenContext, website: WebsiteAddress?, categories: Set<String>, against block: Block) -> Verdict? {
        let list = block.list
        let target: RuleTarget
        let name: String

        if let website, let match = matchingWebsiteRule(for: website, in: list) {
            target = match.target
            name = match.name
        } else if let website, !list.categoryNames.isDisjoint(with: categories) {
            target = .website(website.host)
            name = website.host
        } else {
            // App rules were settled before any block's websites were looked at.
            return nil
        }

        return Verdict(
            kind: .block,
            reason: "\(name) is blocked",
            blockID: block.id,
            blockName: block.name,
            ruleTarget: target
        )
    }

    /// The app itself is on this block's list, or on a pre-made list the block includes.
    /// Website exceptions never waive it.
    private func appMatch(_ context: ScreenContext, in block: Block, listApps: Set<String>) -> Verdict? {
        let bundleID = context.bundleID.lowercased()
        guard listApps.contains(bundleID) || block.list.apps.contains(where: { bundleID == $0.lowercased() }) else {
            return nil
        }
        return Verdict(
            kind: .block,
            reason: "\(context.appName) is blocked",
            blockID: block.id,
            blockName: block.name,
            ruleTarget: .app(bundleID)
        )
    }

    private func matchingWebsiteRule(for address: WebsiteAddress, in list: BlockList) -> (target: RuleTarget, name: String)? {
        var firstDomain: String?
        // Older data can store paths and domains in either list. Paths take precedence.
        for entries in [list.paths, list.hosts] {
            for entry in entries {
                guard let rule = WebsiteAddress(entry: entry), rule.matches(address) else { continue }
                if !rule.isDomainOnly { return (.path(entry), entry) }
                if firstDomain == nil { firstDomain = entry }
            }
        }
        return firstDomain.map { (.website($0.lowercased()), $0) }
    }
}

private extension BlockList {
    /// Only single pages and patterns can be allowed. Pre-made lists never can (26 Nov 2026).
    func exempts(_ address: WebsiteAddress, input: WebRuleInput) -> Bool {
        websiteExceptions.contains { exception in
            switch exception.rule {
            case .address(let allowed): allowed.matches(address)
            case .text(let allowed): input.matches(allowed)
            }
        }
    }
}
