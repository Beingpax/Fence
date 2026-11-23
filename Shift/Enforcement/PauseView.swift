import SwiftUI

/// The pause: one breath, one honest question, and a reason to close it.
///
/// The only full-screen surface in Shift. Each reach within the hour waits longer before
/// the question opens: 10, then 20, then 30 seconds. The opening copy comes from
/// `PauseCopy` and the matched rule explains why the screen appeared.
///
/// Design rules for this screen, worth keeping if it's changed:
///
/// 1. **One thing at a time.** During the breath there is no panel, only the constellation
///    and a bar that empties. No cue to read, no digits to watch.
///    The question appears only once the breath is done, and choosing an answer replaces
///    the question. “I need it” can lead to a separate wait for temporary access.
/// 2. **The orb becomes the panel.** The breath and the question are one object changing
///    shape, so the moment it opens is felt rather than merely noticed.
/// 3. **Frosted panel, solid buttons.** The panel uses neutral glass and every button uses
///    a white fill with dark text. The feeling icons use the same coloured tiles as the sidebar.
/// 4. **Words arrive, they don't switch on.** Each line fades in at its own pace
///    (`revealOnAppear`). Text that changes in place (`SwapText`) fully leaves
///    before the next line arrives, never overlapping.
/// 5. **Keep the close button visible.** It sits outside the panel and answers to Return
///    outside the reason form.
struct PauseView: View {
    let request: PauseRequest
    let wallpaper: PauseWallpaper
    let onEvent: (PauseEvent) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: Equatable {
        case breathing, asking, answering(UrgeReason)
        case waitingForAccess(minutes: Int, note: String)
    }

    @State private var phase: Phase = .breathing
    @State private var secondsLeft: Int
    @State private var accessWaitSecondsLeft = BreakPlan.waitSeconds
    @State private var breathStart: Date?
    /// The fraction remaining in the current wait.
    @State private var drain: Double = 1
    @State private var hovered: UrgeReason?
    @State private var note = ""
    @State private var appeared = false
    @State private var questionShown = false
    @FocusState private var noteFocused: Bool
    @Namespace private var surface
    init(request: PauseRequest, wallpaper: PauseWallpaper, onEvent: @escaping (PauseEvent) -> Void) {
        self.request = request
        self.wallpaper = wallpaper
        self.onEvent = onEvent
        _secondsLeft = State(initialValue: request.waitSeconds)
    }

