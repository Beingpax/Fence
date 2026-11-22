import AppKit
import SwiftUI

/// Hosts the first-run flow in its own window.
///
/// Shift is an `LSUIElement` app, so there is no Dock icon to click and no window by
/// default. The window is created on demand, centred, and sized to its content, per the
/// HIG guidance that setup windows shouldn't be resizable without reason.
@MainActor
final class OnboardingController {
    private var window: NSWindow?

    var isShowing: Bool { window?.isVisible ?? false }

    func present(model: AppModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
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
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        self.window = window
    }

    func close() {
        window?.orderOut(nil)
    }
}
