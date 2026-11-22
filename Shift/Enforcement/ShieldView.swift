import AppKit
import SwiftUI

/// The full-screen "Not now." shield. Frosted: you can see what you were doing, you just
/// can't touch it.
///
/// This is the one loud surface in the app, so it's also the one place that breaks the calm
/// typography rules on purpose. Everything still degrades properly: Reduce Transparency
/// swaps the blur for a solid ground, and Reduce Motion drops the entrance animation.
struct ShieldView: View {
    let request: ShieldRequest
    /// Only the primary display shows text and buttons; the others are just frosted.
    let showsControls: Bool
    let onResolve: (ShieldResolution) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var secondsLeft: Int
    @State private var typedPhrase = ""
    @State private var appeared = false
    @FocusState private var phraseFocused: Bool

    init(request: ShieldRequest, showsControls: Bool, onResolve: @escaping (ShieldResolution) -> Void) {
        self.request = request
        self.showsControls = showsControls
        self.onResolve = onResolve
        _secondsLeft = State(initialValue: request.policy.countdownSeconds)
    }

    private var phraseMatches: Bool {
        typedPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(ShieldPolicy.phrase) == .orderedSame
    }

    private var unlocked: Bool {
        secondsLeft == 0 && (!request.policy.requiresPhrase || phraseMatches)
    }

    var body: some View {
        ZStack {
            background
            if showsControls {
                content
                    .scaleEffect(appeared ? 1 : 0.97)
                    .opacity(appeared ? 1 : 0)
            }
        }
        .task {
            withAnimation(.easeOut(duration: 0.28)) { appeared = true }
            await runCountdown()
        }
    }

    @ViewBuilder
    private var background: some View {
        if reduceTransparency {
            Color.black.opacity(0.92).ignoresSafeArea()
        } else {
            BehindWindowBlur(material: .fullScreenUI).ignoresSafeArea()
            Color.black.opacity(0.38).ignoresSafeArea()
        }
    }

    private var content: some View {
        VStack(spacing: Theme.Space.loose) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 50, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .accessibilityHidden(true)

            VStack(spacing: Theme.Space.snug) {
                Text("Not now.")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)

                Text(request.reason)
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label("You're here to: \(request.goal)", systemImage: "scope")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.72))
                .labelStyle(.titleAndIcon)

            strikeBadge

            if request.policy.requiresPhrase {
                phraseField
            }

            actions

            if request.isPreview {
                Text("Preview. Nothing will be closed.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(Theme.Space.vast)
        .frame(maxWidth: 760)
        .multilineTextAlignment(.center)
    }

    private var phraseField: some View {
        VStack(spacing: Theme.Space.tight) {
            Text("Type “\(ShieldPolicy.phrase)” to continue")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
            TextField("", text: $typedPhrase)
                .textFieldStyle(.roundedBorder)
                .frame(width: 380)
                .focused($phraseFocused)
                .onAppear { phraseFocused = true }
                .accessibilityLabel("Type the phrase to continue")
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.Space.snug) {
            Button {
                onResolve(request.isBrowser ? .closeTab : .forceQuit)
            } label: {
                Text(secondsLeft > 0 ? "Unlocks in \(secondsLeft)s" : request.primaryActionTitle)
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 280)
                    .padding(.vertical, Theme.Space.hair + 2)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .disabled(!unlocked)
            .keyboardShortcut(.defaultAction)

            // PRD §9: "wrong call" must not be an escape hatch, so it stays locked until
            // the countdown is done, exactly like the primary action.
            Button("Wrong call? This is part of my work") {
                onResolve(.wrongCall)
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.white.opacity(unlocked ? 0.72 : 0.3))
            .disabled(!unlocked)
        }
    }

    private var strikeBadge: some View {
        HStack(spacing: Theme.Space.tight) {
            HStack(spacing: Theme.Space.hair + 2) {
                ForEach(1...3, id: \.self) { index in
                    Circle()
                        .fill(index <= request.strike ? Color.white : Color.white.opacity(0.22))
                        .frame(width: 8, height: 8)
                }
            }
            Text("Strike \(request.strike)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Strike \(request.strike)")
    }

    private func runCountdown() async {
        while secondsLeft > 0 {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            secondsLeft -= 1
        }
    }
}
