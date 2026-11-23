import AppKit
import SwiftUI

/// What the pause needs to know about one reach for a blocked site.
struct PauseRequest {
    var blockName: String
    /// The site or app, as the person would name it: "instagram.com", "Steam".
    var target: String
    var appName: String
    /// 1 for the first reach this hour, 2 for the second. The third never gets a pause;
    /// the full-screen block takes over.
    var visit: Int
    /// Locked blocks don't offer "I need it": a lock is a promise not to negotiate.
    var allowsNeeded: Bool
    var plans: [UrgeReason: String]
    var isPreview = false

    /// One slow breath the first time, three the second. Each repeat costs more, so
    /// coming back is never free.
    var breathCycles: Int { visit <= 1 ? 1 : 3 }
}

/// What the person did in the pause.
enum PauseEvent {
    /// "I don't need this", with no answer given.
    case close
    /// A break started. The page closes now, and the break timer keeps the cover up.
    case beganBreak(UrgeReason)
    case finished(UrgeReason, UrgeOutcome, note: String?)
    case openMessages
    /// Two minutes for a stated reason.
    case allow(note: String)
}

/// A borderless panel has to opt in to key status, or the text fields can't take typing.
final class PausePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Covers the one browser window that reached for a blocked site.
///
/// Not the whole screen, on purpose. The pause is a question, not a punishment: everything
/// else on the Mac stays usable, and walking away to another app counts as the right answer.
/// The full-screen shield is kept for the third reach in an hour.
///
/// The panel is non-activating, so the browser stays the frontmost app underneath it. That
/// matters twice: the sampler keeps reading the browser, so Shift notices if the person
/// leaves, and the text fields still take typing without Shift stealing activation.
@MainActor
final class PauseController {
    private var panel: PausePanel?
    /// Which encounter this pause is for. See `AppModel.encounterKey`.
    private(set) var key: String?
    /// Set once the person has chosen something that closes the page (a break, say). From
    /// then on, the page changing underneath is expected and must not end the pause.
    private(set) var isCommitted = false

    var isShowing: Bool { panel != nil }

    private static let minimumSize = CGSize(width: 600, height: 620)

    /// - Parameter windowFrame: the browser window in screen coordinates with a top-left
    ///   origin, as the window server reports it. `nil` centres the pause on the main screen.
    func present(
        _ request: PauseRequest,
        key: String,
        over windowFrame: CGRect?,
        onEvent: @escaping (PauseEvent) -> Void
    ) {
        dismiss(animated: false)
        self.key = key
        isCommitted = false

        let frame = Self.cocoaFrame(for: windowFrame)
        let panel = PausePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        let view = PauseView(request: request) { event in onEvent(event) }
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        panel.contentView = hosting
        panel.setFrame(frame, display: true)

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    func commit() {
        isCommitted = true
    }

    func dismiss(animated: Bool = true) {
        guard let panel else { return }
        self.panel = nil
        key = nil
        isCommitted = false
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    /// Converts a window-server rectangle (top-left origin) to AppKit's bottom-left one,
    /// and grows it to a size the pause can lay out in.
    private static func cocoaFrame(for windowFrame: CGRect?) -> NSRect {
        guard let windowFrame, let primary = NSScreen.screens.first else {
            let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
            return NSRect(
                x: visible.midX - minimumSize.width / 2 - 60,
                y: visible.midY - minimumSize.height / 2 - 40,
                width: minimumSize.width + 120,
                height: minimumSize.height + 80
            )
        }
        var frame = NSRect(
            x: windowFrame.minX,
            y: primary.frame.maxY - windowFrame.maxY,
            width: windowFrame.width,
            height: windowFrame.height
        )
        if frame.width < minimumSize.width || frame.height < minimumSize.height {
            let grown = NSSize(width: max(frame.width, minimumSize.width), height: max(frame.height, minimumSize.height))
            frame = NSRect(x: frame.midX - grown.width / 2, y: frame.midY - grown.height / 2,
                           width: grown.width, height: grown.height)
            if let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) {
                let bounds = screen.visibleFrame
                frame.origin.x = min(max(frame.minX, bounds.minX), bounds.maxX - frame.width)
                frame.origin.y = min(max(frame.minY, bounds.minY), bounds.maxY - frame.height)
            }
        }
        return frame
    }
}
