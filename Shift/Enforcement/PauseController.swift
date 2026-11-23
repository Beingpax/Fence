import AppKit
import SwiftUI

/// What the pause needs to know about one reach for a blocked site.
struct PauseRequest {
    var blockName: String
    var blockID: UUID?
    /// The rule that matched, so "I need it" can let exactly this site through.
    var ruleTarget: RuleTarget?
    /// The site or app, as the person would name it: "instagram.com", "Steam".
    var target: String
    var appName: String
    var isBrowser: Bool
    /// Which reach this is within the hour: 1, 2, 3 or more.
    var visit: Int
    /// Breaks left today on this block, or `nil` when the block has breaks switched off.
    /// "I need it" spends one of these, so it only appears when the block allows breaks.
    var breaksLeft: Int?
    var plans: [UrgeReason: String]
    /// The headline and line under it, dealt from `PauseCopy` for this visit.
    var title: String
    var subtitle: String
    var isPreview = false

    /// How long the choices stay out of reach. Two slow breaths the first time, four the
    /// second, six from the third on: each repeat costs more, so coming back is never free.
    /// Closing it never waits.
    var waitSeconds: Int {
        switch visit {
        case ...1: 10
        case 2: 20
        default: 30
        }
    }

    /// Closing the tab is the whole point in a browser; the other tabs are probably work.
    var closeTitle: String { isBrowser ? "Close the tab" : "Quit \(appName)" }
}

/// What the person chose in the pause.
enum PauseEvent {
    /// Close it, with the craving they named, if they named one.
    case close(UrgeReason?)
    /// "I need it": a stated reason, then this one site for a minute or two.
    case takeBreak(minutes: Int, note: String)
}

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
    /// Which encounter this pause is for. See `AppModel.encounterKey`.
    private(set) var key: String?

    var isShowing: Bool { !windows.isEmpty }

    func present(_ request: PauseRequest, key: String, onEvent: @escaping (PauseEvent) -> Void) {
        dismiss()
        self.key = key

        let screens = NSScreen.screens
        guard let primaryScreen = NSScreen.main ?? screens.first else {
            self.key = nil
            return
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
                ? AnyView(PauseView(request: request, wallpaper: wallpaper, onEvent: onEvent))
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

    /// Gives the system back straight away, so the browser can take the front and close
    /// the tab, and lets the windows fade out on their own time.
    func dismiss() {
        guard isShowing else { return }
        NSApp.presentationOptions = savedPresentationOptions
        let leaving = windows
        windows.removeAll()
        key = nil

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