    var body: some View {
        ZStack {
            PauseBackdrop(wallpaper: wallpaper)
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
        .task { await wallpaper.followClock() }
        .task(id: phase) {
            if case let .waitingForAccess(minutes, note) = phase {
                await waitForAccess(minutes: minutes, note: note)
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { appeared = true }
    }

    private var content: some View {
        VStack(spacing: Theme.Space.wide) {
            header

            ZStack {
                switch phase {
                case .breathing:
                    orb
                case .asking:
                    panel { question }
                case .answering(let reason):
                    panel { answer(for: reason) }
                case .waitingForAccess(let minutes, _):
                    panel { accessWait(minutes: minutes) }
                }
            }
            .frame(minHeight: 280)
            .entrance(appeared, delay: 0.5, distance: 24, reduceMotion: reduceMotion)

            closeButton
                .entrance(appeared, delay: 0.7, reduceMotion: reduceMotion)

            if request.isPreview {
                Text("Pause preview")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(Theme.Space.vast)
        .frame(maxWidth: 820)
        .multilineTextAlignment(.center)
    }

    // MARK: Header (the same through every phase)

    private var header: some View {
        VStack(spacing: Theme.Space.loose) {
            BlockBadge(symbol: "wind", tint: .orange, size: 62)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
                .entrance(appeared, delay: 0.05, reduceMotion: reduceMotion)
                .accessibilityHidden(true)

            VStack(spacing: Theme.Space.snug) {
                Text(request.title)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                    .revealOnAppear(delay: 0.12, duration: 0.8)

                Text(request.subtitle)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 640)
                    .revealOnAppear(delay: 0.4, duration: 1.1)
            }

            Label("\(request.blockedTarget) is blocked by “\(request.blockName)”", systemImage: "square.stack")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .entrance(appeared, delay: 0.55, reduceMotion: reduceMotion)
        }
    }

    // MARK: 1. The breath

    /// A constellation that opens and draws itself on the in-breath and gathers into a knot
    /// of light on the out-breath (`ConstellationBreath`). When the breath ends, the panel
    /// grows from its centre.
    private var orb: some View {
        VStack(spacing: Theme.Space.loose) {
            ConstellationBreath(start: breathStart, animates: !reduceMotion)
                .frame(width: 560, height: 420)
                .background {
                    Circle()
                        .fill(.clear)
                        .frame(width: 180, height: 180)
                        .matchedGeometryEffect(id: "surface", in: surface)
                }

            waitBar(remaining: drain)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pause. \(secondsLeft) second\(secondsLeft == 1 ? "" : "s") left.")
    }

    /// Both waits use a bar that drains toward the leading edge.
    private func waitBar(remaining: Double) -> some View {
        GeometryReader { geometry in
            Capsule()
                .fill(.white.opacity(0.16))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: geometry.size.width * remaining)
                }
                .overlay { Capsule().strokeBorder(.white.opacity(0.14)) }
        }
        .frame(maxWidth: 260)
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    private func breathe() async {
        // Let the header land before the first breath starts.
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 600))
        guard !Task.isCancelled else { return }
        breathStart = Date()
        let total = Double(max(request.waitSeconds, 1))
        // One linear animation for the whole wait, so the bar empties smoothly instead of
        // stepping once a second. Reduce Motion gets the steps instead.
        if !reduceMotion {
            withAnimation(.linear(duration: total)) { drain = 0 }
        }
        while secondsLeft > 0 {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            secondsLeft -= 1
            if reduceMotion { drain = Double(secondsLeft) / total }
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
            .padding(.vertical, Theme.Space.wide + 4)
            .frame(maxWidth: 660)
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
        VStack(spacing: Theme.Space.wide) {
            // The question has to be answerable by the chips under it. They name a state
            // ("I'm bored", "This is hard"), not a reward, so asking what the feed was
            // going to give you left the answers reading like non-sequiturs. This asks
            // what's behind the reach, and keeps the pull as the subject rather than the
            // person: no shame in it.
            Text("What’s pulling you here?")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .revealOnAppear(delay: 0.3, duration: 0.85)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.base), count: 3),
                spacing: Theme.Space.base
            ) {
                ForEach(Array(choices.enumerated()), id: \.element) { index, choice in
                    feelingChip(choice, index: index)
                }
            }

            // One helper line, filled by whatever is under the pointer, instead of six
            // descriptions competing for attention at once.
            SwapText(helperText, outDuration: 0.18, inDuration: 0.4) {
                $0.font(.callout).foregroundStyle(.white.opacity(0.85))
            }
            .frame(height: 22)
            .opacity(questionShown ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.7), value: questionShown)
        }
    }

    private var helperText: String {
        guard let hovered else {
            if request.breaksLeft == 0 {
                return "No breaks left today. Press 1 to \(choices.count - 1) to choose."
            }
            return "Or press 1 to \(choices.count)."
        }
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
        .buttonStyle(PauseButtonStyle())
        .disabled(disabled)
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
             "Stand up, stretch, or look out a window for a minute.")
        case .tired:
            ("Give yourself a rest.",
             "Close your eyes and let your shoulders drop for two minutes.")
        case .stuck:
            ("Make it smaller.",
             "Hard work feels like a wall. A tiny next step is a door. Close this and write down one thing you could do in the next two minutes.")
        case .anxious:
            ("Put it on paper.",
             "Write down what’s on your mind. Start with one sentence.")
        case .lonely:
            ("Reach out to someone.",
             "Send a short message to someone you’d like to talk to.")
        case .needed:
            ("Say what you need it for.",
             "Your access time starts after a \(BreakPlan.waitMinutes)-minute wait.")
        }
    }

    private func answer(for reason: UrgeReason) -> some View {
        let text = suggestion(for: reason)
        return VStack(spacing: Theme.Space.loose) {
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
                .frame(maxWidth: 520)
                .revealOnAppear(delay: 0.4, duration: 1.2)

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
                ForEach(BreakPlan.accessMinutes, id: \.self) { minutes in
                    Button {
                        guard phase == .answering(.needed) else { return }
                        noteFocused = false
                        drain = 1
                        phase = .waitingForAccess(minutes: minutes, note: trimmed)
                    } label: {
                        Text("Allow for \(minutes) minutes")
                            .frame(minWidth: 130)
                            .padding(.horizontal, Theme.Space.snug)
                            .padding(.vertical, Theme.Space.snug + 3)
                    }
                    .buttonStyle(PauseButtonStyle())
                    .disabled(trimmed.isEmpty)
                }
            }

            if let left = request.breaksLeft {
                Text("Uses one of today’s breaks when access starts. \(left) left.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.top, Theme.Space.tight)
    }

    private func accessWait(minutes: Int) -> some View {
        VStack(spacing: Theme.Space.loose) {
            VStack(spacing: Theme.Space.tight) {
                Text("Access starts in")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))

                Text(Duration.seconds(accessWaitSecondsLeft).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(size: 48, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .accessibilityLabel("\(accessWaitSecondsLeft) second\(accessWaitSecondsLeft == 1 ? "" : "s")")
            }
            .accessibilityElement(children: .combine)

            waitBar(remaining: drain)

            Text("Then \(minutes) minutes of access to \(request.blockedTarget).")
                .font(.body)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520)
        }
    }

    private func waitForAccess(minutes: Int, note: String) async {
        let clock = ContinuousClock()
        let start = clock.now
        let total = Double(BreakPlan.waitSeconds)
        if !reduceMotion {
            withAnimation(.linear(duration: total)) { drain = 0 }
        }
        for elapsed in 1...BreakPlan.waitSeconds {
            do {
                try await clock.sleep(until: start.advanced(by: .seconds(elapsed)), tolerance: nil)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            accessWaitSecondsLeft = BreakPlan.waitSeconds - elapsed
            if reduceMotion { drain = Double(accessWaitSecondsLeft) / total }
        }
        onEvent(.takeBreak(minutes: minutes, note: note))
    }

    // MARK: The way out

    private var chosen: UrgeReason? {
        if case .answering(let reason) = phase { return reason }
        return nil
    }

    /// Keep the way out visible in the same place throughout the pause.
    private var closeButton: some View {
        Button {
            onEvent(.close(chosen == .needed ? nil : chosen))
        } label: {
            Label(request.closeTitle, systemImage: request.isBrowser ? "xmark" : "power")
                .padding(.horizontal, Theme.Space.loose + 4)
                .padding(.vertical, Theme.Space.snug + 3)
        }
        .buttonStyle(PauseButtonStyle())
        .keyboardShortcut(chosen == .needed ? nil : .defaultAction)
    }
}

// MARK: - Pieces

/// A feeling's label, colour tile, and keyboard shortcut.
private struct FeelingChip: View {
    let reason: UrgeReason
    let number: Int
    let highlighted: Bool

    var body: some View {
        HStack(spacing: Theme.Space.snug) {
            SidebarIconTile(systemName: reason.symbol, background: Color.tint(for: reason), size: 32)
                .symbolEffect(.bounce, value: highlighted)
            Text(reason.title)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            Text("\(number)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .opacity(highlighted ? 1 : 0.7)
        }
        .padding(.leading, Theme.Space.snug)
        .padding(.trailing, Theme.Space.base)
        .frame(height: 56)
        .accessibilityLabel("\(reason.title). \(reason.feeling)")
    }
}

private struct PauseButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.black.opacity(0.85))
            .background(.white, in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
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
