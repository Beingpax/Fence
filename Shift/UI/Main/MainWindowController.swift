import AppKit
import SwiftUI

/// Hosts the main window.
///
/// Keeping the window in an AppKit controller rather than a SwiftUI `Window` scene means
/// we can decide exactly when it appears, and bring it back without a scene round trip.
///
/// Shift lives in the menu bar all day and the window is open for minutes of it, so closing
/// the window frees it and its whole view tree. The next open builds a fresh one. An
/// unsaved edit in the inspector goes with it, as it would with any closed window.
@MainActor
final class MainWindowController {
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    /// Where the window was when it closed, so reopening it this session puts it back
    /// there, as it did when the window was kept.
    private var lastFrame: NSRect?

    func present(model: AppModel) {
        if let window {
            window.presentForUser()
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
        if let lastFrame {
            window.setFrame(lastFrame, display: false)
        } else {
            window.center()
        }

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, weak model] _ in
            MainActor.assumeIsolated { self?.release(model: model) }
        }

        self.window = window
        window.presentForUser()
    }

    func close() {
        window?.close()
    }

    private func release(model: AppModel?) {
        guard let window else { return }
        lastFrame = window.frame
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        self.window = nil
        // These open the inspector and the unlock sheet. Their drafts lived in the views
        // that are going, so a reopened window starts clean rather than half-restored.
        model?.newBlock = nil
        model?.unlockTarget = nil
        // Let AppKit finish closing before the view tree goes.
        Task { @MainActor in window.contentView = nil }
    }
}

extension NSWindow {
    func presentForUser() {
        if NSApp.isHidden { NSApp.unhide(nil) }
        NSApp.activate()
        if isMiniaturized { deminiaturize(nil) }

        if let sheet = attachedSheet {
            orderFront(nil)
            sheet.makeKey()
        } else {
            makeKeyAndOrderFront(nil)
        }
        // `NSApp.activate()` is cooperative: when another app is frontmost (Finder after a
        // double-click, or Xcode after Run) macOS may decline it, and the window would open
        // behind that app, so first launch looked like Shift had gone straight to the menu
        // bar. Bring the window forward regardless; it's always a response to the user.
        orderFrontRegardless()
    }
}
