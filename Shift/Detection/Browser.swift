import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os.log

/// Browser identities and Apple Events for closing tabs.
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

    var isChromium: Bool {
        switch self {
        case .chrome, .arc, .brave, .edge: true
        case .safari, .firefox: false
        }
    }

    /// Firefox exposes no scripting dictionary for closing tabs.
    var supportsAppleEvents: Bool { self != .firefox }

    private var closeTabScript: String {
        let tab = self == .safari ? "current tab" : "active tab"
        return """
        with timeout of 2 seconds
            tell application id "\(bundleID)" to close \(tab) of front window
        end timeout
        return "closed"
        """
    }

    func closeFrontTab(pid: pid_t) async -> Bool {
        if supportsAppleEvents { return await AppleScriptRunner.run(closeTabScript) == "closed" }

        // Firefox has no tab scripting dictionary. Target its process directly, and
        // require Accessibility so the shortcut can be delivered to that process.
        guard PermissionsManager.isAccessibilityTrusted,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_W), keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_W), keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }
}

/// Runs AppleScript off the main thread on one serial queue, with a deadline.
enum AppleScriptRunner {
    private static let log = Logger(subsystem: "com.beingpax.Shift", category: "AppleScript")

    /// Serial on purpose: `NSAppleScript` is not safe to use concurrently, and serialising
    /// also stops a backlog of events piling onto a slow browser.
    private static let queue = DispatchQueue(label: "com.beingpax.Shift.applescript", qos: .utility)

    private static let deadline: DispatchTimeInterval = .seconds(3)

    @discardableResult
    static func run(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            // The continuation must fire exactly once, whether the script finishes,
            // fails, or outlives its deadline.
            let state = ResumeOnce(continuation)

            queue.async {
                guard state.isPending else { return }
                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    state.resume(with: nil)
                    return
                }
                let result = script.executeAndReturnError(&error)
                if error != nil {
                    log.debug("Browser tab action failed")
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

        var isPending: Bool {
            lock.lock()
            defer { lock.unlock() }
            return continuation != nil
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
