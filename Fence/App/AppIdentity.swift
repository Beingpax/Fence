import Foundation

/// Which Fence this is.
///
/// Release builds are `com.prakashjoshipax.Fence` ("Fence"); Debug builds are
/// `com.prakashjoshipax.Fence.dev` ("Fence Dev"). Set per configuration in the project's
/// build settings.
///
/// Everything the two must not share comes from the bundle ID: the data folder
/// (`FenceInstallation.supportDirectory`), the background helper's launchd label and plist,
/// the log subsystem, the notifications between the app and its helper, UserDefaults and
/// the Accessibility grant. So a development build can run beside the installed app without
/// reading its blocks, enforcing its locks, or fighting over its helper.
enum AppIdentity {
    /// The shipping app's bundle ID. Also the fallback for tools built without a bundle.
    static let releaseBundleID = "com.prakashjoshipax.Fence"
    static let developmentBundleID = releaseBundleID + ".dev"

    static let bundleID = Bundle.main.bundleIdentifier ?? releaseBundleID
    static var isDevelopment: Bool { bundleID == developmentBundleID }

    /// The name in everything the user reads. The Dock and Finder take theirs from the
    /// build settings ("Fence", or "Fence Dev" for Debug).
    static let name = "Fence"

    /// The background helper's launchd label, and its plist in Contents/Library/LaunchAgents
    /// (`Services/` in the repo, one per configuration).
    static var helperLabel: String { "\(bundleID).enforcement" }
    static var helperPlistName: String { "\(helperLabel).plist" }

    /// Every Fence build. None of them is ever blocked, so a bad list can't lock someone
    /// out of the app that fixes it, and the dev build can't block the real one.
    static let ownBundleIDs: Set<String> = [releaseBundleID, developmentBundleID, bundleID]
}
