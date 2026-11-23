import Foundation

enum ShiftInstallation {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return base.appending(path: "Shift", directoryHint: .isDirectory)
    }

    static func isTrashDirectory(_ directory: URL) -> Bool {
        var relationship = FileManager.URLRelationship.other
        do {
            try FileManager.default.getRelationship(&relationship, of: .trashDirectory, in: .userDomainMask, toItemAt: directory)
            return relationship == .same
        } catch {
            return false
        }
    }

    static var legacyWatchdogPlist: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/LaunchAgents", directoryHint: .isDirectory)
            .appending(path: "com.beingpax.Shift.watchdog.plist", directoryHint: .notDirectory)
    }
}
