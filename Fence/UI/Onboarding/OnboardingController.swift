import AppKit
import SwiftUI

/// Hosts the first-run flow in its own window.
///
/// The window is created on demand and fills the screen it opens on, short of the menu bar
/// and the Dock: an ordinary window, not a full-screen space (26 Nov 2026, the user's call).
/// It can't be resized, zoomed or dragged: setup is always the size of the screen.
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
            .frame(minWidth: Theme.onboardingMinSize.width, maxWidth: .infinity,
                   minHeight: Theme.onboardingMinSize.height, maxHeight: .infinity)
            // Closing setup only orders the window out and keeps its views, so without this
            // the mascot, stars and loading dots would keep animating in a window nobody sees.
            .tracksWindowVisibility()

        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.visibleFrame ?? NSRect(origin: .zero, size: Theme.onboardingMinSize)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Fence"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovable = false
        window.isMovableByWindowBackground = false
        let hosting = NSHostingView(rootView: root)
        // Only the minimum comes from SwiftUI; the window, not the content, sets the size.
        hosting.sizingOptions = [.minSize]
        window.contentView = hosting
        window.contentMinSize = Theme.onboardingMinSize
        // No zoom either: the green button would toggle away from the maximised size.
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.isReleasedWhenClosed = false
        window.setFrame(frame, display: false)

        self.window = window
        window.presentForUser()
    }

    private func close() {
        window?.close()
        window?.contentView = nil
        window = nil
    }
}
