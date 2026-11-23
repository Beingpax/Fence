import SwiftUI

/// The pause: one breath, one honest question, and a reason to close it.
///
/// The only full-screen surface in Shift. Each reach within the hour waits longer before
/// the question opens: 5, then 15, then 30 seconds. Every line on it comes from
/// `PauseCopy`, dealt so it doesn't repeat.
///
/// Design rules for this screen, worth keeping if it's changed:
///
/// 1. **One thing at a time.** During the breath there is no panel, only the breathing orb.
///    The question appears only once the breath is done, and choosing an answer replaces
///    the question. There's no way back from an answer: it ends in closing the tab.
/// 2. **The orb becomes the panel.** The breath and the question are one object changing
///    shape, so the moment it opens is felt rather than merely noticed.
/// 3. **Neutral glass, colour tiles.** Cards, panel and buttons are white glass; only the
///    feeling icons carry colour, as solid tiles drawn exactly like the sidebar's
///    (`SidebarIconTile`), so each is recognisable at a glance and the screen still feels
///    like part of the app. The breathing light takes its colours from the
///    time of day, to match the photo behind it.
/// 4. **Words arrive, they don't switch on.** Every line reveals letter by letter out of a
///    soft blur (`revealOnAppear`). Text that changes in place (`SwapText`) fully leaves
///    before the next line arrives, never overlapping.
/// 5. **Turning back is always the easiest thing.** The close button sits outside the
///    panel, is never disabled, and answers to Return.
struct PauseView: View {
    let request: PauseRequest
    let onEvent: (PauseEvent) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: Equatable {
        case breathing, asking, answering(UrgeReason)
    }

    @State private var phase: Phase = .breathing
    @State private var secondsLeft: Int
    @State private var breathStart: Date?
    @State private var cue = "Breathe in"
    @State private var hovered: UrgeReason?
    @State private var note = ""
    @State private var appeared = false
    @State private var questionShown = false
    @FocusState private var noteFocused: Bool
    @Namespace private var surface
    private let period = DayPeriod()

    init(request: PauseRequest, onEvent: @escaping (PauseEvent) -> Void) {
        self.request = request
        self.onEvent = onEvent
        _secondsLeft = State(initialValue: request.waitSeconds)
    }

