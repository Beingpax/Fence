import CryptoKit
import Foundation

enum StrikeTarget: Sendable, Equatable {
    case website(String)
    case path(String)
    case app(String)

    fileprivate var identifier: String {
        switch self {
        case .website(let host): "website:\(host)"
        case .path(let path): "path:\(path)"
        case .app(let bundleID): "app:\(bundleID)"
        }
    }
}

/// Counts repeat detections for the current calendar day. Stored keys omit raw domains and paths.
struct DailyStrikeCounts: Codable {
    private var day: Date?
    private var counts: [String: Int] = [:]

    mutating func record(_ target: StrikeTarget, blockID: UUID?, now: Date) -> Int {
        if day.map({ Calendar.current.isDate($0, inSameDayAs: now) }) != true {
            day = now
            counts.removeAll()
        }
        let identifier = "\(blockID?.uuidString ?? "unassigned")|\(target.identifier)"
        let key = Data(SHA256.hash(data: Data(identifier.utf8))).base64EncodedString()
        counts[key, default: 0] += 1
        return counts[key, default: 0]
    }
}

struct ShieldPolicy: Equatable {
    enum Level: String {
        case gentle = "Gentle"
        case firm = "Firm"
        case severe = "Severe"

        var symbol: String {
            switch self {
            case .gentle: "hand.raised.fill"
            case .firm: "hand.raised.slash.fill"
            case .severe: "exclamationmark.shield.fill"
            }
        }
    }

    let level: Level

    var countdownSeconds: Int {
        switch level {
        case .gentle: 0
        case .firm: 15
        case .severe: 30
        }
    }

    var requiresPhrase: Bool { level == .severe }

    static let phrase = "I am choosing to get distracted"

    static func make(strike: Int) -> ShieldPolicy {
        switch strike {
        case ...1: ShieldPolicy(level: .gentle)
        case 2: ShieldPolicy(level: .firm)
        default: ShieldPolicy(level: .severe)
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
    /// Length of the break available from this shield.
    var breakMinutes: Int?
    /// Demo shields from the menu bar don't touch any real app.
    var isPreview: Bool = false

    var primaryActionTitle: String {
        isBrowser ? "Close this tab" : "Quit \(appName)"
    }
}

enum ShieldResolution: Equatable {
    case closeTab
    case forceQuit
    case takeBreak
}
