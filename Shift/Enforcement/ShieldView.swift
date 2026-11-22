import AppKit
import SwiftUI

/// The full-screen shield: the last rung of `NudgeLadder`, after the nudges are spent.
///
/// One tier, not three. The escalation lives in the ladder now, so by the time this appears
/// the user has already been asked three times — which is why the wait and the phrase are
/// unconditional. It carries the same rose as the last nudge, so the arc reads as one thing.
struct ShieldView: View {
    let request: ShieldRequest
    let showsControls: Bool
    let onResolve: (ShieldResolution) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var secondsLeft: Int
    @State private var typedPhrase = ""
    @FocusState private var phraseFocused: Bool

    init(request: ShieldRequest, showsControls: Bool, onResolve: @escaping (ShieldResolution) -> Void) {
        self.request = request
        self.showsControls = showsControls
        self.onResolve = onResolve
        _secondsLeft = State(initialValue: ShieldPolicy.countdownSeconds)
    }

    private var unlocked: Bool {
        let phraseMatches = typedPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(ShieldPolicy.phrase) == .orderedSame
        return secondsLeft == 0 && phraseMatches
    }

    /// One hue, lit from one direction.
    ///
    /// The old backdrop stacked a maroon bloom and an indigo bloom over a navy ground;
    /// three hues at low saturation average out to mud, and the action button was so dark
    /// against it that an enabled button looked disabled. So: a neutral near-black ground,
    /// a single rose bloom behind the headline, and an action colour bright enough that
    /// dimming it to 0.48 still reads as "not yet" rather than "broken".
    private enum Palette {
        static let ground = Color(red: 0.055, green: 0.059, blue: 0.078)
        static let bloom = Color(red: 0.62, green: 0.14, blue: 0.28)
        static let accent = Color(red: 1, green: 0.72, blue: 0.74)
        static let action = Color(red: 0.89, green: 0.26, blue: 0.35)
    }

    var body: some View {
        ZStack {
            backdrop
            if showsControls {
                GeometryReader { geometry in
                    ScrollView {
                        content
                            .frame(minHeight: geometry.size.height)
                            .frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .task { await runCountdown() }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var backdrop: some View {
        ZStack {
            if !reduceTransparency {
                BehindWindowBlur(material: .fullScreenUI)
            }
            Palette.ground.opacity(reduceTransparency ? 1 : 0.95)

            // One bloom, sitting behind the headline, so the backdrop reads as light
            // falling on the message rather than as a gradient for its own sake.
            EllipticalGradient(
                colors: [Palette.bloom.opacity(0.66), Palette.bloom.opacity(0.17), .clear],
                center: UnitPoint(x: 0.5, y: 0.32),
                startRadiusFraction: 0, endRadiusFraction: 0.78
            )

            // Vignette. Holds the eye in the middle and hides where the bloom runs out.
            RadialGradient(
                colors: [.clear, .black.opacity(0.5)],
                center: .center, startRadius: 300, endRadius: 1020
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(spacing: Theme.Space.loose) {
            // Haloed, so the badge sits inside the bloom rather than on top of it.
            BlockBadge(symbol: "shield.lefthalf.filled", tint: .pink, size: 62)
                .background {
                    Circle()
                        .fill(Palette.action)
                        .frame(width: 112, height: 112)
                        .blur(radius: 44)
                        .opacity(0.42)
                }

            VStack(spacing: Theme.Space.snug) {
                Text("Not now.")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)

                Text(request.reason)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
            }

            Label(request.blockName, systemImage: "square.stack")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))

            VStack(spacing: Theme.Space.base) {
                ladderBadge

                phraseField
                actions
            }
            .padding(Theme.Space.loose)
            .frame(maxWidth: 420)
            // Lighter than the ground, not darker: on a near-black backdrop an elevated
            // surface has to catch light, or the panel disappears into the page.
            .background(Color.white.opacity(reduceTransparency ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.panel)
                    .strokeBorder(.white.opacity(0.12))
                    .allowsHitTesting(false)
            }

            if request.isPreview {
                Text("Shield preview")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(Theme.Space.vast)
        .frame(maxWidth: 720)
        .multilineTextAlignment(.center)
    }

    /// Says why the screen is covered: the nudges ran out.
    private var ladderBadge: some View {
        Label("\(NudgeLadder.stepCount) nudges, then this", systemImage: "hand.raised.fill")
            .font(.callout.weight(.semibold))
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, Theme.Space.base)
            .padding(.vertical, Theme.Space.tight)
            .background(Palette.accent.opacity(0.12), in: Capsule())
    }

    private var phraseField: some View {
        VStack(spacing: Theme.Space.tight) {
            Text("Type “\(ShieldPolicy.phrase)” to continue")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.82))
            TextField("Type the phrase", text: $typedPhrase)
                .textFieldStyle(.plain)
                .padding(Theme.Space.snug)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .focused($phraseFocused)
                .onAppear { phraseFocused = true }
        }
        .frame(maxWidth: 380)
    }

    private var actions: some View {
        VStack(spacing: Theme.Space.snug) {
            if secondsLeft > 0 {
                Text("Actions available in \(secondsLeft)s")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Palette.accent)
            }

            Button {
                onResolve(.quitApp)
            } label: {
                Label(request.primaryActionTitle, systemImage: "power")
                    .frame(minWidth: 180)
            }
            .buttonStyle(.shiftProminent(Palette.action))
            .disabled(!unlocked)
            .opacity(unlocked ? 1 : 0.48)
            .keyboardShortcut(.defaultAction)

            if let minutes = request.breakMinutes {
                Button {
                    onResolve(.takeBreak)
                } label: {
                    Label("Pause for \(minutes) minutes", systemImage: "pause")
                }
                .buttonStyle(.shiftSoft)
                .disabled(!unlocked)
                .opacity(unlocked ? 1 : 0.48)
            }
        }
    }

    private func runCountdown() async {
        while secondsLeft > 0 {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            secondsLeft -= 1
        }
    }
}
