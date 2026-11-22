import AppKit
import SwiftUI

/// The HUD for `nudge` verdicts. PRD §9: nudges never raise the shield.
///
/// Behaviour borrowed from IINA's on-screen display, which is the best-behaved HUD on the
/// platform: a non-activating panel that floats over everything, never takes keyboard focus,
/// never appears in Cmd+Tab or Mission Control, and fades itself out. Hovering it cancels
/// the fade so a slow reader isn't punished.
@MainActor
final class NudgeHUDController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    /// How long a nudge stays up before fading. Long enough to read a line, short enough
    /// to never feel like an alert.
    private let visibleDuration: Duration = .seconds(5)
    private let width: CGFloat = 420

    var isShowing: Bool { panel?.isVisible ?? false }

    /// Shows or replaces the current nudge.
    func show(reason: String, goal: String, onBlock: @escaping () -> Void) {
        let view = NudgeHUDView(
            reason: reason,
            goal: goal,
            onBlock: { [weak self] in
                self?.hide()
                onBlock()
            },
            onDismiss: { [weak self] in self?.hide() },
            onHoverChange: { [weak self] hovering in
                hovering ? self?.cancelAutoDismiss() : self?.scheduleAutoDismiss()
            }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: hosting.fittingSize.height)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = hosting
        panel.setContentSize(NSSize(width: width, height: hosting.fittingSize.height))
        position(panel)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            fade(panel, to: 1)
        }

        scheduleAutoDismiss()
    }

    func hide() {
        cancelAutoDismiss()
        guard let panel, panel.isVisible else { return }
        fade(panel, to: 0) { panel.orderOut(nil) }
    }

    // MARK: Panel

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 90),
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
        panel.hasShadow = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        return panel
    }

    /// Bottom centre, clear of the Dock. The same place macOS puts its own volume HUD,
    /// so it reads as system feedback rather than an app window.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.minY + Theme.Space.vast
            )
        )
    }

    // MARK: Fade and timing

    private func fade(_ panel: NSPanel, to alpha: CGFloat, completion: (() -> Void)? = nil) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.alphaValue = alpha
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alpha
        } completionHandler: {
            completion?()
        }
    }

    private func scheduleAutoDismiss() {
        cancelAutoDismiss()
        dismissTask = Task { [weak self, visibleDuration] in
            try? await Task.sleep(for: visibleDuration)
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
    let reason: String
    let goal: String
    let onBlock: () -> Void
    let onDismiss: () -> Void
    let onHoverChange: (Bool) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.snug) {
            Image(systemName: "arrow.turn.up.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Space.hair) {
                Text(reason)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                Text("You're here to: \(goal)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.tight)

            if isHovering {
                HStack(spacing: Theme.Space.tight) {
                    Button("Block it", action: onBlock)
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.semibold))
                        .help("Raise the shield for this now")

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.borderless)
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss nudge")
                }
                .calmTransition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Space.base)
        .padding(.vertical, Theme.Space.snug + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Behind-window blur rather than Liquid Glass: this panel floats over other
            // apps, so it has to sample the desktop, which only NSVisualEffectView does.
            BehindWindowBlur(material: .hudWindow)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hud, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.hud, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            onHoverChange(hovering)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shift nudge: \(reason)")
    }
}
