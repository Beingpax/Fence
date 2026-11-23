import SwiftUI

/// The pause: one breath, one honest question, and something better than the feed.
///
/// Every screen here follows the same few rules from habit research, so check new copy
/// against them:
///
/// 1. **Catch the cue, before the reward.** The pause lands while the page is still
///    loading. A feed that never pays out stops being worth reaching for.
/// 2. **No shame.** Shame makes people hide from the tool, not change. The voice is a
///    friend's: warm, on your side, a little wry. The urge is "the pull", not you.
/// 3. **Name the craving.** Putting a feeling into words weakens it, and turns autopilot
///    into a decision.
/// 4. **Replace, don't remove.** Every answer leads to a routine that meets the same need
///    better: real rest, a smaller step, a real person.
/// 5. **Effort over willpower.** Each option asks for a small, concrete action, because
///    doing something is easier than resisting something.
struct PauseView: View {
    let request: PauseRequest
    let onEvent: (PauseEvent) -> Void

    private enum Phase: Equatable {
        case breathing
        case asking
        case answering(UrgeReason)
        case resting(UrgeReason, endsAt: Date)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var phase: Phase = .breathing
    @State private var inhaling = false
    @State private var cue = "Breathe in…"
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    private static let accent = NudgeMood.calm.tint
    private static let breakLength: TimeInterval = 120

