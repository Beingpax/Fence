/// The Accessibility layout Shift expects for a known browser.
enum Browser: Equatable, Sendable {
    case webKit, chromium, gecko, dia, vivaldi

    // Exact bundle IDs, folded for comparison. Browser previews and forks often install side by side.
    private static let byBundleID: [String: Browser] = [
        "com.apple.safari": .webKit,
        "com.apple.safaritechnologypreview": .webKit,
        "com.kagi.kagimacos": .webKit,
        "com.kagi.kagimacos.rc": .webKit,

        "com.google.chrome": .chromium,
        "com.google.chrome.beta": .chromium,
        "com.google.chrome.dev": .chromium,
        "com.google.chrome.canary": .chromium,
        "org.chromium.chromium": .chromium,
        "com.microsoft.edgemac": .chromium,
        "com.microsoft.edgemac.beta": .chromium,
        "com.microsoft.edgemac.dev": .chromium,
        "com.microsoft.edgemac.canary": .chromium,
        "com.brave.browser": .chromium,
        "com.brave.browser.beta": .chromium,
        "com.brave.browser.nightly": .chromium,
        "company.thebrowser.browser": .chromium,
        "net.imput.helium": .chromium,
        "com.operasoftware.opera": .chromium,
        "com.operasoftware.operagx": .chromium,
        "com.operasoftware.operaair": .chromium,
        "com.operasoftware.operanext": .chromium,
        "com.operasoftware.operadeveloper": .chromium,
        "company.thebrowser.dia": .dia,
        "com.vivaldi.vivaldi": .vivaldi,
        "com.vivaldi.vivaldi.snapshot": .vivaldi,

        "org.mozilla.firefox": .gecko,
        "org.mozilla.firefoxdeveloperedition": .gecko,
        "org.mozilla.nightly": .gecko,
        "app.zen-browser.zen": .gecko,
        "net.librewolf.librewolf": .gecko,
        "io.gitlab.librewolf-community.librewolf": .gecko,
        "net.waterfox.waterfox": .gecko,
    ]

    init?(bundleID: String) {
        guard let browser = Self.byBundleID[bundleID.lowercased()] else { return nil }
        self = browser
    }

    var isChromium: Bool { self == .chromium || self == .dia || self == .vivaldi }
}
