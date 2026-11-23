import Foundation

/// Judges one screen reading against every block that is currently active.
///
/// Explicit block rules take precedence over the title-based drift hint.
struct BlockEvaluator {
    /// Only blocks that are active right now. The caller does the schedule maths.
    var blocks: [Block]
    /// Words that merely suggest drift. These nudge, they never block.
    var driftKeywords: [String]

    /// System apps Shift leaves available so users can manage the Mac.
    private static let neverBlocked: Set<String> = [
        "com.apple.finder",
        "com.apple.systempreferences",
        "com.apple.systemsettings",
        "com.apple.loginwindow",
        (Bundle.main.bundleIdentifier ?? "com.beingpax.Shift").lowercased(),
    ]

    @MainActor
    func ruleVerdict(for context: ScreenContext) -> Verdict? {
        if Self.neverBlocked.contains(context.bundleID.lowercased()) {
            return .allow("\(context.appName) is never blocked")
        }

        let address = context.websiteAddress
        let input = context.url.flatMap(WebRuleInput.init(url:))
        var categories: Set<String> = []
        if let input, blocks.contains(where: { !$0.list.categoryNames.isEmpty || !$0.list.exceptionCategoryNames.isEmpty }) {
            let catalog = WebsiteCategoryCatalog.shared
            categories = catalog.categories(forHost: input.host)
            if input.matchesAdultSearch(in: catalog) { categories.insert(BlockList.adultSitesCategory) }
        }
        var firstPause: Verdict?

        for block in blocks {
            let list = block.list
            var website = address
            if let address, let input {
                // An exception waives only this block's website rules. Its app rules still apply.
                if list.exempts(address, input: input, categories: categories) {
                    website = nil
                } else {
                    let reason: String?
                    if list.categoryNames.contains(BlockList.adultSitesCategory) && categories.contains(BlockList.adultSitesCategory) {
                        reason = "Adult content filter matched"
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
            let bundleID = context.bundleID.lowercased()
            guard list.apps.contains(where: { bundleID == $0.lowercased() }) else { return nil }
            target = .app(bundleID)
            name = context.appName
        }

        return Verdict(
            kind: .block,
            reason: "\(name) is blocked",
            blockID: block.id,
            blockName: block.name,
            ruleTarget: target
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
    func exempts(_ address: WebsiteAddress, input: WebRuleInput, categories: Set<String>) -> Bool {
        if !exceptionCategoryNames.isDisjoint(with: categories) { return true }
        return websiteExceptions.contains { exception in
            switch exception.rule {
            case .address(let allowed): allowed.matches(address)
            case .text(let allowed): input.matches(allowed)
            }
        }
    }
}
