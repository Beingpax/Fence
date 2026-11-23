import AppKit

if EnforcementService.isAgent {
    EnforcementService.run()
} else if CommandLine.arguments.contains("--watchdog") || CommandLine.arguments.contains("--background") {
    WatchdogRunner.migrateLegacyLaunch()
} else {
    EnforcementService.runDashboard()
}
