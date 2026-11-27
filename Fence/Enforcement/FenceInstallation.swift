import Foundation

enum FenceInstallation {
    /// `~/Library/Application Support/<bundle ID>`: one folder per build, so Fence Dev never
    /// reads or writes the real app's blocks, journal, lists or locks.
    /// Worked out once: it can't change while the app runs, and the engine asks every second.
    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return base.appending(path: AppIdentity.bundleID, directoryHint: .isDirectory)
    }()

    static func isTrashDirectory(_ directory: URL) -> Bool {
        var relationship = FileManager.URLRelationship.other
        do {
            try FileManager.default.getRelationship(&relationship, of: .trashDirectory, in: .userDomainMask, toItemAt: directory)
            return relationship == .same
        } catch {
            return false
        }
    }
}
