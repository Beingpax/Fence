import AppKit
import SwiftUI

/// What one nudge says, and how worried it looks saying it.
struct NudgeContent: Equatable {
    var headline: String
    var detail: String
    /// `1...total` for a rung of the escalation ladder; `nil` for a soft hint that never
    /// escalates into anything (the intent and feed-keyword nudges).
    var step: Int?
    var total: Int = NudgeLadder.stepCount

    var mood: NudgeMood {
        guard let step else { return .calm }
        switch step {
        case ...1: return .calm
        case 2: return .concerned
        default: return .alarmed
        }
    }
}

/// Drives which rendered expression appears and what colour the panel carries.
enum NudgeMood {
    case calm, concerned, alarmed

    var tint: Color {
        switch self {
        case .calm: Color(red: 0.36, green: 0.78, blue: 0.72)
        case .concerned: Color(red: 0.98, green: 0.69, blue: 0.33)
        case .alarmed: Color(red: 0.98, green: 0.45, blue: 0.47)
        }
    }
}

/// The HUD for every nudge, soft or escalating.
///
/// Behaviour borrowed from IINA's on-screen display, which is the best-behaved HUD on the
/// platform: a non-activating panel that floats over everything, never takes keyboard focus,
/// never appears in Cmd+Tab or Mission Control, and fades itself out.
///
/// It sits against the right edge rather than the bottom centre, because the ladder nudges
/// have to be noticed without covering the thing the user is reading, and because a
/// character leaning in from off-screen is a friendlier interruption than a banner.
@MainActor
final class NudgeHUDController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    /// Ladder rungs replace each other every few seconds, so a fade-out already in flight
    /// has to lose to the fade-in that follows it, or the panel gets ordered out from
    /// under the new rung.
    private var transitionTask: Task<Void, Never>?

    /// How long a soft hint stays up before fading.
    private let hintDuration: Duration = .seconds(5)
    private let width: CGFloat = 580

    var isShowing: Bool { panel?.isVisible ?? false }

    /// A nudge that will never turn into anything. Fades itself out.
    func hint(reason: String, detail: String) {
        show(NudgeContent(headline: reason, detail: detail, step: nil))
    }

    /// Rung `step` of the escalation ladder.
    func ladder(step: Int, headline: String, detail: String) {
        show(NudgeContent(headline: headline, detail: detail, step: step))
    }

    func show(_ content: NudgeContent) {
        let isHint = content.step == nil
        let view = NudgeHUDView(
            content: content,
            onDismiss: isHint ? { [weak self] in self?.hide() } : nil,
            onHoverChange: { [weak self] hovering in
                guard isHint else { return }
                hovering ? self?.cancelAutoDismiss() : self?.scheduleAutoDismiss(after: self?.hintDuration ?? .seconds(5))
            }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: hosting.fittingSize.height)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = hosting
        panel.setContentSize(NSSize(width: width, height: hosting.fittingSize.height))
        position(panel)

        if !panel.isVisible {
            transitionTask?.cancel()
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            transitionTask = Task { [panel] in await fade(panel, to: 1) }
        } else if panel.alphaValue < 1 {
            transitionTask?.cancel()
            transitionTask = Task { [panel] in await fade(panel, to: 1) }
        }

        // The ladder takes its own rungs down after `visible`. This timer is only a
        // backstop against a rung outliving the ladder that put it there.
        scheduleAutoDismiss(after: isHint ? hintDuration : NudgeLadder.visible + .seconds(2))
    }

    func hide() {
        cancelAutoDismiss()
        transitionTask?.cancel()
        guard let panel, panel.isVisible else { return }
        transitionTask = Task { [panel] in
            await fade(panel, to: 0)
            // A `show` during the fade cancels this, so the panel stays up for the new rung.
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    // MARK: Panel

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 110),
            // `.nonactivatingPanel` is what keeps the user's keyboard focus where it was.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Above ordinary windows, deliberately below the shield's `.screenSaver` level.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The character carries its own soft glow, so the panel must not clip to a box.
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        return panel
    }

    /// Top right, just under the menu bar — where macOS already puts things that want
    /// your attention without taking it. Clear of the Dock, clear of the middle of the
    /// screen, and clear of whatever you are reading.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: visible.maxX - size.width,
                y: visible.maxY - size.height - Theme.Space.tight
            )
        )
    }

    // MARK: Fade and timing

    /// Awaitable so callers can sequence work after the animation without passing a
    /// non-Sendable completion closure into AppKit's `@Sendable` handler.
    private func fade(_ panel: NSPanel, to alpha: CGFloat) async {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.alphaValue = alpha
            return
        }
        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = alpha
            } completionHandler: {
                continuation.resume()
            }
        }
    }

    private func scheduleAutoDismiss(after delay: Duration) {
        cancelAutoDismiss()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func cancelAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
    }
}

