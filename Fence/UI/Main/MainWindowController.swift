import AppKit
import SwiftUI

/// Hosts the main window.
///
/// Keeping the window in an AppKit controller rather than a SwiftUI `Window` scene means
/// we can decide exactly when it appears, and bring it back without a scene round trip.
///
/// Fence lives in the menu bar all day and the window is open for minutes of it, so closing
/// the window frees it and its whole view tree. The next open builds a fresh one. An
/// unsaved edit in the inspector goes with it, as it would with any closed window.
@MainActor
final class MainWindowController {
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    /// Where the window was when it closed, so reopening it this session puts it back
    /// there, as it did when the window was kept.
    private var lastFrame: NSRect?
    /// Holds the window at its minimum size on every resize.
    private let sizeGuard = MinimumSizeGuard(contentMinSize: Theme.mainWindowMinSize)

    func present(model: AppModel) {
        if let window {
            window.presentForUser()
            return
        }

        let root = MainWindowView()
            .environment(model)
            // The Dashboard's mascot idles at 30 fps; hold it still while the window is
            // covered, minimised or on another Space.
            .tracksWindowVisibility()

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Theme.mainWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Fence"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // The content paints its own translucent material, so the window must not paint
        // an opaque one underneath it.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.toolbarStyle = .unified
        let hosting = NSHostingView(rootView: root)
        // The window's size limits are set once below (`contentMinSize`), so the hosting view
        // needn't work them out again from the whole view tree after every update. With the
        // Dashboard's mascot that measuring ran 30 times a second (Instruments, 26 Nov 2026).
        hosting.sizingOptions = []
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("FenceMainWindow")
        // One minimum, shared with the SwiftUI root, so the window can never be smaller
        // than its content. When they disagreed (820 here, 900 there) the hosting view
        // centred the overflow and clipped the sidebar and the Dashboard's switches.
        window.contentMinSize = Theme.mainWindowMinSize
        // `contentMinSize` alone didn't hold: the window could still be dragged to about
        // 500 × 400 (26 Nov 2026), most likely because the hosting view resets the limit
        // once its own sizing is switched off. The delegate clamps every resize, so nothing
        // that touches the limit later can let the window shrink past it.
        window.delegate = sizeGuard
        if let lastFrame {
            window.setFrame(lastFrame, display: false)
        } else {
            window.center()
        }
        // A frame saved by an older build may be smaller than today's minimum.
        let content = window.contentRect(forFrameRect: window.frame).size
        if content.width < Theme.mainWindowMinSize.width || content.height < Theme.mainWindowMinSize.height {
            window.setContentSize(NSSize(
                width: max(content.width, Theme.mainWindowMinSize.width),
                height: max(content.height, Theme.mainWindowMinSize.height)
            ))
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
        // Set again once the content is laid out and on screen, in case anything replaced it.
        window.contentMinSize = Theme.mainWindowMinSize
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

/// Refuses any resize that would make the window's content smaller than `contentMinSize`.
@MainActor
final class MinimumSizeGuard: NSObject, NSWindowDelegate {
    let contentMinSize: CGSize

    init(contentMinSize: CGSize) {
        self.contentMinSize = contentMinSize
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minimum = sender.frameRect(forContentRect: NSRect(origin: .zero, size: contentMinSize)).size
        return NSSize(width: max(frameSize.width, minimum.width), height: max(frameSize.height, minimum.height))
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
        // behind that app, so first launch looked like Fence had gone straight to the menu
        // bar. Bring the window forward regardless; it's always a response to the user.
        orderFrontRegardless()
    }
}
