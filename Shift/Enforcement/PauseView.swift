import SwiftUI

/// The pause: one breath, one honest question, and a reason to close it.
///
/// The only full-screen surface in Shift. Each reach within the hour waits longer before
/// the question opens: 5, then 15, then 30 seconds. Every line on it comes from
/// `PauseCopy`, dealt so it doesn't repeat.
///
/// The question section follows a few design rules, worth keeping if it's changed:
///
/// 1. **One thing at a time.** During the breath there is no panel, only a breathing orb.
///    The question appears only once the breath is done, and the answer replaces the
///    question rather than stacking under it.
/// 2. **The orb becomes the panel.** The breath and the question are one object changing
///    shape, so the moment it opens is felt rather than merely noticed.
/// 3. **Feelings, not form fields.** Six short words, each with its own colour and symbol,
///    so the right one is recognised at a glance (Hick's law: fewer, clearer choices decide
///    faster). The longer description only appears on hover.
/// 4. **Turning back is always the easiest thing.** The close button sits outside the
///    panel, is never disabled, and answers to Return.
/// 5. **No shame.** The voice is a friend's. The urge is "the pull", not the person.
struct PauseView: View {
    let request: PauseRequest
    let onEvent: (PauseEvent) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: Equatable {
        case breathing, asking, answering(UrgeReason)
    }

    @State private var phase: Phase = .breathing
    @State private var secondsLeft: Int
    @State private var inhaling = false
    @State private var cue = "Breathe in"
    @State private var hovered: UrgeReason?
    @State private var note = ""
    @State private var appeared = false
    @State private var questionShown = false
    @FocusState private var noteFocused: Bool
    @Namespace private var surface

    private enum Palette {
        static let action = Color(red: 0.92, green: 0.47, blue: 0.32)
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
        .environment(\.colorScheme, .dark)
        .onAppear { appeared = true }
    }

    private var content: some View {
        VStack(spacing: Theme.Space.loose) {
            header

            ZStack {
                switch phase {
                case .breathing:
                    orb
                case .asking:
                    panel { question }
                case .answering(let reason):
                    panel { answer(for: reason) }
                }
            }
            .frame(minHeight: 260)
            .entrance(appeared, delay: 0.34, distance: 30, reduceMotion: reduceMotion)

            closeButton(title: phase == .breathing || phase == .asking
                        ? "I don’t need it. \(request.closeTitle)"
                        : request.closeTitle,
                        reason: currentReason)
                .entrance(appeared, delay: 0.46, reduceMotion: reduceMotion)

            if request.isPreview {
                Text("Pause preview")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(Theme.Space.vast)
        .frame(maxWidth: 820)
        .multilineTextAlignment(.center)
    }

    private var currentReason: UrgeReason? {
        if case .answering(let reason) = phase, reason != .needed { return reason }
        return nil
    }

    // MARK: Header (the same through every phase)

    private var header: some View {
        VStack(spacing: Theme.Space.base) {
            BlockBadge(symbol: "wind", tint: .orange, size: 62)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
                .entrance(appeared, delay: 0.05, reduceMotion: reduceMotion)
                .accessibilityHidden(true)

            VStack(spacing: Theme.Space.snug) {
                Text(request.title)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 2)
                    .accessibilityAddTraits(.isHeader)
                    .entrance(appeared, delay: 0.14, reduceMotion: reduceMotion)

                Text(request.subtitle)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.88))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 640)
                    .entrance(appeared, delay: 0.22, reduceMotion: reduceMotion)
            }

