import AppKit
import Foundation
import os.log

/// The headless half of the watchdog pair. Entered only via `Shift --watchdog`.
///
/// It never shows UI and never touches the user's data. Its whole job, while a Locked
/// session is running, is:
///   1. relaunch Shift if the UI process is gone (force quit, `kill`, crash), and
///   2. put the app bundle back if it was dragged to the Trash.
///
/// `KeepAlive` in the launch agent brings it back if it is killed during a lock.
/// The app unloads the agent when the last lock ends. The agent can also unload itself
/// if the lock expires while the app is unavailable.
///
/// Honesty, per the PRD: `kill -9` on both processes at once, or deleting the bundle while
/// unlocked, still wins. Shift sells friction, not a prison.
enum WatchdogRunner {
    private static let log = Logger(subsystem: "com.beingpax.Shift", category: "Watchdog")

    /// How often to check. Two seconds is responsive enough to feel instant, and cheap
    /// enough to be invisible: one small file read per tick.
    private static let pollInterval: TimeInterval = 2
    /// Don't hammer launch attempts if something is wrong.
    private static let relaunchCooldown: TimeInterval = 5

    /// Single-threaded by construction: only `run()`'s loop touches this.
    nonisolated(unsafe) private static var lastRelaunch: Date = .distantPast

    /// Never returns.
    static func run() -> Never {
        log.info("Watchdog started (pid \(getpid())).")

        // The watchdog must not die quietly when something tries to shut it down politely.
        // launchd would restart it anyway; ignoring the signal just makes that instant.
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)

        while true {
            tick()
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }

    private static func tick() {
        guard let state = GuardState.load(), state.isActive else {
            if !isShiftRunning(), GuardState.load()?.isActive != true {
                signal(SIGTERM, SIG_DFL)
                WatchdogService.remove()
                exit(EXIT_SUCCESS)
            }
            return
        }

        restoreBundleIfTrashed(expectedPath: state.bundlePath)

        guard !isShiftRunning() else { return }
        guard Date().timeIntervalSince(lastRelaunch) > relaunchCooldown else { return }

        relaunch(bundlePath: state.bundlePath, goal: state.goal)
    }

    // MARK: Is the UI alive?

    private static func isShiftRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let mine = getpid()
        return NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == bundleID && app.processIdentifier != mine
        }
    }

    // MARK: Relaunch

    private static func relaunch(bundlePath: String, goal: String) {
        let url = URL(fileURLWithPath: bundlePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            log.error("Shift is gone from \(bundlePath, privacy: .public); cannot relaunch.")
            return
        }

        lastRelaunch = Date()
        log.info("Shift is not running during a locked session (\(goal, privacy: .private)); relaunching.")

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                log.error("Relaunch failed: \(error.localizedDescription, privacy: .public). Falling back to open(1).")
                openViaCommandLine(url)
            }
        }
    }

    private static func openViaCommandLine(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", url.path]
        try? process.run()
    }

    // MARK: Tamper recovery

    /// If the bundle vanished from where the lock started, look for it in the Trash and
    /// put it back. This is the "can't uninstall during a lock" guarantee in PRD §9.
    private static func restoreBundleIfTrashed(expectedPath: String) {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: expectedPath) else { return }

        let trash = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".Trash", directoryHint: .isDirectory)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: trash,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        ) else { return }

        let expectedName = URL(fileURLWithPath: expectedPath).lastPathComponent
        // Finder renames duplicates ("Shift 2.app"), so match on the stem rather than the whole name.
        let stem = (expectedName as NSString).deletingPathExtension
        let candidate = entries.first { entry in
            entry.pathExtension == "app" && entry.lastPathComponent.hasPrefix(stem)
        }

        guard let candidate else { return }

        do {
            try fileManager.moveItem(at: candidate, to: URL(fileURLWithPath: expectedPath))
            log.info("Restored Shift from the Trash during a locked session.")
        } catch {
            log.error("Could not restore Shift from the Trash: \(error.localizedDescription, privacy: .public)")
        }
    }
}
