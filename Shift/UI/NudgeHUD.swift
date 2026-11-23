import AppKit
import SwiftUI

/// What one card says, and how Flop looks saying it.
struct NudgeContent: Equatable {
    enum Kind: Equatable {
        /// A soft hint from the feed-keyword check. Never escalates.
        case hint
        /// Praise for turning back on your own. See `AppModel.reward`.
        case reward
        /// A plain status line, such as the two minutes you asked for starting.
        case status
    }

    var headline: String
    var detail: String
    var kind: Kind

    var mood: NudgeMood { kind == .reward ? .happy : .calm }
}

/// Drives which rendered expression appears and what colour the panel carries.
///
/// `concerned` and `alarmed` belonged to the old three-nudge ladder. They stay because the
/// character's ears are still the clearest way to show escalation, should it come back.
enum NudgeMood {
    case calm, concerned, alarmed, happy

    var tint: Color {
        switch self {
        case .calm: Color(red: 0.36, green: 0.78, blue: 0.72)
        case .concerned: Color(red: 0.98, green: 0.69, blue: 0.33)
        case .alarmed: Color(red: 0.98, green: 0.45, blue: 0.47)
        case .happy: Color(red: 0.36, green: 0.78, blue: 0.72)
        }
    }
}

/// The HUD for every nudge, soft or escalating.
///
/// Behaviour borrowed from IINA's on-screen display, which is the best-behaved HUD on the
/// platform: a non-activating panel that floats over everything, never takes keyboard focus,
/// never appears in Cmd+Tab or Mission Control, and fades itself out.
///
/// It sits against the right edge rather than the bottom centre, because a nudge has to be
/// noticed without covering the thing the user is reading, and because that is where macOS
/// already puts banners. Flop stands to the left of the card, the card against the screen
/// edge, and the pair arrives and leaves exactly like a notification: in from beyond the
/// right edge, and back out the same way.
@MainActor
final class NudgeHUDController {
    private var panel: NSPanel?
    private var hosting: NSHostingView<NudgeHUDView>?
    private var dismissTask: Task<Void, Never>?
    /// Cards can replace each other within a second or two, so a slide-out already in
    /// flight has to lose to the card that follows it, or the panel gets ordered out from
    /// under the new one.
    private var transitionTask: Task<Void, Never>?
    /// True from the moment the card starts sliding out until the panel is gone.
    private var isLeaving = false
    /// How long the exit takes, plus a frame or two. Keep in step with
    /// `NudgeHUDView.exitDuration`.
    private let exitGrace: Duration = .milliseconds(340)

    /// How long a soft hint stays up before fading.
    private let hintDuration: Duration = .seconds(5)
    private let width: CGFloat = 580

    var isShowing: Bool { (panel?.isVisible ?? false) && !isLeaving }

    private var current: NudgeContent?

    /// A nudge that will never turn into anything. Fades itself out.
    func hint(reason: String, detail: String) {
        show(NudgeContent(headline: reason, detail: detail, kind: .hint))
    }

    /// Flop, delighted, the moment someone turns back on their own.
    func reward(headline: String, detail: String) {
        show(NudgeContent(headline: headline, detail: detail, kind: .reward))
    }

    func status(headline: String, detail: String) {
        show(NudgeContent(headline: headline, detail: detail, kind: .status))
    }

    /// Takes a soft hint down when the user moves on, but leaves praise alone: a reward
    /// usually lands right as the user switches app, and it has to survive that.
    func hideHint() {
        guard current?.kind == .hint else { return }
        hide()
    }

    func show(_ content: NudgeContent) {
        current = content

        let panel = self.panel ?? makePanel()
        self.panel = panel

        if let hosting, panel.isVisible, !isLeaving {
            // A card already resting on screen swaps its words in place: handing SwiftUI a
            // new root view is an update, not an appearance, so the entrance doesn't replay.
            hosting.rootView = makeView(content)
            fit(panel, hosting)
        } else {
            // Gone, or on its way out: build it fresh so it slides in from off-screen.
            transitionTask?.cancel()
            transitionTask = nil
            isLeaving = false

            let hosting = NSHostingView(rootView: makeView(content))
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = .clear
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: hosting.fittingSize.height)
            self.hosting = hosting
            panel.contentView = hosting
            fit(panel, hosting)

            // The card animates itself in, so the panel is simply there at full strength.
            // Fading the window as well read as a dissolve rather than an arrival.
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }

