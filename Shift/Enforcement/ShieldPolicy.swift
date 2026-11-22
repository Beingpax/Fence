import Foundation

/// How much friction a shield applies, escalating by strike.
///
/// Friction is about the moment you hit a block. Whether you can switch the block off at
/// all is a separate question, answered by the block's lock.
struct ShieldPolicy: Equatable {
    var countdownSeconds: Int
    var requiresPhrase: Bool

    static let phrase = "I am choosing to get distracted"

    static func make(friction: Friction, strike: Int) -> ShieldPolicy {
        switch friction {
        case .gentle:
            return ShieldPolicy(countdownSeconds: 0, requiresPhrase: false)
        case .firm:
            switch strike {
            case ...1: return ShieldPolicy(countdownSeconds: 0, requiresPhrase: false)
            case 2: return ShieldPolicy(countdownSeconds: 15, requiresPhrase: false)
            default: return ShieldPolicy(countdownSeconds: 15, requiresPhrase: true)
            }
        case .severe:
            switch strike {
            case ...1: return ShieldPolicy(countdownSeconds: 10, requiresPhrase: false)
            case 2: return ShieldPolicy(countdownSeconds: 30, requiresPhrase: true)
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
    /// The block responsible, shown so the user knows which rule they set is biting.
    var blockName: String
    var blockID: UUID?
    /// The block's intent sentence, when it has one.
    var goal: String
    var strike: Int
    var policy: ShieldPolicy
    /// Whether the block offers breaks, and whether one is still available.
    var offersBreak: Bool = false
    /// Demo shields from the menu bar don't touch any real app.
    var isPreview: Bool = false

    var primaryActionTitle: String {
        isBrowser ? "Close this tab" : "Quit \(appName)"
    }
}

enum ShieldResolution: Equatable {
    case closeTab
    case forceQuit
    case wrongCall
    case takeBreak
}