            Label(request.blockName, systemImage: "square.stack")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .entrance(appeared, delay: 0.28, reduceMotion: reduceMotion)
        }
    }

    // MARK: 1. The breath

    /// A frosted orb that swells and settles with the breath, with a thin ring that empties
    /// as the wait runs out. When the breath ends, it grows into the question panel.
    private var orb: some View {
        let progress = 1 - Double(secondsLeft) / Double(max(request.waitSeconds, 1))
        return ZStack {
            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: 236, height: 236)
                .scaleEffect(reduceMotion ? 1 : (inhaling ? 1.12 : 0.86))
                .blur(radius: 18)

            Circle()
                .fill(.ultraThinMaterial)
                .matchedGeometryEffect(id: "surface", in: surface)
                .frame(width: 176, height: 176)
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }
                .scaleEffect(reduceMotion ? 1 : (inhaling ? 1.06 : 0.94))

            Circle()
                .trim(from: 0, to: 1 - progress)
                .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 198, height: 198)
                .animation(.linear(duration: 1), value: secondsLeft)

            VStack(spacing: 4) {
                Text(cue)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)
                Text("\(secondsLeft)")
                    .font(.system(.callout, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                    .contentTransition(.numericText(countsDown: true))
            }
        }
        .frame(height: 260)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cue). \(secondsLeft) seconds")
    }

    private func breathe() async {
        while secondsLeft > 0 {
            let elapsed = request.waitSeconds - secondsLeft
            let step = elapsed % 5
            if step == 0 || step == 3 {
                withAnimation(.easeInOut(duration: step == 0 ? 3 : 2)) {
                    inhaling = step == 0
                    cue = step == 0 ? "Breathe in" : "And let it go"
                }
            }
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            withAnimation { secondsLeft -= 1 }
        }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.62, dampingFraction: 0.84)) {
            phase = .asking
        }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 220))
        withAnimation(.easeOut(duration: 0.5)) { questionShown = true }
    }

    // MARK: The panel

    /// The frosted surface the orb grows into. It resizes smoothly between the question
    /// and an answer.
    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, Theme.Space.wide)
            .padding(.vertical, Theme.Space.wide)
            .frame(maxWidth: 640)
            .background {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .matchedGeometryEffect(id: "surface", in: surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.06)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.28), radius: 30, y: 14)
    }

    // MARK: 2. The question

    private var choices: [UrgeReason] {
        UrgeReason.allCases.filter { $0 != .needed || request.breaksLeft != nil }
    }

    private var question: some View {
        VStack(spacing: Theme.Space.loose) {
            VStack(spacing: Theme.Space.tight) {
                Text("What were you hoping it would give you?")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Pick the closest one. There’s no wrong answer.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
            }
            // Comes into focus rather than just appearing.
            .blur(radius: questionShown || reduceMotion ? 0 : 10)
            .opacity(questionShown ? 1 : 0)
            .offset(y: questionShown || reduceMotion ? 0 : 8)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.snug), count: 3),
                spacing: Theme.Space.snug
            ) {
                ForEach(Array(choices.enumerated()), id: \.element) { index, choice in
                    feelingChip(choice, index: index)
                }
            }

            // One helper line, filled by whatever is under the pointer, instead of six
            // descriptions competing for attention at once.
            Text(helperText)
                .font(.callout)
                .foregroundStyle(hovered.map { Color.tint(for: $0) } ?? .white.opacity(0.6))
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.15), value: hovered)
                .frame(height: 20)
                .opacity(questionShown ? 1 : 0)
        }
    }

    private var helperText: String {
        guard let hovered else { return "You can also press 1 to \(choices.count)." }
        if hovered == .needed, let left = request.breaksLeft {
            return left == 0 ? "No breaks left today." : "\(hovered.feeling). \(left) break\(left == 1 ? "" : "s") left today."
        }
        return hovered.feeling
    }

    private func feelingChip(_ reason: UrgeReason, index: Int) -> some View {
        let disabled = reason == .needed && request.breaksLeft == 0
        return Button {
            note = ""
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.86)) {
                phase = .answering(reason)
            }
        } label: {
            FeelingChip(reason: reason, number: index + 1, highlighted: hovered == reason)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
        .onHover { inside in
            if inside { hovered = reason } else if hovered == reason { hovered = nil }
        }
        // Each chip arrives a beat after the one before, once the question is in focus.
        .opacity(questionShown ? 1 : 0)
        .scaleEffect(questionShown || reduceMotion ? 1 : 0.86)
        .offset(y: questionShown || reduceMotion ? 0 : 12)
        .animation(
            reduceMotion ? .easeOut(duration: 0.2)
                : .spring(response: 0.5, dampingFraction: 0.74).delay(0.18 + Double(index) * 0.06),
            value: questionShown
        )
    }

    // MARK: 3. The answer

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
            ("Name it, and it’s yours for a minute.",
             "Say exactly what you need \(request.target) for. Just this site opens; everything else in “\(request.blockName)” stays blocked.")
        }
    }

    private func answer(for reason: UrgeReason) -> some View {
        let text = suggestion(for: reason)
        let tint = Color.tint(for: reason)
        return VStack(spacing: Theme.Space.base) {
            ZStack {
                Circle().fill(tint.opacity(0.22)).frame(width: 64, height: 64)
                Image(systemName: reason.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)

            Text(text.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(text.body)
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480)

            if let plan = request.plans[reason], !plan.isEmpty {
                // Their own words, from the weekly review. A promise you made yourself
                // carries far more weight than any line an app could write.
                VStack(spacing: 2) {
                    Text("Your plan")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                    Text("\(reason.planLead) \(plan).")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, Theme.Space.base)
                .padding(.vertical, Theme.Space.snug)
                .frame(maxWidth: .infinity)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if reason == .needed {
                needed
            }

            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.86)) {
                    note = ""
                    phase = .asking
                }
            } label: {
                Label("Something else", systemImage: "chevron.left")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.65))
            .padding(.top, Theme.Space.tight)
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 14)),
            removal: .opacity
        ))
    }

    private var needed: some View {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(spacing: Theme.Space.snug) {
            TextField("Like “reply to Sam about Friday”", text: $note)
                .textFieldStyle(.plain)
                .font(.body)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, Theme.Space.base)
                .padding(.vertical, Theme.Space.snug + 2)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(noteFocused ? Color.tint(for: .needed).opacity(0.7) : .white.opacity(0.12))
                }
                .focused($noteFocused)
                .onAppear { noteFocused = true }

            HStack(spacing: Theme.Space.snug) {
                ForEach([1, 2], id: \.self) { minutes in
                    Button {
                        onEvent(.takeBreak(minutes: minutes, note: trimmed))
                    } label: {
                        Text("Open for \(minutes) min")
                            .frame(minWidth: 130)
                    }
                    .buttonStyle(.shiftProminent(Color.tint(for: .needed).opacity(0.85)))
                    .disabled(trimmed.isEmpty)
                    .opacity(trimmed.isEmpty ? 0.45 : 1)
                }
            }

            if let left = request.breaksLeft {
                Text("Uses one of today’s breaks. \(left) left.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.top, Theme.Space.tight)
    }

    // MARK: The way out

    /// Outside the panel, never disabled, and Return presses it. Turning back has to be the
    /// easiest thing on the screen.
    private func closeButton(title: String, reason: UrgeReason?) -> some View {
        Button {
            onEvent(.close(reason))
        } label: {
            Label(title, systemImage: request.isBrowser ? "xmark" : "power")
                .font(.body.weight(.semibold))
                .padding(.horizontal, Theme.Space.loose)
                .padding(.vertical, Theme.Space.snug + 2)
                .foregroundStyle(.white)
                .background {
                    Capsule().fill(currentReason == nil ? Color.white.opacity(0.14) : Palette.action)
                }
                .overlay { Capsule().strokeBorder(.white.opacity(0.22)) }
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .keyboardShortcut(phase == .answering(.needed) ? nil : .defaultAction)
        .animation(.easeOut(duration: 0.2), value: currentReason)
    }
}

// MARK: - Pieces

private struct FeelingChip: View {
    let reason: UrgeReason
    let number: Int
    let highlighted: Bool

    var body: some View {
        let tint = Color.tint(for: reason)
        HStack(spacing: Theme.Space.snug) {
            ZStack {
                Circle().fill(tint.opacity(highlighted ? 0.34 : 0.2)).frame(width: 34, height: 34)
                Image(systemName: reason.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(reason.title)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            Text("\(number)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(highlighted ? 0.7 : 0.35))
        }
        .padding(.leading, Theme.Space.snug)
        .padding(.trailing, Theme.Space.base)
        .frame(height: 56)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(highlighted ? tint.opacity(0.22) : .white.opacity(0.07))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(highlighted ? tint.opacity(0.75) : .white.opacity(0.12), lineWidth: highlighted ? 1.5 : 1)
        }
        .scaleEffect(highlighted ? 1.035 : 1)
        .shadow(color: highlighted ? tint.opacity(0.35) : .clear, radius: 14, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: highlighted)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("\(reason.title). \(reason.feeling)")
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private extension Color {
    /// Each feeling has its own colour, so it can be recognised before it's read. Warm for
    /// restless states, cool for low-energy ones.
    static func tint(for reason: UrgeReason) -> Color {
        switch reason {
        case .bored: Color(red: 1.0, green: 0.80, blue: 0.32)
        case .tired: Color(red: 0.62, green: 0.66, blue: 1.0)
        case .stuck: Color(red: 1.0, green: 0.58, blue: 0.38)
        case .anxious: Color(red: 0.42, green: 0.86, blue: 0.80)
        case .lonely: Color(red: 1.0, green: 0.58, blue: 0.72)
        case .needed: Color(red: 0.56, green: 0.86, blue: 0.48)
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