    var body: some View {
        ZStack {
            background
            ScrollView {
                VStack(spacing: Theme.Space.base) {
                    switch phase {
                    case .breathing: breathing
                    case .asking: asking
                    case .answering(let reason): answering(reason)
                    case .resting(let reason, let endsAt): resting(reason, endsAt: endsAt)
                    }
                }
                .frame(maxWidth: 500)
                .padding(.horizontal, Theme.Space.wide)
                .padding(.vertical, Theme.Space.vast)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 560)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)

            if request.isPreview {
                VStack {
                    Spacer()
                    Text("Preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, Theme.Space.base)
                }
            }
        }
        .multilineTextAlignment(.center)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.86), value: phase)
        .task { await breathe() }
    }

    // MARK: Surface

    private var background: some View {
        ZStack {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                // Heavy blur plus a wash, so whatever has loaded underneath is a blur of
                // colour, never something you could read or get pulled into.
                BehindWindowBlur(material: .fullScreenUI, cornerRadius: 16)
                Color(nsColor: .windowBackgroundColor).opacity(0.62)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
    }

    // MARK: 1. Breathe

    private var breathing: some View {
        VStack(spacing: Theme.Space.base) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Self.accent.opacity(0.32), Self.accent.opacity(0.08), .clear],
                            center: .center, startRadius: 10, endRadius: 130
                        )
                    )
                    .frame(width: 260, height: 260)
                    .scaleEffect(reduceMotion ? 1 : (inhaling ? 1.08 : 0.74))
                    .opacity(reduceMotion ? (inhaling ? 1 : 0.55) : 1)
                NudgeCharacterView(mood: .calm, animates: !reduceMotion, height: 160)
            }
            .accessibilityHidden(true)

            Text(request.visit <= 1 ? "Hey. One breath first." : "Back again. That’s the pull, not you.")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text(request.visit <= 1
                 ? "You reached for \(request.target). Before it pulls you in, check in with yourself."
                 : "Urges rise, peak and fade, usually within a minute. Ride this one out with me.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(cue)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Self.accent)
                .contentTransition(.opacity)
                .padding(.top, Theme.Space.tight)
                .accessibilityAddTraits(.updatesFrequently)

            closeLink
                .padding(.top, Theme.Space.snug)
        }
    }

    private func breathe() async {
        for _ in 0..<request.breathCycles {
            withAnimation(.easeInOut(duration: 2.5)) {
                inhaling = true
                cue = "Breathe in…"
            }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, phase == .breathing else { return }
            withAnimation(.easeInOut(duration: 2.5)) {
                inhaling = false
                cue = "And let it go…"
            }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, phase == .breathing else { return }
        }
        phase = .asking
    }

    // MARK: 2. Ask

    private var reasons: [UrgeReason] {
        UrgeReason.allCases.filter { $0 != .needed || request.allowsNeeded }
    }

    private var asking: some View {
        VStack(spacing: Theme.Space.base) {
            NudgeCharacterView(mood: .calm, animates: !reduceMotion, height: 96)
                .accessibilityHidden(true)

            Text("What were you hoping it would give you?")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            Text("Whatever it is, it’s a real need. Let’s meet it properly.")
                .font(.body)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.snug),
                                GridItem(.flexible(), spacing: Theme.Space.snug)],
                      spacing: Theme.Space.snug) {
                ForEach(reasons) { reason in
                    Button {
                        note = ""
                        phase = .answering(reason)
                    } label: {
                        ReasonLabel(reason: reason)
                    }
                    .buttonStyle(ReasonButtonStyle(tint: Self.accent))
                }
            }
            .padding(.top, Theme.Space.tight)

            closeLink
                .padding(.top, Theme.Space.tight)
        }
    }

    // MARK: 3. Answer

    private struct Answer {
        var title: String
        var body: String
        var prompt: String?
        var action: String
    }

    private func answer(for reason: UrgeReason) -> Answer {
        switch reason {
        case .bored:
            Answer(
                title: "Give your mind something real.",
                body: "The feed promises something new and serves more of the same. Two minutes away from the screen will do more: stand up, stretch, look at something far away.",
                action: "Start a 2-minute break"
            )
        case .tired:
            Answer(
                title: "You need rest, not more input.",
                body: "Scrolling feels like rest, but it keeps your brain working. Close your eyes, drop your shoulders, and just breathe for two minutes.",
                action: "Rest for 2 minutes"
            )
        case .stuck:
            Answer(
                title: "Make it smaller.",
                body: "Hard work feels like a wall. A tiny next step is a door. What could you do in the next two minutes?",
                prompt: "One small thing, like “write one rough sentence”",
                action: "That’s my next step"
            )
        case .anxious:
            Answer(
                title: "Put it on paper, not in a feed.",
                body: "A feed only adds noise to whatever you’re carrying. Write down what’s on your mind. Out of your head, it gets lighter.",
                prompt: "What’s on your mind?",
                action: "Set it down"
            )
        case .lonely:
            Answer(
                title: "Reach a real person.",
                body: "A feed shows you people without giving you any of them. Send one message to someone you actually like.",
                action: "Open Messages"
            )
        case .needed:
            Answer(
                title: "Name it, and it’s yours for two minutes.",
                body: "Say exactly what you need it for. When the two minutes are up, Shift will close it for you.",
                prompt: "Like “reply to Sam about Friday”",
                action: "Open for 2 minutes"
            )
        }
    }

    private func answering(_ reason: UrgeReason) -> some View {
        let answer = answer(for: reason)
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let canContinue = answer.prompt == nil || !trimmed.isEmpty

        return VStack(spacing: Theme.Space.base) {
            NudgeCharacterView(mood: .calm, animates: !reduceMotion, height: 96)
                .accessibilityHidden(true)

            if let plan = request.plans[reason], !plan.isEmpty {
                // Their own words, from the weekly review. A promise you made yourself
                // carries far more weight than any line an app could write.
                VStack(spacing: 2) {
                    Text("Your plan")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Self.accent)
                    Text("\(reason.planLead) \(plan).")
                        .font(.callout.weight(.medium))
                }
                .padding(.horizontal, Theme.Space.base)
                .padding(.vertical, Theme.Space.snug)
                .frame(maxWidth: .infinity)
                .background(Self.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text(answer.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            Text(answer.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let prompt = answer.prompt {
                TextField(prompt, text: $note, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...4)
                    .multilineTextAlignment(.leading)
                    .padding(Theme.Space.snug + 2)
                    .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(noteFocused ? Self.accent.opacity(0.6) : .primary.opacity(0.12), lineWidth: 1)
                    }
                    .focused($noteFocused)
                    .onAppear { noteFocused = true }
                    .onSubmit { if canContinue { act(on: reason) } }
            }

            Button {
                act(on: reason)
            } label: {
                Text(answer.action)
                    .frame(minWidth: 220)
            }
            .buttonStyle(.shiftProminent(Self.accent))
            .disabled(!canContinue)
            .opacity(canContinue ? 1 : 0.5)
            .keyboardShortcut(.defaultAction)
            .padding(.top, Theme.Space.tight)

            if reason == .lonely {
                Button("I’ll text from my phone") {
                    onEvent(.finished(.lonely, .reachedOut, note: nil))
                }
                .buttonStyle(.shiftSoft)
            }

            HStack(spacing: Theme.Space.base) {
                Button("Something else") {
                    note = ""
                    phase = .asking
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                closeLink
            }
            .font(.callout)
            .padding(.top, Theme.Space.tight)
        }
    }

    private func act(on reason: UrgeReason) {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch reason {
        case .bored, .tired:
            onEvent(.beganBreak(reason))
            phase = .resting(reason, endsAt: Date().addingTimeInterval(Self.breakLength))
        case .stuck:
            onEvent(.finished(.stuck, .wroteStep, note: text))
        case .anxious:
            onEvent(.finished(.anxious, .wroteItDown, note: text))
        case .lonely:
            onEvent(.openMessages)
        case .needed:
            onEvent(.allow(note: text))
        }
    }

    // MARK: 4. Rest

    private func resting(_ reason: UrgeReason, endsAt: Date) -> some View {
        VStack(spacing: Theme.Space.base) {
            NudgeCharacterView(mood: .calm, animates: !reduceMotion, height: 130)
                .accessibilityHidden(true)

            Text(reason == .tired ? "Rest. Nothing to do." : "Away from the screen.")
                .font(.system(size: 26, weight: .bold, design: .rounded))

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = max(0, Int(endsAt.timeIntervalSince(context.date).rounded(.up)))
                Text(String(format: "%d:%02d", left / 60, left % 60))
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .onChange(of: left) { _, value in
                        if value == 0 { onEvent(.finished(reason, .tookBreak, note: nil)) }
                    }
            }

            Text(reason == .tired
                 ? "Eyes closed, shoulders down. Shift will be right here."
                 : "Stand up, stretch, look out of a window. Shift will be right here.")
                .font(.body)
                .foregroundStyle(.secondary)

            Button("I’m back") {
                onEvent(.finished(reason, .tookBreak, note: nil))
            }
            .buttonStyle(.shiftSoft)
            .padding(.top, Theme.Space.snug)
        }
    }

    // MARK: Pieces

    /// Always there, on every screen. Turning back has to be the easiest thing to do.
    private var closeLink: some View {
        Button("I don’t need this. Close it.") {
            onEvent(.close)
        }
        .buttonStyle(.plain)
        .font(.callout.weight(.medium))
        .foregroundStyle(Self.accent)
    }
}

private struct ReasonLabel: View {
    let reason: UrgeReason

    var body: some View {
        HStack(spacing: Theme.Space.snug) {
            Image(systemName: reason.symbol)
                .font(.title3)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(reason.title)
                    .font(.callout.weight(.semibold))
                Text(reason.feeling)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, Theme.Space.base)
        .padding(.vertical, Theme.Space.snug + 2)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ReasonButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, tint: tint)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        let tint: Color
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.background.opacity(hovering ? 0.95 : 0.6))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(hovering ? tint.opacity(0.7) : .primary.opacity(0.1), lineWidth: hovering ? 1.5 : 1)
                }
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}
