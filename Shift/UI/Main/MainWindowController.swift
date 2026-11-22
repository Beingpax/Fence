import AppKit
import SwiftUI

/// Hosts the main window.
///
/// Keeping the window in an AppKit controller rather than a SwiftUI `Window` scene means
/// we can decide exactly when it appears, and bring it back without a scene round trip.
@MainActor
final class MainWindowController {
    private var window: NSWindow?

    func present(model: AppModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let root = MainWindowView()
            .environment(model)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Theme.mainWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Shift"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // The content paints its own translucent material, so the window must not paint
        // an opaque one underneath it.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.toolbarStyle = .unified
        window.contentView = NSHostingView(rootView: root)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ShiftMainWindow")
        window.minSize = NSSize(width: 820, height: 520)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        self.window = window
    }

    func close() {
        window?.orderOut(nil)
    }
}
