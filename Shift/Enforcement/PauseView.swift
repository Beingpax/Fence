import SwiftUI

/// The pause: one breath, one honest question, and a reason to close it.
///
/// The only full-screen surface in Shift. It used to be followed by a separate shield; now
/// it simply gets longer each time (5, 15, then 30 seconds before the choices open).
/// Every screen follows a few rules from habit research, so check new copy against them:
///
/// 1. **Catch the cue, before the reward.** The pause lands while the page is still
///    loading. A feed that never pays out stops being worth reaching for.
/// 2. **No shame.** Shame makes people fight the tool, not change. The voice is a
///    friend's: warm, on your side. The urge is "the pull", not you.
/// 3. **Name the craving.** Putting a feeling into words weakens it and turns autopilot
///    into a decision.
/// 4. **Point at something better, then close it.** Each answer says what would actually
///    meet that need, and the only button closes the page. The person does the better
///    thing themselves.
/// 5. **Real needs are allowed, honestly.** "I need it" asks what for, then spends one of
///    the block's breaks. It only exists when the block allows breaks.
struct PauseView: View {
    let request: PauseRequest
    let onEvent: (PauseEvent) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var reason: UrgeReason?
    @State private var secondsLeft: Int
    @State private var inhaling = false
    @State private var cue = "Breathe in…"
    @State private var note = ""
    @State private var appeared = false
    @FocusState private var noteFocused: Bool

    private enum Palette {
        static let accent = Color(red: 1.0, green: 0.84, blue: 0.66)
        static let action = Color(red: 0.90, green: 0.45, blue: 0.30)
    }

    init(request: PauseRequest, onEvent: @escaping (PauseEvent) -> Void) {
        self.request = request
        self.onEvent = onEvent
        _secondsLeft = State(initialValue: request.waitSeconds)
    }

    var body: some View {
        ZStack {
            PauseBackdrop()
            GeometryReader { geometry in
                ScrollView {
                    content
                        .frame(minHeight: geometry.size.height)
                        .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .task { await breathe() }
        }
        .onAppear { appeared = true }
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.88), value: reason)
    }

