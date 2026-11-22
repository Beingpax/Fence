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
    /// A sunrise, not an alarm.
    ///
    /// The old backdrop was a dark red bloom, which made the shield read as a punishment
    /// screen. That fights the product: Shift sells friction, not a prison, and this
    /// appears *after* three nudges have already been ignored — being louder at this
    /// point adds nothing. A dawn sky says "start the day again" instead, and its dark
    /// upper half still carries white type at full contrast.
    private enum Palette {
        static let night = Color(red: 0.05, green: 0.07, blue: 0.15)
        static let dusk = Color(red: 0.16, green: 0.13, blue: 0.29)
        static let violet = Color(red: 0.40, green: 0.21, blue: 0.36)
        static let ember = Color(red: 0.76, green: 0.37, blue: 0.31)
        static let horizon = Color(red: 0.96, green: 0.63, blue: 0.38)
        static let sun = Color(red: 1.0, green: 0.84, blue: 0.56)

        static let accent = Color(red: 1.0, green: 0.84, blue: 0.66)
        static let action = Color(red: 0.90, green: 0.45, blue: 0.30)
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
            // A real photograph rather than a gradient. A hand-rolled sky always looks
            // hand-rolled at full-screen size, and this is the one surface in the app
            // that fills a display. Twilight over dunes: dark enough overhead to carry
            // white type at full contrast, with the horizon already glowing — the shield
            // should read as "start again", not as a punishment screen.
            // Tim de Groot, Unsplash License. See CREDITS.md.
            Palette.night
            Image("ShieldDawn")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .opacity(1)

            // Scrim. Deliberately light: the sky in this photograph is already dark
            // enough to carry white type, so the scrim only has to steady it. Heavier
            // and the photograph may as well not be there.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.40), location: 0.0),
                    .init(color: .black.opacity(0.26), location: 0.42),
                    .init(color: .black.opacity(0.05), location: 0.74),
                    .init(color: .black.opacity(0.24), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )

            // Vignette: holds the eye in the middle and keeps the corners quiet.
            RadialGradient(
                colors: [.clear, .black.opacity(0.22)],
                center: .center, startRadius: 420, endRadius: 1150
            )
        }
        .clipped()
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(spacing: Theme.Space.loose) {
            // Haloed, so the badge sits inside the bloom rather than on top of it.
            // A rising sun rather than a shield. The glyph should agree with the sky
            // behind it; a red shield on a sunrise reads as two screens fighting.
            // A rising sun rather than a shield: the glyph has to agree with the sky
            // behind it. No halo — a blurred disc on top of a gradient only ever reads
            // as a smudge, and the sky is already supplying the warmth.
            BlockBadge(symbol: "sun.horizon.fill", tint: .orange, size: 62)

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
