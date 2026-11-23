import SwiftUI

/// Draws text so it can arrive glyph by glyph: each letter rises a few points out of a soft
/// blur and settles, a beat after the one before it. It reads like ink settling rather
/// than text being switched on, which is the difference between "natural" and "animated".
///
/// `progress` runs 0 → 1 over the whole reveal. The stagger is spread across the first
/// `spread` of the timeline, and each glyph eases in over the rest, so short and long
/// lines take the same time and never feel like a typewriter.
struct RevealRenderer: TextRenderer, Animatable {
    var progress: Double
    var spread: Double = 0.55

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var total = 0
        for line in layout { for run in line { total += run.count } }
        guard total > 0 else { return }

        var index = 0
        for line in layout {
            for run in line {
                for glyph in run {
                    let start = total > 1 ? Double(index) / Double(total - 1) * spread : 0
                    let t = min(1, max(0, (progress - start) / (1 - spread)))
                    // Ease out: quick to start, gentle to land.
                    let eased = 1 - pow(1 - t, 3)

                    var copy = context
                    copy.opacity = eased
                    copy.translateBy(x: 0, y: (1 - eased) * 8)
                    if eased < 1 { copy.addFilter(.blur(radius: (1 - eased) * 6)) }
                    copy.draw(glyph)
                    index += 1
                }
            }
        }
    }
}

/// Reveals the text it wraps the first time it appears.
private struct RevealOnAppear: ViewModifier {
    var delay: Double
    var duration: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        Group {
            if reduceMotion {
                content.opacity(shown ? 1 : 0)
            } else {
                content.textRenderer(RevealRenderer(progress: shown ? 1 : 0))
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.25).delay(delay) : .linear(duration: duration).delay(delay),
            value: shown
        )
        .onAppear { shown = true }
    }
}

/// Text that changes in place, one line at a time: the old words dissolve completely back
/// into blur, and only then do the new ones rise in. Never both at once, which is what made
/// a crossfade look like two cues fighting.
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
    @State private var generation = 0

    init(_ text: String, outDuration: Double = 0.32, inDuration: Double = 0.6, style: @escaping (Text) -> Text) {
        self.text = text
        self.outDuration = outDuration
        self.inDuration = inDuration
        self.style = style
        _shown = State(initialValue: text)
    }

    var body: some View {
        style(Text(shown))
            .textRenderer(RevealRenderer(progress: visible || reduceMotion ? 1 : 0, spread: 0.45))
            .opacity(reduceMotion && !visible ? 0 : 1)
            .onChange(of: text) { _, new in swap(to: new) }
    }

    private func swap(to new: String) {
        generation += 1
        let current = generation
        Task { @MainActor in
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .linear(duration: outDuration)) { visible = false }
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.15 : outDuration))
            guard current == generation else { return }
            shown = new
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .linear(duration: inDuration)) { visible = true }
        }
    }
}

extension View {
    /// Lets the text inside arrive letter by letter, out of a soft blur.
    func revealOnAppear(delay: Double = 0, duration: Double = 0.9) -> some View {
        modifier(RevealOnAppear(delay: delay, duration: duration))
    }
}
