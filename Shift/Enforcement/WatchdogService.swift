import Foundation
import os.log

/// Installs and removes the watchdog launch agent (the UI side of the pair).
///
/// Why a launch agent rather than a child process: launchd owns the lifecycle, so the
/// watchdog survives the UI being force quit, survives being killed itself (`KeepAlive`),
/// and comes back after a reboot. A child process would die with its parent, which is
/// exactly the case we need to defend against.
///
/// Why `launchctl` rather than `SMAppService.agent`: `SMAppService.agent(plistName:)`
/// requires the plist to be bundled at `Contents/Library/LaunchAgents/`, which needs a
/// Copy Files build phase in the Xcode project. The project uses folder-synced groups and
/// CLAUDE.md says not to hand-edit file references, so the agent is installed into
/// `~/Library/LaunchAgents` at runtime instead. Migrating to `SMAppService.agent` later is
/// a drop-in replacement for `install()` and `remove()`.
enum WatchdogService {
    static let label = "com.beingpax.Shift.watchdog"
    /// Argument that puts the binary into headless watchdog mode. See `main.swift`.
    static let modeFlag = "--watchdog"

    private static let log = Logger(subsystem: "com.beingpax.Shift", category: "WatchdogService")

    private static var plistURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/LaunchAgents", directoryHint: .isDirectory)
            .appending(path: "\(label).plist", directoryHint: .notDirectory)
    }

    private static var domain: String { "gui/\(getuid())" }

    /// True when launchd currently has the agent loaded.
    static var isInstalled: Bool {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return false }
        return launchctl(["print", "\(domain)/\(label)"]) == 0
    }

    /// Writes the agent plist and asks launchd to load it. Idempotent.
    @discardableResult
    static func install() -> Bool {
        guard let executable = Bundle.main.executableURL?.path else {
            log.error("No executable path; cannot install the watchdog.")
            return false
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, modeFlag],
            // Always keep the watchdog alive, so killing it just brings it back.
            "KeepAlive": true,
            "RunAtLoad": true,
            // Don't let launchd spin if the watchdog crashes in a loop.
            "ThrottleInterval": 10,
            // Lowest scheduling priority: this process must never be felt.
            "ProcessType": "Background",
            "LimitLoadToSessionType": "Aqua",
        ]

        do {
            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            log.error("Could not write the watchdog plist: \(error.localizedDescription, privacy: .public)")
            return false
        }

        // Reload so a changed executable path takes effect.
        _ = launchctl(["bootout", "\(domain)/\(label)"])
        let status = launchctl(["bootstrap", domain, plistURL.path])
        if status != 0 {
            log.error("launchctl bootstrap failed with status \(status).")
            return false
        }
        log.info("Watchdog installed.")
        return true
    }

    /// Unloads and deletes the agent.
    @discardableResult
    static func remove() -> Bool {
        _ = launchctl(["bootout", "\(domain)/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
        log.info("Watchdog removed.")
        return true
    }

    /// Nudges launchd to start the agent now, used when a Locked session begins.
    static func kickstart() {
        _ = launchctl(["kickstart", "\(domain)/\(label)"])
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            log.error("launchctl \(arguments.first ?? "", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return -1
        }
    }
}
