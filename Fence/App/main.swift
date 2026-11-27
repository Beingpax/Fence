import AppKit

if EnforcementService.isAgent {
    EnforcementService.run()
} else {
    EnforcementService.runDashboard()
}
