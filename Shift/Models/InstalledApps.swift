import AppKit
import Observation

/// Every app on this Mac, for the in-app picker.
///
/// Scanning the application folders and pulling icons is slow enough to matter, so it
/// happens once, off the main actor, and the result is cached for the session. The
/// alternative was sending people to an open panel, which makes choosing three apps feel
/// like three separate chores.
@MainActor
@Observable
final class InstalledApps {
    static let shared = InstalledApps()

    private(set) var apps: [InstalledApp] = []
    private(set) var isLoading = false

    private var hasLoaded = false

    func loadIfNeeded() {
        guard !hasLoaded, !isLoading else { return }
        isLoading = true
        Task {
            let found = await Self.scan()
            apps = found
            isLoading = false
            hasLoaded = true
        }
    }

    /// Name for a bundle identifier, so saved blocks can show something human.
    func name(for bundleID: String) -> String? {
        apps.first { $0.bundleID == bundleID }?.name
    }

    func icon(for bundleID: String) -> NSImage? {
        apps.first { $0.bundleID == bundleID }?.icon
    }

    func matching(_ query: String) -> [InstalledApp] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private nonisolated static func scan() async -> [InstalledApp] {
        await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let roots = [
                "/Applications",
                "/Applications/Utilities",
                "/System/Applications",
                "/System/Applications/Utilities",
                NSHomeDirectory() + "/Applications",
            ].map { URL(fileURLWithPath: $0) }

            var seen = Set<String>()
            var results: [InstalledApp] = []

            for root in roots {
                guard let entries = try? fileManager.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isApplicationKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for url in entries where url.pathExtension == "app" {
                    guard
                        let bundle = Bundle(url: url),
                        let bundleID = bundle.bundleIdentifier,
                        !seen.contains(bundleID)
                    else { continue }
                    seen.insert(bundleID)

                    let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                        ?? url.deletingPathExtension().lastPathComponent

                    let icon = NSWorkspace.shared.icon(forFile: url.path)
                    icon.size = NSSize(width: 32, height: 32)

                    results.append(InstalledApp(bundleID: bundleID, name: name, icon: icon))
                }
            }

            return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }.value
    }
}

struct InstalledApp: Identifiable, Hashable, @unchecked Sendable {
    let bundleID: String
    let name: String
    /// `NSImage` isn't `Sendable`; these are created once during the scan and only ever
    /// read afterwards, which is why the conformance is unchecked.
    let icon: NSImage?

    var id: String { bundleID }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.bundleID == rhs.bundleID }
    func hash(into hasher: inout Hasher) { hasher.combine(bundleID) }
}
