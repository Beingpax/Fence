import Foundation

/// Tier 0: deterministic rules. Decides the clear cases instantly.
struct RuleBasedClassifier: DistractionClassifier {
    var rules: BlockRules

    func classify(_ context: ScreenContext, session: FocusSession) -> Verdict {
        let goal = session.goal

        // 1. Work apps are never blocked.
        if rules.alwaysAllowedApps.contains(context.bundleID) {
            return .allow("\(context.appName) is a work app")
        }

        // 2. Things the user already marked "wrong call" this session.
        if let host = context.host, session.allowances.contains(host) {
            return .allow("You allowed \(host) this session")
        }
        if session.allowances.contains(context.bundleID) {
            return .allow("You allowed \(context.appName) this session")
        }

        // 3. Path-aware rules: block part of a site, keep the rest.
        if let hostAndPath = context.hostAndPath,
           let path = rules.blockedPaths.first(where: { hostAndPath.hasPrefix($0.lowercased()) }) {
            return .block("\(path) isn't part of “\(goal)”")
        }

        // 4. Whole sites (subdomains included).
        if let host = context.host,
           let blocked = rules.blockedHosts.first(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return .block("\(blocked) isn't part of “\(goal)”")
        }

        // 5. Native apps.
        if rules.blockedApps.contains(context.bundleID) {
            return .block("\(context.appName) isn't part of “\(goal)”")
        }

        // 6. Soft signals only nudge. The AI tier will resolve these.
        if let title = context.windowTitle,
           let keyword = rules.nudgeTitleKeywords.first(where: { title.localizedCaseInsensitiveContains($0) }) {
            return .nudge("“\(keyword)” looks like a feed")
        }

        return .allow()
    }
}
