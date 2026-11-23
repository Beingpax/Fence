import AppKit
import SwiftUI

/// Borderless windows can't become key by default, which would break the text field.
final class PauseWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Covers every display with the pause.
///
/// The only full-screen surface in Shift: it replaced both the window-sized pause and the
/// separate shield. Full-screen because a partial cover left the page visible around it,
/// and the question only lands when it's the only thing on screen. While it's up there's
/// no Dock, menu bar or Cmd+Tab, so the only ways out are the answers on it.
@MainActor
final class PauseController {
    private var windows: [PauseWindow] = []
    private var savedPresentationOptions: NSApplication.PresentationOptions = []
    private var presentationID: UUID?
    private(set) var blockID: Block.ID?

    var isShowing: Bool { !windows.isEmpty }

    func present(_ request: PauseRequest, onEvent: @escaping (PauseEvent) -> Void) {
        dismiss()

        let screens = NSScreen.screens
        guard let primaryScreen = NSScreen.main ?? screens.first else { return }
        let presentationID = UUID()
        self.presentationID = presentationID
        blockID = request.blockID
        let handleEvent: (PauseEvent) -> Void = { [weak self] event in
            // A window that is fading out may still finish its countdown.
            guard self?.presentationID == presentationID else { return }
            onEvent(event)
        }
        let wallpaper = PauseWallpaper()
        var primaryWindow: PauseWindow?
        for screen in screens {
            let window = PauseWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.setFrame(screen.frame, display: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.alphaValue = 0

            let content: AnyView = screen == primaryScreen
                ? AnyView(PauseView(request: request, wallpaper: wallpaper, onEvent: handleEvent))
                : AnyView(PauseBackdrop(wallpaper: wallpaper))
            window.contentView = NSHostingView(rootView: content)
            if screen == primaryScreen { primaryWindow = window }
            window.orderFrontRegardless()
            windows.append(window)
        }

        savedPresentationOptions = NSApp.presentationOptions
        NSApp.activate()
        NSApp.presentationOptions = [
            .hideDock,
            .hideMenuBar,
            .disableProcessSwitching,
            .disableHideApplication,
            .disableAppleMenu,
        ]
        primaryWindow?.makeKey()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for window in windows {
            if reduceMotion {
                window.alphaValue = 1
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.45
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().alphaValue = 1
                }
            }
        }
    }

    /// Gives the system back straight away and lets the windows fade out on their own time.
    func dismiss() {
        guard isShowing else { return }
        NSApp.presentationOptions = savedPresentationOptions
        let leaving = windows
        windows.removeAll()
        presentationID = nil
        blockID = nil

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            Self.releaseWindows(leaving)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            leaving.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            MainActor.assumeIsolated { Self.releaseWindows(leaving) }
        }
    }

    private static func releaseWindows(_ windows: [PauseWindow]) {
        for window in windows {
            window.close()
            window.contentView = nil
        }
    }
}