    private var content: some View {
        VStack(spacing: Theme.Space.loose) {
            ZStack {
                Circle()
                    .fill(Palette.accent.opacity(0.18))
                    .frame(width: 112, height: 112)
                    .scaleEffect(reduceMotion ? 1 : (inhaling ? 1.15 : 0.8))
                    .opacity(secondsLeft > 0 ? 1 : 0)
                BlockBadge(symbol: "wind", tint: .orange, size: 62)
            }
            .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
            .entrance(appeared, delay: 0.05, reduceMotion: reduceMotion)
            .accessibilityHidden(true)

            VStack(spacing: Theme.Space.snug) {
                Text(headline.title)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 2)
                    .accessibilityAddTraits(.isHeader)
                    .entrance(appeared, delay: 0.14, reduceMotion: reduceMotion)

                Text(headline.subtitle)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.88))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .entrance(appeared, delay: 0.22, reduceMotion: reduceMotion)
            }

            Label(request.blockName, systemImage: "square.stack")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .entrance(appeared, delay: 0.28, reduceMotion: reduceMotion)

            VStack(spacing: Theme.Space.base) {
                if let reason {
                    answer(for: reason)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                } else {
                    question
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .padding(Theme.Space.loose)
            .frame(maxWidth: 520)
            // Frosted, so it reads on a bright midday sky as well as on the night one.
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.panel)
                    .strokeBorder(.white.opacity(0.16))
                    .allowsHitTesting(false)
            }
            .entrance(appeared, delay: 0.36, distance: 40, reduceMotion: reduceMotion)

            if request.isPreview {
                Text("Pause preview")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(Theme.Space.vast)
        .frame(maxWidth: 760)
        .multilineTextAlignment(.center)
    }

    /// Gentle the first time, warmer and more patient after that. Never a scolding: by the
    /// third reach the person already knows, and shame only makes them fight the tool.
    private var headline: (title: String, subtitle: String) {
        switch request.visit {
        case ...1:
            ("Take a breath.",
             "You reached for \(request.target). Before it pulls you in, check in with yourself.")
        case 2:
            ("Back again.",
             "That’s the pull, not you. Urges rise, peak and fade, usually within a minute. Ride this one out.")
        default:
            ("Third time this hour.",
             "The pull is strong today, and that’s okay. Sit with it for thirty seconds, then choose.")
        }
    }

    // MARK: The question

    private var choices: [UrgeReason] {
        UrgeReason.allCases.filter { $0 != .needed || request.breaksLeft != nil }
    }

    private var question: some View {
        VStack(spacing: Theme.Space.base) {
            Text("What were you hoping it would give you?")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            if secondsLeft > 0 {
                Text("\(cue)  ·  choices in \(secondsLeft)s")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Palette.accent)
                    .contentTransition(.opacity)
            } else {
                Text("Whatever it is, it’s a real need. Let’s meet it properly.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.snug),
                                GridItem(.flexible(), spacing: Theme.Space.snug)],
                      spacing: Theme.Space.snug) {
                ForEach(Array(choices.enumerated()), id: \.element) { index, choice in
                    let outOfBreaks = choice == .needed && request.breaksLeft == 0
                    Button {
                        note = ""
                        reason = choice
                    } label: {
                        ChoiceLabel(
                            reason: choice,
                            detail: outOfBreaks ? "No breaks left today" : choice.feeling
                        )
                    }
                    .buttonStyle(ChoiceButtonStyle())
                    .disabled(secondsLeft > 0 || outOfBreaks)
                    .opacity(secondsLeft > 0 || outOfBreaks ? 0.45 : 1)
                    // The choices light up one after another as the breath ends, so the
                    // moment they open is felt rather than merely noticed.
                    .animation(.easeOut(duration: 0.35).delay(Double(index) * 0.06), value: secondsLeft > 0)
                }
            }

            closeButton(title: "I don’t need it. \(request.closeTitle)", reason: nil)
                .padding(.top, Theme.Space.tight)
        }
    }

    // MARK: The answer

    private func suggestion(for reason: UrgeReason) -> (title: String, body: String) {
        switch reason {
        case .bored:
            ("Give your mind something real.",
             "The feed promises something new and serves more of the same. Close it, stand up, stretch, and look at something far away for a minute.")
        case .tired:
            ("You need rest, not more input.",
             "Scrolling feels like rest, but it keeps your brain working. Close it, shut your eyes, and let your shoulders drop for two minutes.")
        case .stuck:
            ("Make it smaller.",
             "Hard work feels like a wall. A tiny next step is a door. Close this and write down one thing you could do in the next two minutes.")
        case .anxious:
            ("Put it on paper, not in a feed.",
             "A feed only adds noise to whatever you’re carrying. Close it and write down what’s on your mind. Out of your head, it gets lighter.")
        case .lonely:
            ("Reach a real person.",
             "A feed shows you people without giving you any of them. Close it and send one message to someone you actually like.")
        case .needed:
            ("Name it, then take a short break.",
             "Say exactly what you need it for. “\(request.blockName)” pauses while you do it and comes back on its own.")
        }
    }

    private func answer(for reason: UrgeReason) -> some View {
        let text = suggestion(for: reason)
        return VStack(spacing: Theme.Space.base) {
            if let plan = request.plans[reason], !plan.isEmpty {
                // Their own words, from the weekly review. A promise you made yourself
                // carries far more weight than any line an app could write.
                VStack(spacing: 2) {
                    Text("Your plan")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                    Text("\(reason.planLead) \(plan).")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, Theme.Space.base)
                .padding(.vertical, Theme.Space.snug)
                .frame(maxWidth: .infinity)
                .background(Palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text(text.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(text.body)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            if reason == .needed {
                needed
            } else {
                closeButton(title: request.closeTitle, reason: reason)
                    .padding(.top, Theme.Space.tight)
            }

            Button("Something else") {
                note = ""
                self.reason = nil
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var needed: some View {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let left = request.breaksLeft ?? 0
        return VStack(spacing: Theme.Space.snug) {
            TextField("Like “reply to Sam about Friday”", text: $note)
                .textFieldStyle(.plain)
                .font(.callout)
                .multilineTextAlignment(.leading)
                .padding(Theme.Space.snug)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .focused($noteFocused)
                .onAppear { noteFocused = true }

            HStack(spacing: Theme.Space.snug) {
                ForEach([1, 2], id: \.self) { minutes in
                    Button {
                        onEvent(.takeBreak(minutes: minutes, note: trimmed))
                    } label: {
                        Text("\(minutes) minute\(minutes == 1 ? "" : "s")")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.shiftSoft)
                    .disabled(trimmed.isEmpty)
                    .opacity(trimmed.isEmpty ? 0.48 : 1)
                }
            }

            Text("Uses one of today’s breaks. \(left) left.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

            closeButton(title: "Actually, \(request.closeTitle.lowercased())", reason: nil)
                .padding(.top, Theme.Space.tight)
        }
    }

    // MARK: Pieces

    /// Always available, from the first second. Turning back has to be the easiest thing
    /// on the screen.
    private func closeButton(title: String, reason: UrgeReason?) -> some View {
        Button {
            onEvent(.close(reason))
        } label: {
            Label(title, systemImage: request.isBrowser ? "xmark.square" : "power")
                .frame(minWidth: 200)
        }
        .buttonStyle(.shiftProminent(Palette.action))
        .keyboardShortcut(.defaultAction)
    }

    private func breathe() async {
        while secondsLeft > 0 {
            let phase = (request.waitSeconds - secondsLeft) % 5
            if phase == 0 || phase == 3 {
                withAnimation(.easeInOut(duration: 2.5)) {
                    inhaling = phase == 0
                    cue = phase == 0 ? "Breathe in…" : "And let it go…"
                }
            }
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            secondsLeft -= 1
        }
    }
}

private struct ChoiceLabel: View {
    let reason: UrgeReason
    let detail: String

    var body: some View {
        HStack(spacing: Theme.Space.snug) {
            Image(systemName: reason.symbol)
                .font(.title3)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(reason.title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, Theme.Space.base)
        .padding(.vertical, Theme.Space.snug + 2)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ChoiceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(hovering ? 0.16 : 0.08))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(hovering ? 0.35 : 0.14), lineWidth: 1)
                }
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}

private extension View {
    /// Fades and lifts a piece into place, a beat after the one before it.
    func entrance(_ shown: Bool, delay: Double, distance: CGFloat = 18, reduceMotion: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : distance)
            .animation(
                reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.7, dampingFraction: 0.82).delay(delay),
                value: shown
            )
    }
}
