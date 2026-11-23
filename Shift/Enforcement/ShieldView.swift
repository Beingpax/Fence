import AppKit
import SwiftUI

/// The full-screen shield: the third reach for a blocked site within an hour, after two pauses.
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
    @State private var reflection = ""
    @FocusState private var reflectionFocused: Bool

    init(request: ShieldRequest, showsControls: Bool, onResolve: @escaping (ShieldResolution) -> Void) {
        self.request = request
        self.showsControls = showsControls
        self.onResolve = onResolve
        _secondsLeft = State(initialValue: ShieldPolicy.countdownSeconds)
    }

    private var wordCount: Int { ShieldPolicy.wordCount(reflection) }
    private var wordsRemaining: Int { max(0, ShieldPolicy.minimumWords - wordCount) }

    private var unlocked: Bool {
        secondsLeft == 0 && wordCount >= ShieldPolicy.minimumWords
    }

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
                reflectionField
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

    private var reflectionField: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            Text("Be honest with yourself: what were you working on, and what keeps pulling you away?")
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("", text: $reflection, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(3...5)
                .padding(Theme.Space.snug)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .focused($reflectionFocused)
                .onAppear { reflectionFocused = true }

            HStack(spacing: Theme.Space.tight) {
                // A quiet progress bar rather than a scold. It fills as you write.
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule()
                            .fill(unlockedWords ? Color.green.opacity(0.75) : Palette.accent)
                            .frame(width: geometry.size.width *
                                   min(1, Double(wordCount) / Double(ShieldPolicy.minimumWords)))
                    }
                }
                .frame(height: 4)

                Text(wordsRemaining == 0
                     ? "Enough — thank you"
                     : "\(wordsRemaining) more word\(wordsRemaining == 1 ? "" : "s")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize()
            }
            .animation(.easeOut(duration: 0.2), value: wordCount)
        }
        .frame(maxWidth: 420)
        .multilineTextAlignment(.leading)
    }

    private var unlockedWords: Bool { wordCount >= ShieldPolicy.minimumWords }

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
