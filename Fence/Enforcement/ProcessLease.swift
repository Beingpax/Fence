import Darwin
import Foundation

/// An advisory lock shared by Fence's two processes. macOS releases it on exit,
/// including Force Quit. The separate lock file survives atomic data-file replacement.
final class ProcessLease {
    private var descriptor: Int32

    init(url: URL, wait: Bool = false) throws {
        descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw Self.lastError }
        while flock(descriptor, LOCK_EX | (wait ? 0 : LOCK_NB)) != 0 {
            if errno == EINTR { continue }
            let error = Self.lastError
            release()
            throw error
        }
    }

    func release() {
        if descriptor >= 0 { close(descriptor); descriptor = -1 }
    }

    deinit { release() }

    private static var lastError: POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
