import AppKit
import SwiftUI

/// Hosts the first-run flow in its own window.
///
/// The window is created on demand, centred, and sized to its content.
@MainActor
final class OnboardingController {
    private var window: NSWindow?

    var isShowing: Bool { window?.isVisible ?? false }

    func present(model: AppModel) {
        if let window {
            window.presentForUser()
            return
        }

        let root = OnboardingView(onFinish: { [weak self] in self?.close() })
            .environment(model)
            .frame(width: Theme.onboardingSize.width, height: Theme.onboardingSize.height)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Theme.onboardingSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Shift"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: root)
        window.isReleasedWhenClosed = false
        window.center()

        self.window = window
        window.presentForUser()
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
    }
}
