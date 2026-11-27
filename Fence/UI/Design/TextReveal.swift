import SwiftUI

/// Reveals the text it wraps the first time it appears.
/// Fading the text as a unit lets SwiftUI reuse its rasterized glyphs across animation frames.
private struct RevealOnAppear: ViewModifier {
    var delay: Double
    var duration: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .animation(.easeOut(duration: reduceMotion ? 0.25 : duration).delay(delay), value: shown)
            .onAppear { shown = true }
    }
}

/// Text that changes in place. The new words appear after the old words fade out.
///
/// Changes that arrive while a swap is running (hovering across several buttons quickly)
/// skip straight to the latest text rather than queueing.
struct SwapText: View {
    let text: String
    var outDuration: Double = 0.32
    var inDuration: Double = 0.6
    let style: (Text) -> Text

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: String
    @State private var visible = true

    init(_ text: String, outDuration: Double = 0.32, inDuration: Double = 0.6, style: @escaping (Text) -> Text) {
        self.text = text
        self.outDuration = outDuration
        self.inDuration = inDuration
        self.style = style
        _shown = State(initialValue: text)
    }

    var body: some View {
        style(Text(shown))
            .opacity(visible ? 1 : 0)
            .task(id: text) { await swap(to: text) }
    }

    private func swap(to new: String) async {
        guard !Task.isCancelled, new != shown || !visible else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .linear(duration: outDuration)) { visible = false }
        try? await Task.sleep(for: .seconds(reduceMotion ? 0.15 : outDuration))
        guard !Task.isCancelled else { return }
        shown = new
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .linear(duration: inDuration)) { visible = true }
    }
}

extension View {
    /// Lets the text inside fade in after a delay.
    func revealOnAppear(delay: Double = 0, duration: Double = 0.9) -> some View {
        modifier(RevealOnAppear(delay: delay, duration: duration))
    }
}
