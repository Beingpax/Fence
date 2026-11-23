import Darwin
import Foundation
import os.log

/// Tracks the particular bundle this process started from, including Finder renames.
final class RunningBundleRecovery {
    private let original: URL
    private let descriptor: Int32
    private var protecting = false
    private var armed = false
    private static let log = Logger(subsystem: "com.beingpax.Shift", category: "BundleRecovery")

    init?(bundleURL: URL = Bundle.main.bundleURL) {
        guard bundleURL.pathExtension == "app" else { return nil }
        original = bundleURL.standardizedFileURL
        descriptor = open(original.path, O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_EVTONLY)
        guard descriptor >= 0 else { return nil }
    }

    deinit { if descriptor >= 0 { close(descriptor) } }

    func update(protected: Bool) {
        if protected != protecting {
            protecting = protected
            // A block starting later must not undo a move made while Shift was idle.
            armed = protected && isTrackedBundle(at: original)
        }
        guard armed, !FileManager.default.fileExists(atPath: original.path) else { return }

        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &path) == 0 else { return }
        let moved = URL(fileURLWithFileSystemRepresentation: path, isDirectory: true, relativeTo: nil)
        guard ShiftInstallation.isTrashDirectory(moved.deletingLastPathComponent()),
              !ShiftInstallation.isTrashDirectory(original.deletingLastPathComponent()),
              isTrackedBundle(at: moved) else { return }

        // Both processes may observe the move. Never overwrite an update or another app.
        if renamex_np(moved.path, original.path, UInt32(RENAME_EXCL)) == 0 {
            Self.log.info("Restored the running Shift app from the Trash.")
        }
    }

    private func isTrackedBundle(at url: URL) -> Bool {
        var tracked = stat()
        var entry = stat()
        return fstat(descriptor, &tracked) == 0 && lstat(url.path, &entry) == 0
            && entry.st_dev == tracked.st_dev && entry.st_ino == tracked.st_ino
    }
}
