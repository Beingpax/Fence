import Foundation

/// How much friction a shield applies, escalating by strike (PRD §9).
struct ShieldPolicy: Equatable {
    var countdownSeconds: Int
    var requiresPhrase: Bool

    static let phrase = "I am choosing to get distracted"

    static func make(strictness: Strictness, strike: Int) -> ShieldPolicy {
        switch strictness {
        case .gentle:
            return ShieldPolicy(countdownSeconds: 0, requiresPhrase: false)
        case .firm:
            switch strike {
            case ...1: return ShieldPolicy(countdownSeconds: 0, requiresPhrase: false)
            case 2: return ShieldPolicy(countdownSeconds: 15, requiresPhrase: false)
            default: return ShieldPolicy(countdownSeconds: 15, requiresPhrase: true)
            }
        case .locked:
            switch strike {
            case ...1: return ShieldPolicy(countdownSeconds: 10, requiresPhrase: false)
            case 2: return ShieldPolicy(countdownSeconds: 30, requiresPhrase: false)
            default: return ShieldPolicy(countdownSeconds: 30, requiresPhrase: true)
            }
        }
    }
}

/// Everything the shield needs to render and act.
struct ShieldRequest: Equatable {
    var appName: String
    var bundleID: String
    var processID: pid_t
    var host: String?
    var isBrowser: Bool
    var reason: String
    var goal: String
    var strike: Int
    var policy: ShieldPolicy
    /// Demo shields from the menu bar don't touch any real app.
    var isPreview: Bool = false

    var primaryActionTitle: String {
        isBrowser ? "Close this tab" : "Force quit \(appName)"
    }
}

enum ShieldResolution {
    case closeTab
    case forceQuit
    case wrongCall
}
