import Foundation
import os.log

/// Removes registrations made by earlier releases after the bundled agent takes over.
enum WatchdogService {
    static let label = "com.beingpax.Shift.watchdog"

    private static let log = Logger(subsystem: "com.beingpax.Shift", category: "WatchdogService")

    private static var domain: String { "gui/\(getuid())" }

    /// When the legacy file was last seen to be missing. Only earlier releases wrote it, so
    /// once it's gone it stays gone; the dashboard asked every second all the same.
    @MainActor private static var lastSeenAbsent: Date?

    @MainActor
    static var hasConfiguration: Bool {
        if let lastSeenAbsent, Date().timeIntervalSince(lastSeenAbsent) < 60 { return false }
        let present = FileManager.default.fileExists(atPath: ShiftInstallation.legacyWatchdogPlist.path)
        lastSeenAbsent = present ? nil : Date()
        return present
    }

    /// Unloads and deletes the agent.
    @MainActor
    @discardableResult
    static func remove() -> Bool {
        lastSeenAbsent = nil
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
