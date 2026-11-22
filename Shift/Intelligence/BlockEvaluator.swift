import Foundation

/// Judges one screen reading against every block that is currently active.
///
/// Explicit block rules take precedence over focus and title-based nudges.
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

    func ruleVerdict(for context: ScreenContext) -> Verdict? {
        if Self.neverBlocked.contains(context.bundleID.lowercased()) {
            return .allow("\(context.appName) is never blocked")
        }

        let website = context.websiteAddress
        for block in blocks {
            if let verdict = ruleMatch(context, website: website, against: block) {
                return verdict
            }
        }

        return nil
    }

    func intentGoals() -> [IntentGoal] {
        blocks.compactMap { block in
            let goal = String(block.goal.prefix(400)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !goal.isEmpty else { return nil }
            return IntentGoal(id: block.id, text: goal)
        }
    }

    func fallbackVerdict(for context: ScreenContext, hasIntentGoals: Bool) -> Verdict {
        if hasIntentGoals { return .allow("No blocking rule matched. No clear distraction detected.") }
        if let title = context.windowTitle,
           let keyword = driftKeywords.first(where: { title.localizedCaseInsensitiveContains($0) }) {
            return .nudge("“\(keyword)” looks like a feed")
        }

        return .allow("No blocking rule matched")
    }

    private func ruleMatch(_ context: ScreenContext, website: WebsiteAddress?, against block: Block) -> Verdict? {
        let list = block.list
        let target: RuleTarget
        let name: String

        let matchingRules = website.map { address in
            // Older onboarding data can have a URL stored in the other list.
            (list.paths + list.hosts).compactMap { entry -> (entry: String, rule: WebsiteAddress)? in
                guard let rule = WebsiteAddress(entry: entry), rule.matches(address) else { return nil }
                return (entry, rule)
            }
        } ?? []
        if let path = matchingRules.first(where: { !$0.rule.isDomainOnly }) {
            target = .path(path.entry)
            name = path.entry
        } else if let domain = matchingRules.first {
            target = .website(domain.entry.lowercased())
            name = domain.entry
        } else if list.apps.contains(where: { context.bundleID.lowercased() == $0.lowercased() }) {
            target = .app(context.bundleID.lowercased())
            name = context.appName
        } else {
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
}
