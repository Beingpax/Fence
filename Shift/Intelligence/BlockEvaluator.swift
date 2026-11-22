import Foundation

/// Judges one screen reading against every block that is currently active.
///
/// Tier 0 is deterministic and runs before intent detection.
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

        for block in blocks {
            if let verdict = ruleMatch(context, against: block) {
                return verdict
            }
        }

        return nil
    }

    func intentGoals() -> [IntentGoal] {
        blocks.compactMap { block in
            let goal = String(block.goal.prefix(400)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !goal.isEmpty else { return nil }
            return IntentGoal(id: block.id, name: block.name, text: goal)
        }
    }

    func fallbackVerdict(for context: ScreenContext, hasIntentGoals: Bool = false) -> Verdict {
        if let title = context.windowTitle,
           let keyword = driftKeywords.first(where: { title.localizedCaseInsensitiveContains($0) }) {
            return .nudge("“\(keyword)” looks like a feed")
        }

        return .allow(hasIntentGoals ? "No blocking rule matched. Intent could not be confirmed." : "No blocking rule matched")
    }

    private func ruleMatch(_ context: ScreenContext, against block: Block) -> Verdict? {
        let list = block.list
        let target: StrikeTarget
        let name: String

        if let hostAndPath = context.hostAndPath,
           let path = list.paths.first(where: { hostAndPath.hasPrefix($0.lowercased()) }) {
            target = .path(path.lowercased())
            name = path
        } else if let host = context.host,
                  let domain = list.hosts.first(where: {
                      let rule = $0.lowercased()
                      return host == rule || host.hasSuffix("." + rule)
                  }) {
            target = .website(domain.lowercased())
            name = domain
        } else if list.apps.contains(where: { context.bundleID.lowercased() == $0.lowercased() }) {
            target = .app(context.bundleID.lowercased())
            name = context.appName
        } else {
            return nil
        }

        return Verdict(
            kind: .block,
            reason: "\(name) is blocked",
            confidence: 0.95,
            blockID: block.id,
            blockName: block.name,
            ruleTarget: target,
            goal: block.goal
        )
    }
}