    var body: some View {
        ZStack {
            PauseBackdrop(period: period)
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
            .frame(minHeight: 280)
            .entrance(appeared, delay: 0.5, distance: 24, reduceMotion: reduceMotion)

            closeButton
                .entrance(appeared, delay: 0.7, reduceMotion: reduceMotion)

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
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 2)
                    .accessibilityAddTraits(.isHeader)
                    .revealOnAppear(delay: 0.12, duration: 0.8)

                Text(request.subtitle)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 640)
                    .revealOnAppear(delay: 0.4, duration: 1.1)
            }

            Label(request.blockName, systemImage: "square.stack")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .entrance(appeared, delay: 0.55, reduceMotion: reduceMotion)
        }
    }

    // MARK: 1. The breath

    /// A constellation that opens and draws itself on the in-breath and gathers into a knot
    /// of light on the out-breath (`ConstellationBreath`). When the breath ends, the panel
    /// grows from its centre.
    private var orb: some View {
        VStack(spacing: Theme.Space.base) {
            ConstellationBreath(start: breathStart, animates: !reduceMotion)
                .frame(width: 560, height: 420)
                .background {
                    Circle()
                        .fill(.clear)
                        .frame(width: 180, height: 180)
                        .matchedGeometryEffect(id: "surface", in: surface)
                }

            VStack(spacing: 4) {
                SwapText(cue) {
                    $0.font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                }
                Text("\(secondsLeft)")
                    .font(.system(.callout, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                    .contentTransition(.numericText(countsDown: true))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cue). \(secondsLeft) seconds")
    }

    private func breathe() async {
        // Let the header land before the first breath starts.
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 600))
        guard !Task.isCancelled else { return }
        breathStart = Date()
        while secondsLeft > 0 {
            let step = (request.waitSeconds - secondsLeft) % 5
            if step == 0 || step == 3 {
                cue = step == 0 ? "Breathe in" : "And let it go"
            }
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            withAnimation { secondsLeft -= 1 }
        }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.62, dampingFraction: 0.84)) {
            phase = .asking
        }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 350))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.5)) { questionShown = true }
    }

    // MARK: The panel

    /// The frosted surface the orb grows into. A dark wash under the frost keeps white type
    /// readable on every backdrop, from the pale midday sky to the night one.
    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, Theme.Space.wide)
            .padding(.vertical, Theme.Space.wide)
            .frame(maxWidth: 620)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(.black.opacity(0.24))
                }
                .matchedGeometryEffect(id: "surface", in: surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.3), radius: 30, y: 14)
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
                    .revealOnAppear(delay: 0.3, duration: 0.85)
                Text("Pick the closest one. There’s no wrong answer.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .revealOnAppear(delay: 0.6, duration: 0.8)
            }

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
            SwapText(helperText, outDuration: 0.18, inDuration: 0.4) {
                $0.font(.callout).foregroundStyle(.white.opacity(0.75))
            }
            .frame(height: 20)
            .opacity(questionShown ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.7), value: questionShown)
        }
    }

    private var helperText: String {
        guard let hovered else { return "Or press 1 to \(choices.count)." }
        if hovered == .needed, let left = request.breaksLeft {
            return left == 0 ? "No breaks left today." : "\(hovered.feeling). \(left) break\(left == 1 ? "" : "s") left today."
        }
        return hovered.feeling
    }

    private func feelingChip(_ reason: UrgeReason, index: Int) -> some View {
        let disabled = reason == .needed && request.breaksLeft == 0
        return Button {
            note = ""
            hovered = nil
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
        // Each chip arrives a beat after the one before, once the question has settled.
        .opacity(questionShown ? 1 : 0)
        .scaleEffect(questionShown || reduceMotion ? 1 : 0.9)
        .offset(y: questionShown || reduceMotion ? 0 : 14)
        .blur(radius: questionShown || reduceMotion ? 0 : 6)
        .animation(
            reduceMotion ? .easeOut(duration: 0.2)
                : .spring(response: 0.55, dampingFraction: 0.78).delay(0.35 + Double(index) * 0.07),
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

    /// The suggestion for one answer. No way back to the question from here: having named
    /// it, the only thing left to do is close it (or, for "I need it", open it briefly).
    private func answer(for reason: UrgeReason) -> some View {
        let text = suggestion(for: reason)
        return VStack(spacing: Theme.Space.base) {
            SidebarIconTile(systemName: reason.symbol, background: Color.tint(for: reason), size: 56)
                .symbolEffect(.bounce, options: .nonRepeating, value: reason)
            .accessibilityHidden(true)

            Text(text.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .revealOnAppear(delay: 0.15, duration: 0.75)

            Text(text.body)
                .font(.body)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480)
                .revealOnAppear(delay: 0.4, duration: 1.2)

            if let plan = request.plans[reason], !plan.isEmpty {
                // Their own words, from the weekly review. A promise you made yourself
                // carries far more weight than any line an app could write.
                VStack(spacing: 2) {
                    Text("Your plan")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(reason.planLead) \(plan).")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, Theme.Space.base)
                .padding(.vertical, Theme.Space.snug)
                .frame(maxWidth: .infinity)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)) }
            }

            if reason == .needed {
                needed
            }
        }
        .transition(.asymmetric(insertion: .opacity, removal: .opacity))
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
                        .strokeBorder(.white.opacity(noteFocused ? 0.45 : 0.14))
                }
                .focused($noteFocused)
                .onAppear { noteFocused = true }

            HStack(spacing: Theme.Space.snug) {
                ForEach([1, 2], id: \.self) { minutes in
                    Button {
                        onEvent(.takeBreak(minutes: minutes, note: trimmed))
                    } label: {
                        Text("Open for \(minutes) min")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 130)
                            .padding(.vertical, Theme.Space.snug)
                            .background(.white.opacity(0.14), in: Capsule())
                            .overlay { Capsule().strokeBorder(.white.opacity(0.22)) }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
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

    private var chosen: UrgeReason? {
        if case .answering(let reason) = phase { return reason }
        return nil
    }

    /// Outside the panel, never disabled, and Return presses it. Turning back has to be the
    /// easiest thing on the screen. Once a feeling is chosen it becomes the one solid,
    /// white button on the screen: the obvious next step.
    private var closeButton: some View {
        let solid = chosen != nil && chosen != .needed
        let title = chosen == nil ? "I don’t need it. \(request.closeTitle)" : request.closeTitle
        return Button {
            onEvent(.close(chosen == .needed ? nil : chosen))
        } label: {
            Label(title, systemImage: request.isBrowser ? "xmark" : "power")
                .font(.body.weight(.semibold))
                .padding(.horizontal, Theme.Space.loose + 4)
                .padding(.vertical, Theme.Space.snug + 3)
                .foregroundStyle(solid ? Color.black.opacity(0.85) : .white)
                .background {
                    Capsule().fill(solid ? Color.white : Color.white.opacity(0.14))
                }
                .overlay { Capsule().strokeBorder(.white.opacity(solid ? 0 : 0.24)) }
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .keyboardShortcut(chosen == .needed ? nil : .defaultAction)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: solid)
    }
}

// MARK: - Pieces

/// One feeling: a sidebar-style colour tile, one word, and its number key, on neutral glass.
/// The card brightens and lifts under the pointer; only the tile carries colour.
private struct FeelingChip: View {
    let reason: UrgeReason
    let number: Int
    let highlighted: Bool

    var body: some View {
        HStack(spacing: Theme.Space.snug) {
            SidebarIconTile(systemName: reason.symbol, background: Color.tint(for: reason), size: 32)
                .symbolEffect(.bounce, value: highlighted)
            Text(reason.title)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            Text("\(number)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(highlighted ? 0.7 : 0.3))
        }
        .padding(.leading, Theme.Space.snug)
        .padding(.trailing, Theme.Space.base)
        .frame(height: 56)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(highlighted ? 0.18 : 0.07))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(highlighted ? 0.4 : 0.12), lineWidth: 1)
        }
        .scaleEffect(highlighted ? 1.03 : 1)
        .offset(y: highlighted ? -2 : 0)
        .shadow(color: .black.opacity(highlighted ? 0.25 : 0), radius: 12, y: 6)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: highlighted)
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
    /// Each feeling's tile colour: the same solid system colours the sidebar's icon tiles
    /// use, so the pause speaks the same visual language as the rest of the app.
    static func tint(for reason: UrgeReason) -> Color {
        switch reason {
        case .bored: Color(nsColor: .systemYellow)
        case .tired: Color(nsColor: .systemIndigo)
        case .stuck: Color(nsColor: .systemOrange)
        case .anxious: Color(nsColor: .systemTeal)
        case .lonely: Color(nsColor: .systemPink)
        case .needed: Color(nsColor: .systemGreen)
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
