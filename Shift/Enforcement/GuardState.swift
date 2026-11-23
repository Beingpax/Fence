import Foundation

/// The handshake between the Shift UI process and the watchdog process.
///
/// The UI writes this file while a Locked session runs. The watchdog reads it to answer
/// two questions: "should Shift be running right now?" and "where does it live?".
/// It is deliberately a plain file rather than IPC, so the watchdog keeps working even
/// if the UI process dies without warning.
struct GuardState: Codable, Equatable {
    /// Wall-clock instant after which the watchdog should stop reviving Shift.
    var lockedUntil: Date
    /// Where the app bundle was when the lock started, so tamper recovery can find it.
    var bundlePath: String
    /// The goal, used only for the log line the watchdog writes.
    var goal: String
    /// Last time the UI said it was alive.
    var heartbeat: Date

    var isActive: Bool { Date() < lockedUntil }

    // MARK: Storage

    static var fileURL: URL {
        ShiftInstallation.supportDirectory.appending(path: "guard.json", directoryHint: .notDirectory)
    }

    static func load() -> GuardState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(GuardState.self, from: data)
    }

    func save() {
        let directory = ShiftInstallation.supportDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    /// Called when a locked session ends normally. The watchdog then goes quiet.
    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
