import AppKit
import SwiftUI

/// Borderless windows can't become key by default, which would break the phrase text field.
final class ShieldWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Covers every display with the frosted shield and locks the system down until the user acts.
@MainActor
final class ShieldController {
    private var windows: [ShieldWindow] = []
    private var savedPresentationOptions: NSApplication.PresentationOptions = []

    var isShowing: Bool { !windows.isEmpty }

    func present(_ request: ShieldRequest, onResolve: @escaping (ShieldResolution) -> Void) {
        guard !isShowing else { return }

        let primaryScreen = NSScreen.main ?? NSScreen.screens.first

        for screen in NSScreen.screens {
            let window = ShieldWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.setFrame(screen.frame, display: true)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false

            let view = ShieldView(
                request: request,
                showsControls: screen == primaryScreen
            ) { [weak self] resolution in
                self?.dismiss()
                onResolve(resolution)
            }
            window.contentView = NSHostingView(rootView: view)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }

        // Lock the system down while the shield is up: no Dock, no menu bar, no Cmd+Tab.
        savedPresentationOptions = NSApp.presentationOptions
        NSApp.activate()
        NSApp.presentationOptions = [
            .hideDock,
            .hideMenuBar,
            .disableProcessSwitching,
            .disableHideApplication,
            .disableAppleMenu,
        ]
        windows.first(where: { $0.screen == primaryScreen })?.makeKey()
    }

    func dismiss() {
        NSApp.presentationOptions = savedPresentationOptions
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}
