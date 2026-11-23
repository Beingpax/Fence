import AppKit
import SwiftUI

/// Shared visual language. One place to change spacing, radii and glass behaviour.
///
/// Design notes (Apple HIG + macOS 26):
/// - Liquid Glass is used for surfaces that float above content: cards and HUDs.
///   Glass never stacks on glass, so grouped glass lives inside a `GlassEffectContainer`.
/// - Every glass surface degrades to an opaque material when the user turns on
///   Reduce Transparency, and every animation degrades when Reduce Motion is on.
/// - Type uses the system text styles so Dynamic Type and the user's font size stick.
enum Theme {
    /// 4pt rhythm. Use these instead of literals so density stays consistent.
    enum Space {
        static let hair: CGFloat = 2
        static let tight: CGFloat = 6
        static let snug: CGFloat = 10
        static let base: CGFloat = 14
        static let loose: CGFloat = 20
        static let wide: CGFloat = 28
        static let vast: CGFloat = 40
    }

    enum Radius {
        static let control: CGFloat = 8
        static let card: CGFloat = 14
        static let panel: CGFloat = 20
        static let hud: CGFloat = 22
    }

    /// The menu bar popover width. Matches the HIG guidance to keep menu bar extras narrow.
    static let menuWidth: CGFloat = 352
    static let onboardingSize = CGSize(width: 680, height: 560)

    static let mainWindowSize = CGSize(width: 1040, height: 680)

    /// Behind the whole window, including under the sidebar's rounded trailing corners.
    static let workspaceBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
    })

    /// The content area beside the sidebar. Slightly off-white so glass cards read.
    static let detailBackground = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            NSColor(srgbRed: 20 / 255, green: 21 / 255, blue: 24 / 255, alpha: 1)
        } else {
            NSColor(srgbRed: 239 / 255, green: 241 / 255, blue: 244 / 255, alpha: 1)
        }
    })

    /// Verdict colours. Deliberately desaturated so the UI stays calm; the pause is the one full-screen surface.
    static func tint(for kind: Verdict.Kind) -> Color {
        switch kind {
        case .allow: .green
        case .nudge: .orange
        case .block: .red
        }
    }
}

// MARK: - Glass surfaces

extension View {
    /// Applies a transition only when the user hasn't asked for reduced motion.
    func calmTransition(_ transition: AnyTransition) -> some View {
        modifier(CalmTransition(transition: transition))
    }
}

private struct CalmTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let transition: AnyTransition

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : transition)
    }
}

// MARK: - Small shared parts

/// A label above a value, used in the settings rows.
struct FieldRow: View {
    let label: String
    let value: String
    var labelWidth: CGFloat = 54

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.tight) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: labelWidth, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Coloured capsule showing a verdict kind.
struct VerdictPill: View {
    let kind: Verdict.Kind

    var body: some View {
        Text(kind.rawValue.uppercased())
            .font(.caption2.weight(.bold))
            .monospaced()
            .padding(.horizontal, Theme.Space.tight)
            .padding(.vertical, Theme.Space.hair)
            .background(Theme.tint(for: kind).opacity(0.18), in: Capsule())
            .foregroundStyle(Theme.tint(for: kind))
            .accessibilityLabel("Verdict: \(kind.rawValue)")
    }
}

/// Section heading used throughout the menu and onboarding.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Behind-window blur. Used where a view must sample the desktop rather than app content,
/// which is the one case Liquid Glass can't cover: the pause sits over other apps.
struct BehindWindowBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .fullScreenUI

    /// Corner radius applied on the AppKit side. Leave at 0 for a full-bleed surface.
    ///
    /// This is not a convenience. `.behindWindow` blending is composited by the window
    /// server, outside SwiftUI's render tree, so wrapping this view in a SwiftUI
    /// `.clipShape` does **not** constrain the blurred region — the rounded card gets
    /// drawn correctly while the blur keeps processing the full rectangle behind it,
    /// which shows up as a faint rectangular panel floating around the content. Masking
    /// the layer here is the only thing that actually clips it.
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerCurve = .continuous
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.layer?.cornerRadius = cornerRadius
    }
}

/// The surface macOS notification banners are drawn on: regular Liquid Glass, adaptive to
/// light and dark, with the system's own edge highlight.
///
/// The nudge uses it so a nudge reads as belonging to the same family as the banners that
/// slide in from the same corner. Under Reduce Transparency it falls back to the opaque
/// window background, like every other glass surface in the app.
struct NotificationGlass: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        nsView.cornerRadius = cornerRadius
    }
}


extension BlockTint {
    var color: Color {
        switch self {
        case .indigo: .indigo
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .graphite: .gray
        }
    }

    var title: String { rawValue.capitalized }
}

/// The tinted glyph that identifies a block everywhere it appears.
struct BlockBadge: View {
    let symbol: String
    let tint: BlockTint
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint.color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}
