import AppKit
import SwiftUI

/// Translucent surfaces, in the spirit of IINA: the window is glass, the sidebar is
/// darker glass, and every raised element samples what's behind it rather than painting
/// over it with a flat fill.
///
/// Three rules hold the look together:
/// 1. Nothing uses an opaque background unless Reduce Transparency asks for it.
/// 2. Depth comes from material weight and a hairline, never from heavy shadows.
/// 3. Tint is carried by content and thin strokes, never by large filled rectangles.
enum Surface {
    /// Behind the whole window.
    case window
    /// Sidebar and other full-height chrome.
    case sidebar
    /// A raised card sitting on the window.
    case card
    /// A card that is currently the selected or active one.
    case prominent
    /// Controls: segments, chips, fields.
    case control

    var material: NSVisualEffectView.Material {
        switch self {
        case .window: .underWindowBackground
        case .sidebar: .sidebar
        case .card: .contentBackground
        case .prominent: .selection
        case .control: .headerView
        }
    }
}

/// An `NSVisualEffectView` bridged into SwiftUI, used where the effect must sample the
/// desktop or the window behind it rather than only in-app content.
struct VisualEffect: NSViewRepresentable {
    var surface: Surface = .card
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = surface.material
        view.blendingMode = blending
        view.isEmphasized = emphasized
    }
}

// MARK: - Card surfaces

/// The standard raised surface. Glass, a hairline, and a continuous corner radius.
struct GlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var radius: CGFloat = Theme.Radius.card
    var padding: CGFloat? = Theme.Space.base
    var tint: Color?
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .padding(padding ?? 0)
            .background {
                if reduceTransparency {
                    shape.fill(Color(nsColor: .controlBackgroundColor))
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .background {
                // A whisper of the block's colour, so cards feel owned without shouting.
                if let tint {
                    shape.fill(tint.opacity(isSelected ? 0.16 : 0.07))
                }
            }
            .overlay {
                shape.strokeBorder(
                    isSelected
                        ? (tint ?? Color.accentColor).opacity(0.55)
                        : Color.primary.opacity(0.08),
                    lineWidth: isSelected ? 1.5 : 1
                )
            }
    }
}

extension View {
    func glassSurface(
        radius: CGFloat = Theme.Radius.card,
        padding: CGFloat? = Theme.Space.base,
        tint: Color? = nil,
        isSelected: Bool = false
    ) -> some View {
        modifier(GlassSurface(radius: radius, padding: padding, tint: tint, isSelected: isSelected))
    }

    /// Makes the whole window translucent. Applied once, at the root.
    func translucentWindowBackground() -> some View {
        background {
            VisualEffect(surface: .window, blending: .behindWindow)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Section scaffolding

/// A titled group of settings. Replaces `Form`'s grouped sections so the whole app can
/// share one look rather than inheriting three different ones.
struct Panel<Content: View>: View {
    let title: String?
    var subtitle: String?
    var icon: String?
    @ViewBuilder var content: () -> Content

    init(
        _ title: String? = nil,
        subtitle: String? = nil,
        icon: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            if let title {
                HStack(spacing: Theme.Space.tight) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .accessibilityAddTraits(.isHeader)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(padding: Theme.Space.base)
    }
}

/// A labelled row inside a `Panel`, with the control pushed to the trailing edge.
struct PanelRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.base) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Space.snug)
            control()
        }
        .padding(.vertical, 2)
    }
}
