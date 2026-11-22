import Foundation

/// Judges one screen reading against every block that is currently active.
///
/// This is tier 0: deterministic, instant, and the only tier that exists today. It is a
/// pure value type with no state, so it can run anywhere and is trivial to reason about.
struct BlockEvaluator {
    /// Only blocks that are active right now. The caller does the schedule maths.
    var blocks: [Block]
    /// Words that merely suggest drift. These nudge, they never block.
    var driftKeywords: [String]

    /// Apps Shift refuses to block under any configuration, so a bad allow-list can
    /// never lock someone out of fixing it.
    private static let neverBlocked: Set<String> = [
        "com.apple.finder",
        "com.apple.systempreferences",
        "com.apple.systemsettings",
        "com.apple.loginwindow",
        Bundle.main.bundleIdentifier ?? "com.beingpax.Shift",
    ]

    func evaluate(_ context: ScreenContext, now: Date = Date()) -> Verdict {
        if Self.neverBlocked.contains(context.bundleID.lowercased()) {
            return .allow("\(context.appName) is never blocked")
        }

        for block in blocks {
            if let verdict = judge(context, against: block) {
                return verdict
            }
        }

        if let title = context.windowTitle,
           let keyword = driftKeywords.first(where: { title.localizedCaseInsensitiveContains($0) }) {
            return .nudge("“\(keyword)” looks like a feed")
        }

        return .allow()
    }

    /// Returns a verdict only when this block has an opinion; nil means "no comment".
    private func judge(_ context: ScreenContext, against block: Block) -> Verdict? {
        if matchesException(context, block.list) { return nil }
        guard let reason = blockedReason(context, block.list) else { return nil }
        return verdict(reason: reason, for: block)
    }

    private func verdict(reason: String, for block: Block) -> Verdict {
        Verdict(
            kind: .block,
            reason: reason,
            confidence: 0.95,
            blockID: block.id,
            blockName: block.name,
            friction: block.friction,
            goal: block.goal
        )
    }

    // MARK: Matching

    private func matchesException(_ context: ScreenContext, _ list: BlockList) -> Bool {
        list.exceptions.contains { entry in
            matchesEntry(context, entry: entry)
        }
    }

    private func matchesEntry(_ context: ScreenContext, entry: String) -> Bool {
        let needle = entry.lowercased()
        if needle.contains("/") {
            return context.hostAndPath?.hasPrefix(needle) ?? false
        }
        if needle.contains(".") {
            guard let host = context.host else { return false }
            return host == needle || host.hasSuffix("." + needle)
        }
        return context.bundleID.lowercased() == needle
    }

    /// The first concrete reason this block objects, or nil.
    private func blockedReason(_ context: ScreenContext, _ list: BlockList) -> String? {
        if let hostAndPath = context.hostAndPath,
           let path = list.paths.first(where: { hostAndPath.hasPrefix($0.lowercased()) }) {
            return "\(path) is blocked"
        }

        if let host = context.host,
           let matched = list.hosts.first(where: { host == $0.lowercased() || host.hasSuffix("." + $0.lowercased()) }) {
            return "\(matched) is blocked"
        }

        if list.apps.contains(where: { context.bundleID.lowercased() == $0.lowercased() }) {
            return "\(context.appName) is blocked"
        }

        return nil
    }
}
