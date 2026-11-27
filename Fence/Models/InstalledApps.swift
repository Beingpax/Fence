import AppKit
import Observation

/// Every app on this Mac, for the in-app picker.
///
/// Scans application folders on demand and loads icons as rows are rendered.
@MainActor
@Observable
final class InstalledApps {
    static let shared = InstalledApps()

    private(set) var apps: [InstalledApp] = []
    private(set) var isLoading = false

    private var hasLoaded = false
    @ObservationIgnored private let icons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        return cache
    }()

    func loadIfNeeded() {
        guard !hasLoaded, !isLoading else { return }
        isLoading = true
        Task {
            let found = await Task.detached(priority: .userInitiated) { autoreleasepool { Self.scan() } }.value
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
        guard let app = apps.first(where: { $0.bundleID == bundleID }) else { return nil }
        return icon(for: app)
    }

    func icon(for app: InstalledApp) -> NSImage {
        let key = app.bundleID as NSString
        if let cached = icons.object(forKey: key) { return cached }
        let rasterSize = NSSize(width: 48, height: 48)
        let icon = NSImage(size: rasterSize)
        autoreleasepool {
            icon.lockFocus()
            defer { icon.unlockFocus() }
            NSWorkspace.shared.icon(forFile: app.path).draw(in: NSRect(origin: .zero, size: rasterSize))
        }
        icon.size = NSSize(width: 24, height: 24)
        icons.setObject(icon, forKey: key)
        return icon
    }

    func matching(_ query: String) -> [InstalledApp] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return apps }
        return apps.filter { $0.searchName.contains(trimmed) }
    }

    private nonisolated static func scan() -> [InstalledApp] {
        let fileManager = FileManager.default
        let roots = [
            "/Applications",
            "/System/Applications",
            NSHomeDirectory() + "/Applications",
        ].map { URL(fileURLWithPath: $0) }

        var seen = Set<String>()
        var results: [InstalledApp] = []

        for root in roots {
            guard let entries = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in entries where url.pathExtension.lowercased() == "app" {
                entries.skipDescendants()
                guard
                    let bundle = Bundle(url: url),
                    let bundleID = bundle.bundleIdentifier,
                    !seen.contains(bundleID)
                else { continue }
                seen.insert(bundleID)

                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent

                results.append(InstalledApp(bundleID: bundleID, name: name, path: url.path))
            }
        }

        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct InstalledApp: Identifiable, Hashable, Sendable {
    let bundleID: String
    let name: String
    /// Lowercased once at scan time, so filtering doesn't re-fold case per keystroke.
    let searchName: String
    let path: String

    var id: String { bundleID }

    init(bundleID: String, name: String, path: String) {
        self.bundleID = bundleID
        self.name = name
        self.searchName = name.lowercased()
        self.path = path
    }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.bundleID == rhs.bundleID }
    func hash(into hasher: inout Hasher) { hasher.combine(bundleID) }
}
