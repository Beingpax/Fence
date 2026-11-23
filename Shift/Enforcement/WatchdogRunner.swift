import Foundation
import os.log

enum WatchdogRunner {
    private static let log = Logger(subsystem: "com.beingpax.Shift", category: "Watchdog")

    /// Earlier releases launch with --watchdog or ask Launch Services for --background.
    /// Transfer enabled rules to the bundled login agent without starting a dashboard.
    @MainActor
    static func migrateLegacyLaunch() {
        let store = BlockStore()
        do {
            try EnforcementService.registerIfNeeded(enabled: store.blocks.contains { $0.isEnabled || $0.isLocked() })
        } catch {
            log.error("Could not register background enforcement: \(error.localizedDescription, privacy: .public)")
        }
        if WatchdogService.hasConfiguration { WatchdogService.remove() }
    }
}
