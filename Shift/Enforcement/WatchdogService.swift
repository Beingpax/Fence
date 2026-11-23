import Foundation
import os.log

/// Removes registrations made by earlier releases after the bundled agent takes over.
enum WatchdogService {
    static let label = "com.beingpax.Shift.watchdog"

    private static let log = Logger(subsystem: "com.beingpax.Shift", category: "WatchdogService")

    private static var domain: String { "gui/\(getuid())" }

    static var hasConfiguration: Bool {
        FileManager.default.fileExists(atPath: ShiftInstallation.legacyWatchdogPlist.path)
    }

    /// Unloads and deletes the agent.
    @discardableResult
    static func remove() -> Bool {
        // Remove the file first so cleanup also works when the agent unloads itself.
        try? FileManager.default.removeItem(at: ShiftInstallation.legacyWatchdogPlist)
        _ = launchctl(["bootout", "\(domain)/\(label)"])
        log.info("Watchdog removed.")
        return true
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
