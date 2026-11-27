import Foundation

/// Which copy of Fence's executable is on disk, so the background helper can tell when the
/// app has been replaced under it.
///
/// launchd keeps the helper (`--enforcement-agent`) alive for as long as the Mac is up, so
/// without this a rebuild or an update leaves it enforcing with the old code: the dashboard
/// shows the new pause in previews while every real pause is the old one. Replacing a file
/// gives it a new inode, and rewriting it in place gives it a new modification date, so
/// together they catch an Xcode rebuild, a Sparkle update and a drag-and-drop install.
struct ExecutableStamp: Equatable, Sendable {
    let fileNumber: UInt64?
    let size: UInt64?
    let modified: Date?

    /// The executable as it is on disk right now, or `nil` while it's missing (mid-update,
    /// or moved to the Trash, which `FenceInstallation` handles separately).
    static func current() -> ExecutableStamp? {
        guard let path = executablePath else { return nil }
        // A plain stat. Both processes ask every five seconds; resolving every component of
        // the path and building a FileManager attribute dictionary each time showed up in
        // Instruments as most of the helper's idle work.
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        let modified = info.st_mtimespec
        return ExecutableStamp(
            fileNumber: UInt64(info.st_ino),
            size: UInt64(info.st_size),
            modified: Date(timeIntervalSince1970: TimeInterval(modified.tv_sec) + TimeInterval(modified.tv_nsec) / 1_000_000_000)
        )
    }

    /// Where the executable lives, symlinks resolved once at launch. An update replaces the
    /// file at this path, which `current()` sees as a new inode.
    static let executablePath: String? = Bundle.main.executableURL?.resolvingSymlinksInPath().path(percentEncoded: false)
}

extension ExecutableStamp {
    /// When this copy of Fence's executable was last written, read from disk now.
    static var currentBuildDate: Date? { current()?.modified }

    /// When a process started, from the kernel. Works for the helper, which launchd starts
    /// without going through Launch Services, so `NSRunningApplication.launchDate` is unset.
    static func startDate(of pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
