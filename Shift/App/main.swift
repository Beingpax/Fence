import AppKit

// One binary, two entry points.
//
// `Shift` launches the menu bar app. `Shift --watchdog` launches the headless watchdog
// that keeps Locked sessions honest (see WatchdogRunner). Sharing a binary means there is
// no second bundle to sign, notarize, keep in version lockstep, or have go missing.
//
// This file replaces the `@main` attribute on `ShiftApp`: a module containing top-level
// code uses that code as its entry point, so the two cannot coexist.

if CommandLine.arguments.contains("--watchdog") {
    WatchdogRunner.run()
} else {
    ShiftApp.main()
}
