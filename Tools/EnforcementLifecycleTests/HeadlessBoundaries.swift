// Linked only into the temporary test bundle. main.swift, EnforcementService,
// AppModel, BlockStore, ProcessLease and the rule evaluator are production sources.
import AppKit

enum ShiftInstallation {
    static let supportDirectory: URL = {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "ShiftTestDirectory") as? String,
              Bundle.main.bundleIdentifier?.hasPrefix("test.shift.lifecycle.") == true else {
            fatalError("Expected the isolated lifecycle test bundle")
        }
        UserDefaults.standard.register(defaults: ["Shift.playNudgeSounds": false, "Shift.showNudges": false])
        return URL(fileURLWithPath: path, isDirectory: true)
    }()
    static func isTrashDirectory(_ directory: URL) -> Bool {
        directory.standardizedFileURL.path == supportDirectory.appending(path: "FixtureTrash").standardizedFileURL.path
    }

    static var legacyWatchdogPlist: URL { supportDirectory.appending(path: "unused.plist") }
}

/// The dashboard registers as an AppKit application so macOS publishes its actual
/// termination. It never creates a window. Unexpected dashboard launches leave evidence.
@MainActor
enum ShiftApp {
    static func main() {
        let root = ShiftInstallation.supportDirectory
        guard CommandLine.arguments.contains("--fixture-dashboard") else {
            try! Data().write(to: root.appending(path: "unexpected-dashboard"))
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let store = BlockStore()
        var block = Block(name: "Integration test")
        block.isEnabled = true
        block.list.apps = ["test.shift.game"]
        block.list.paths = ["fixture.invalid/feed"]
        store.add(block)
        // The test runner owns the temporary launchd job and its registration.
        AppModel.shared.startDashboard(registerAgent: { $0 })
        try! Data().write(to: root.appending(path: "dashboard-ready"))
        app.run()
    }
}

private struct Probe: Codable {
    let token: String
    let kind: String
    let path: String
}

@MainActor
private enum ProbeResult {
    static var current: Probe?

    static func record(_ action: String) {
        guard let current else { return }
        let response: [String: Any] = [
            "token": current.token, "action": action, "pid": getpid(),
            "accessory": NSApp.activationPolicy() == .accessory,
            "visibleWindows": NSApp.windows.filter(\.isVisible).count,
            "canQuit": AppModel.shared.canQuitApp
        ]
        let data = try! JSONSerialization.data(withJSONObject: response)
        try! data.write(to: ShiftInstallation.supportDirectory.appending(path: "response.json"), options: .atomic)
    }
}

/// Only the OS-facing input is synthetic. Samples go through AppModel.handle,
/// including the normal confirmation sample before presenting a pause.
@MainActor
final class ContextMonitor {
    var onSample: ((ScreenContext) -> Void)?
    var onInvalidation: (() -> Void)?
    private var timer: Timer?
    private var needsResample = false

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }
    func invalidate() { onInvalidation?() }
    func resampleSoon() { needsResample = true }

    private func sample() {
        let url = ShiftInstallation.supportDirectory.appending(path: "probe.json")
        guard let data = try? Data(contentsOf: url),
              let probe = try? JSONDecoder().decode(Probe.self, from: data),
              needsResample || ProbeResult.current?.token != probe.token else { return }
        ProbeResult.current = probe
        needsResample = false
        let browser = probe.kind == "browser"
        let context = ScreenContext(bundleID: browser ? "com.apple.Safari" : "test.shift.game",
                                    appName: browser ? "Safari" : "Fixture game", processID: getpid(),
                                    url: browser ? URL(string: "https://fixture.invalid" + probe.path) : nil)
        onSample?(context)
        if AppModel.shared.lastVerdict?.kind == .allow { ProbeResult.record("allow") }
    }

    func confirm(_ context: ScreenContext, readWebsite: Bool) async -> ScreenContext? { context }
}

/// Record the action at the point where production would display the full-screen pause.
@MainActor
final class PauseController {
    let isShowing = false
    let blockID: Block.ID? = nil
    func dismiss() {}
    func present(_ request: PauseRequest, onEvent: @escaping (PauseEvent) -> Void) {
        ProbeResult.record(request.ruleTarget?.identifier ?? "missing target")
    }
}