// MARK: - View

private struct NudgeHUDView: View {
    let content: NudgeContent
    /// Soft hints can be swatted away. A ladder rung can't, because dismissing it would
    /// imply it had been dealt with.
    let onDismiss: (() -> Void)?
    let onHoverChange: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var entered = false

    private var mood: NudgeMood { content.mood }

    var body: some View {
        HStack(alignment: .bottom, spacing: -10) {
            message
            NudgeCharacter(mood: mood, animates: !reduceMotion)
        }
        .padding(.trailing, Theme.Space.loose)
        .padding(.vertical, Theme.Space.loose)
        .frame(maxWidth: .infinity, alignment: .trailing)
        // Slides in from beyond the screen edge. The panel is clipped to its window, so an
        // offset wider than the content reads as the character walking on from off-screen.
        .offset(x: entered ? 0 : 470)
        .onAppear {
            guard !reduceMotion else {
                entered = true
                return
            }
            withAnimation(.spring(response: 0.44, dampingFraction: 0.74)) { entered = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if let step = content.step {
            return "Shift nudge \(step) of \(content.total): \(content.headline). \(content.detail)"
        }
        return "Shift nudge: \(content.headline). \(content.detail)"
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.tight) {
                Text(content.headline)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)

                Spacer(minLength: 0)

                if let onDismiss, isHovering {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                    }
                    .buttonStyle(.borderless)
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss nudge")
                    .calmTransition(.opacity)
                }
            }

            Text(content.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

        }
        .padding(.horizontal, Theme.Space.base)
        .padding(.vertical, Theme.Space.snug + 1)
        .frame(width: 300, alignment: .leading)
        .background {
            // Behind-window blur rather than Liquid Glass: this panel floats over other
            // apps, so it has to sample the desktop, which only NSVisualEffectView does.
            // The radius has to be passed in — a SwiftUI clipShape cannot clip a
            // behind-window blur, and without it the card sits inside a faint rectangle.
            BehindWindowBlur(material: .hudWindow, cornerRadius: Theme.Radius.hud)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hud, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.hud, style: .continuous)
                .strokeBorder(mood.tint.opacity(content.step == content.total ? 0.55 : 0.3), lineWidth: 1)
        }
        // No drop shadow. NSHostingView clips at the window bounds, so any shadow wide
        // enough to be worth having gets sliced off at the edge and leaves a hard grey
        // line across the desktop. The tinted border is what separates the card instead.
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            onHoverChange(hovering)
        }
    }

}

// MARK: - The character

/// Hosts the drawn character and gives it its entrance.
///
/// The face itself lives in `NudgeCharacterView`, which owns the idle motion — breathing,
/// sway, blink. This wrapper only handles the arrival.
private struct NudgeCharacter: View {
    let mood: NudgeMood
    let animates: Bool

    @State private var landed = false

    var body: some View {
        NudgeCharacterView(mood: mood, animates: animates)
            // Arrives a beat after the panel, with a little overshoot, so he reads as
            // stepping in rather than appearing.
            .scaleEffect(landed ? 1 : 0.82, anchor: .bottom)
            .opacity(landed ? 1 : 0)
            .onAppear {
                guard animates else {
                    landed = true
                    return
                }
                withAnimation(.spring(response: 0.46, dampingFraction: 0.62).delay(0.08)) {
                    landed = true
                }
            }
            .accessibilityHidden(true)
    }
}
