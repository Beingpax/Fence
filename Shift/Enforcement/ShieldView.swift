import AppKit
import SwiftUI

/// The full-screen "Not now." shield. Frosted glass: you can see it, you can't touch it.
struct ShieldView: View {
    let request: ShieldRequest
    /// Only the primary display shows text and buttons; the others are just frosted.
    let showsControls: Bool
    let onResolve: (ShieldResolution) -> Void

    @State private var secondsLeft: Int
    @State private var typedPhrase = ""
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
            FrostedBackground().ignoresSafeArea()
            Color.black.opacity(0.35).ignoresSafeArea()
            if showsControls {
                content
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .task { await runCountdown() }
    }

    private var content: some View {
        VStack(spacing: 22) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            Text("Not now.")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(request.reason)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            Label("You're here to: \(request.goal)", systemImage: "scope")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))

            strikeBadge

            if request.policy.requiresPhrase {
                VStack(spacing: 8) {
                    Text("Type “\(ShieldPolicy.phrase)” to continue")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                    TextField("", text: $typedPhrase)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 360)
                        .focused($phraseFocused)
                        .onAppear { phraseFocused = true }
                }
            }

            Button {
                onResolve(request.isBrowser ? .closeTab : .forceQuit)
            } label: {
                Text(secondsLeft > 0 ? "Unlocks in \(secondsLeft)s" : request.primaryActionTitle)
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 260)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.white.opacity(0.25))
            .disabled(!unlocked)
            .keyboardShortcut(.defaultAction)

            Button("Wrong call? This is part of my work") {
                onResolve(.wrongCall)
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.white.opacity(unlocked ? 0.7 : 0.3))
            .disabled(!unlocked)

            if request.isPreview {
                Text("Preview — no app will be closed")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(48)
        .frame(maxWidth: 720)
    }

    private var strikeBadge: some View {
        HStack(spacing: 6) {
            ForEach(1...3, id: \.self) { index in
                Circle()
                    .fill(index <= request.strike ? Color.white : Color.white.opacity(0.2))
                    .frame(width: 8, height: 8)
            }
            Text("Strike \(request.strike)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
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

/// Behind-window blur so the distraction stays visible but untouchable.
struct FrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
