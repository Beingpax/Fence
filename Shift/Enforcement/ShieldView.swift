import AppKit
import SwiftUI

/// A full-screen shield with a shared action layout and a different palette for each strike level.
struct ShieldView: View {
    let request: ShieldRequest
    let showsControls: Bool
    let onResolve: (ShieldResolution) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    private var unlocked: Bool {
        let phraseMatches = typedPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(ShieldPolicy.phrase) == .orderedSame
        return secondsLeft == 0 && (!request.policy.requiresPhrase || phraseMatches)
    }

    private var colors: (accent: Color, button: Color) {
        switch request.policy.level {
        case .gentle:
            (Color(red: 0.59, green: 0.91, blue: 0.81), Color(red: 0.08, green: 0.36, blue: 0.32))
        case .firm:
            (Color(red: 1, green: 0.80, blue: 0.53), Color(red: 0.46, green: 0.29, blue: 0.10))
        case .severe:
            (Color(red: 1, green: 0.64, blue: 0.67), Color(red: 0.49, green: 0.20, blue: 0.28))
        }
    }

    private var headline: String {
        switch request.policy.level {
        case .gentle: "Your focus comes first."
        case .firm: "Protect the time you set aside."
        case .severe: "Choose what gets your time."
        }
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
                    .opacity(appeared ? 1 : 0)
                }
                .task {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) { appeared = true }
                    await runCountdown()
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var backdrop: some View {
        ZStack {
            let ground = Color(red: 0.04, green: 0.07, blue: 0.09)
            if reduceTransparency {
                ground
            } else {
                BehindWindowBlur(material: .fullScreenUI)
                ground.opacity(0.92)
            }
            RadialGradient(
                colors: [colors.accent.opacity(0.22), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 780
            )
            RadialGradient(
                colors: [colors.accent.opacity(0.10), .clear],
                center: .bottomLeading, startRadius: 0, endRadius: 650
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(spacing: Theme.Space.loose) {
            strikeBadge

            VStack(spacing: Theme.Space.snug) {
                Text(headline)
                    .font(.system(size: 64, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)

                Text(request.reason)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
            }

            VStack(spacing: Theme.Space.tight) {
                Label(request.blockName, systemImage: "shield.lefthalf.filled")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(colors.accent)
                if !request.goal.isEmpty {
                    Label(request.goal, systemImage: "scope")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.78))
                }
            }

            if request.policy.requiresPhrase { phraseField }

            actions

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

    private var strikeBadge: some View {
        Label("\(request.policy.level.rawValue) · Strike \(request.strike)", systemImage: request.policy.level.symbol)
            .font(.callout.weight(.semibold))
            .foregroundStyle(colors.accent)
            .padding(.horizontal, Theme.Space.base)
            .padding(.vertical, Theme.Space.tight)
            .background(Color.black.opacity(0.22), in: Capsule())
            .overlay { Capsule().strokeBorder(colors.accent.opacity(0.34)) }
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
                    .foregroundStyle(colors.accent)
            }

            Button {
                onResolve(request.isBrowser ? .closeTab : .quitApp)
            } label: {
                Label(request.primaryActionTitle, systemImage: request.isBrowser ? "xmark" : "power")
                    .frame(minWidth: 180)
            }
            .buttonStyle(.shiftProminent(colors.button))
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