        scheduleAutoDismiss(after: hintDuration)
    }

    func hide() {
        cancelAutoDismiss()
        guard let panel, let hosting, let content = current, panel.isVisible, !isLeaving else { return }
        isLeaving = true
        // It leaves the way it came: back out past the right edge. `isLeaving` is a plain
        // property of the root view, so giving SwiftUI a new one is what drives it.
        hosting.rootView = makeView(content, leaving: true)

        transitionTask?.cancel()
        transitionTask = Task { [weak self] in
            try? await Task.sleep(for: self?.exitGrace ?? .milliseconds(340))
            // A `show` during the exit cancels this, so the panel stays up for the new card.
            guard !Task.isCancelled else { return }
            self?.teardown()
        }
    }

    private func teardown() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        hosting = nil
        current = nil
        isLeaving = false
        transitionTask = nil
        cancelAutoDismiss()
    }

    private func makeView(_ content: NudgeContent, leaving: Bool = false) -> NudgeHUDView {
        NudgeHUDView(
            content: content,
            isLeaving: leaving,
            onDismiss: { [weak self] in self?.hide() },
            onHoverChange: { [weak self] hovering in
                hovering
                    ? self?.cancelAutoDismiss()
                    : self?.scheduleAutoDismiss(after: self?.hintDuration ?? .seconds(5))
            }
        )
    }

    /// Cards differ in height, and the panel is anchored by its top edge, so a resize has
    /// to be followed by a reposition or the card appears to sink.
    private func fit(_ panel: NSPanel, _ hosting: NSHostingView<NudgeHUDView>) {
        panel.setContentSize(NSSize(width: width, height: hosting.fittingSize.height))
        position(panel)
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
        // Above ordinary windows, deliberately below the pause's `.screenSaver` level.
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

    // MARK: Timing

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
    /// Flipped by the controller to send the card back out before the panel goes.
    var isLeaving = false
    let onDismiss: (() -> Void)?
    let onHoverChange: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovering = false
    @State private var entered = false

    /// How long the exit runs. `NudgeHUDController.exitGrace` waits this out.
    static let exitDuration: Double = 0.28

    /// Far enough to clear Flop, the card and the gap at the edge, so the pair ends up
    /// fully past the screen's right edge rather than half-visible against it.
    private static let travel: CGFloat = 540

    private var mood: NudgeMood { content.mood }

    /// Off to the right both before the entrance and during the exit.
    private var isOffscreen: Bool { !entered || isLeaving }

    var body: some View {
        HStack(alignment: .bottom, spacing: -10) {
            NudgeCharacter(mood: mood, animates: !reduceMotion)
                .overlay {
                    // A burst of sparkles when someone turns back: a small celebration
                    // the instant they do the thing the habit is built on.
                    if content.kind == .reward, !reduceMotion { SparkleBurst() }
                }
                // Leaning in front of the card, not behind it: the overlap is what ties
                // the pair together.
                .zIndex(1)
            message
        }
        .padding(.trailing, Theme.Space.loose)
        .padding(.vertical, Theme.Space.loose)
        // Flop stands to the left, the card against the screen edge where banners sit.
        .frame(maxWidth: .infinity, alignment: .trailing)
        // Travels in from beyond the screen edge and back out the same way, like a
        // notification banner. The panel clips to its window, and the window's right edge
        // is the screen's, so an offset wider than the content hides it completely.
        .offset(x: isOffscreen ? (reduceMotion ? 0 : Self.travel) : 0)
        .opacity(isOffscreen ? 0 : 1)
        // Only the exit is animated from here: `isLeaving` arrives as a new root view,
        // outside any `withAnimation`. Under Reduce Motion both ends become a cross-fade.
        .animation(reduceMotion
                   ? .easeOut(duration: 0.2)
                   : .easeIn(duration: Self.exitDuration), value: isLeaving)
        .onAppear {
            guard !reduceMotion else {
                entered = true
                return
            }
            // Eased, not bouncy: a banner settles into place, it doesn't overshoot.
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { entered = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        "Shift: \(content.headline). \(content.detail)"
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

            // Banner body text: same size as the title, regular weight, full contrast.
            Text(content.detail)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)

        }
        .padding(.horizontal, Theme.Space.base)
        .padding(.vertical, Theme.Space.snug + 1)
        .frame(width: 300, alignment: .leading)
        .background {
            // The same glass macOS draws notification banners on, so a nudge looks like
            // it belongs next to them. No tinted border any more: banners don't carry one,
            // and Flop's ears and colour already say which rung this is.
            if reduceTransparency {
                RoundedRectangle(cornerRadius: Theme.Radius.hud, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            } else {
                NotificationGlass(cornerRadius: Theme.Radius.hud)
            }
        }
        // No drop shadow. NSHostingView clips at the window bounds, so any shadow wide
        // enough to be worth having gets sliced off at the edge and leaves a hard grey
        // line across the desktop. The glass draws its own edge highlight instead.
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

// MARK: - Celebration

/// Eight small sparkles that fly out from Flop and fade, once.
private struct SparkleBurst: View {
    @State private var burst = false

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                let angle = Double(index) / 8 * 2 * .pi - .pi / 2
                let reach: CGFloat = index.isMultiple(of: 2) ? 86 : 64
                Image(systemName: index.isMultiple(of: 3) ? "sparkle" : "star.fill")
                    .font(.system(size: index.isMultiple(of: 2) ? 13 : 9, weight: .bold))
                    .foregroundStyle(index.isMultiple(of: 2)
                                     ? Color(red: 1.0, green: 0.82, blue: 0.36)
                                     : Color(red: 0.49, green: 0.86, blue: 0.78))
                    .offset(x: burst ? cos(angle) * reach : 0, y: burst ? sin(angle) * reach : 0)
                    .scaleEffect(burst ? 1 : 0.2)
                    .opacity(burst ? 0 : 1)
                    .rotationEffect(.degrees(burst ? 90 : 0))
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).delay(0.25)) { burst = true }
        }
    }
}
