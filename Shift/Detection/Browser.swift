import Foundation
import os.log

/// Browsers Shift can read URLs from and close tabs in, via Apple Events.
///
/// Apple Events are synchronous round trips to another process and can take hundreds of
/// milliseconds, or hang outright if the browser is busy. They therefore never run on the
/// main actor. `AppleScriptRunner` owns a serial queue for them and gives callers a
/// deadline, so a wedged browser costs one sample rather than the whole UI.
enum Browser: String, CaseIterable, Sendable {
    case safari, chrome, arc, brave, edge, firefox

    init?(bundleID: String) {
        guard let match = Self.allCases.first(where: { $0.bundleID == bundleID }) else { return nil }
        self = match
    }

    var bundleID: String {
        switch self {
        case .safari: "com.apple.Safari"
        case .chrome: "com.google.Chrome"
        case .arc: "company.thebrowser.Browser"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        case .firefox: "org.mozilla.firefox"
        }
    }

    var displayName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .arc: "Arc"
        case .brave: "Brave"
        case .edge: "Edge"
        case .firefox: "Firefox"
        }
    }

    /// Firefox exposes no usable scripting dictionary for tabs, so it is read from the
    /// window title only and its tabs can't be closed individually.
    var supportsAppleEvents: Bool { self != .firefox }

    private var urlScript: String? {
        guard supportsAppleEvents else { return nil }
        switch self {
        case .safari:
            return "tell application id \"\(bundleID)\" to return URL of current tab of front window"
        default:
            return "tell application id \"\(bundleID)\" to return URL of active tab of front window"
        }
    }

    private var closeTabScript: String? {
        guard supportsAppleEvents else { return nil }
        switch self {
        case .safari:
            return "tell application id \"\(bundleID)\" to close current tab of front window"
        default:
            return "tell application id \"\(bundleID)\" to close active tab of front window"
        }
    }

    /// The front tab's URL. Triggers the macOS Automation prompt the first time per browser.
    func currentURL() async -> URL? {
        guard let urlScript else { return nil }
        guard let string = await AppleScriptRunner.run(urlScript), !string.isEmpty else { return nil }
        return URL(string: string)
    }

    func closeFrontTab() async {
        guard let closeTabScript else { return }
        _ = await AppleScriptRunner.run(closeTabScript)
    }
}

/// Runs AppleScript off the main thread on one serial queue, with a deadline.
enum AppleScriptRunner {
    private static let log = Logger(subsystem: "com.beingpax.Shift", category: "AppleScript")

    /// Serial on purpose: `NSAppleScript` is not safe to use concurrently, and serialising
    /// also stops a backlog of events piling onto a slow browser.
    private static let queue = DispatchQueue(label: "com.beingpax.Shift.applescript", qos: .utility)

    /// Beyond this, we give up waiting and let detection fall back to the window title.
    private static let deadline: DispatchTimeInterval = .milliseconds(1500)

    @discardableResult
    static func run(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            // The continuation must fire exactly once, whether the script finishes,
            // fails, or outlives its deadline.
            let state = ResumeOnce(continuation)

            queue.async {
                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    state.resume(with: nil)
                    return
                }
                let result = script.executeAndReturnError(&error)
                if let error {
                    log.debug("AppleScript failed: \(error.description, privacy: .public)")
                    state.resume(with: nil)
                    return
                }
                state.resume(with: result.stringValue)
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + deadline) {
                state.resume(with: nil)
            }
        }
    }

    /// Guards a continuation so the first caller wins and later ones are ignored.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<String?, Never>?

        init(_ continuation: CheckedContinuation<String?, Never>) {
            self.continuation = continuation
        }

        func resume(with value: String?) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }
}
