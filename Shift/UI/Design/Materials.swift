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

/// The standard raised surface: a warm paper card, a hairline, and a continuous corner
/// radius. `tint` is accepted for older call sites but no longer colours the card.
struct GlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.usesGlassCards) private var usesGlassCards

    var radius: CGFloat = Theme.Radius.card
    var padding: CGFloat? = Theme.Space.base
    var tint: Color?
    var isSelected: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if usesGlassCards {
            // The block editor's original look, unchanged from before the redesign:
            // frosted glass with a whisper of the block's colour.
            content
                .padding(padding ?? 0)
                .background {
                    if reduceTransparency {
                        shape.fill(Color(nsColor: .controlBackgroundColor))
                    } else {
                        shape.fill(.ultraThinMaterial)
                    }
                }
                .background {
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
        } else {
            content
                .padding(padding ?? 0)
                // A plain warm card. No tinted wash: coloured card fills were the most
                // generic-looking thing in the app.
                .background(shape.fill(Paper.card))
                .overlay {
                    shape.strokeBorder(
                        isSelected ? Paper.coral : Paper.hairline,
                        lineWidth: isSelected ? 1.5 : 1
                    )
                }
        }
    }
}

extension EnvironmentValues {
    /// Set by the block editor, which keeps the original frosted glass cards.
    @Entry var usesGlassCards = false
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
    var help: String?
    var tint: Color?
    @ViewBuilder var content: () -> Content

    init(
        _ title: String? = nil,
        subtitle: String? = nil,
        icon: String? = nil,
        help: String? = nil,
        tint: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.help = help
        self.tint = tint
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            if let title {
                PanelHeading(title: title, icon: icon, help: help, tint: tint)

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
        .glassSurface(padding: Theme.Space.base, tint: tint)
    }
}

struct PanelHeading: View {
    let title: String
    var icon: String?
    var help: String?
    var tint: Color?

    @State private var isShowingHelp = false

    var body: some View {
        HStack(spacing: Theme.Space.tight) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if let help {
                IconButton(symbol: "info.circle", help: "About \(title)") {
                    isShowingHelp.toggle()
                }
                .accessibilityHint(help)
                .popover(isPresented: $isShowingHelp, arrowEdge: .trailing) {
                    Text(help)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 240, alignment: .leading)
                        .padding(Theme.Space.base)
                }
            }
        }
    }
}

/// A labelled row inside a `Panel`, with the control pushed to the trailing edge.
struct PanelRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
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

// MARK: - Page header

extension View {
    func mainPageInsets() -> some View {
        padding(.horizontal, Theme.Space.wide)
            .padding(.vertical, 26)
    }
}

/// The title at the top of a pane.
///
/// Replaces a `.principal` toolbar item, which macOS 26 renders as a floating capsule
/// stranded in the middle of the title bar. A heading that sits with its own content
/// reads better and leaves the title bar to the window controls.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Theme.Space.snug)
            trailing()
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Sidebar

/// Layout constants for the sidebar, matching the reference build in Budget-Tracker.
enum SidebarLayout {
    static let width: CGFloat = 220
    static let horizontalInset: CGFloat = 10
    /// Clears the traffic lights, which sit over the sidebar in a hidden-title-bar window.
    static let topInset: CGFloat = 40
    static let rowSpacing: CGFloat = 3
    static let bottomInset: CGFloat = 14
    static let rowHeight: CGFloat = 38
    static let rowRadius: CGFloat = 10
}

/// The navigation surface: a fixed-width glass panel with its trailing corners rounded,
/// so it reads as a card sitting inside the window rather than a wall attached to it.
struct AppSidebar<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = UnevenRoundedRectangle(bottomTrailingRadius: 12, topTrailingRadius: 12, style: .continuous)
        content()
            .frame(width: SidebarLayout.width)
            .frame(maxHeight: .infinity)
            .background {
                Group {
                    if reduceTransparency {
                        shape.fill(Color(nsColor: .windowBackgroundColor))
                    } else {
                        Color.clear.glassEffect(.regular, in: shape)
                    }
                }
                .ignoresSafeArea(.container, edges: .top)
            }
    }
}

/// A sidebar item: a vivid icon tile, a title, and a neutral selected fill.
///
/// The selection is deliberately not tinted by the row's own colour. The tile carries the
/// colour; the row carries the state. Tinting both makes the sidebar noisy.
struct SidebarRow: View {
    let title: String
    let systemImage: String
    let iconColor: Color
    let isSelected: Bool
    var badgeCount: Int = 0
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                SidebarIconTile(systemName: systemImage, background: iconColor)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
            }
            .foregroundStyle(Color(nsColor: .labelColor))
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .frame(height: SidebarLayout.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : .clear,
                in: RoundedRectangle(cornerRadius: SidebarLayout.rowRadius, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: SidebarLayout.rowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: isSelected)
    }
}

/// The small coloured tile behind each sidebar glyph. The top highlight and hairline are
/// what stop it reading as a flat square of colour.
/// A solid system-colour tile with a white symbol, the way macOS draws Settings icons.
/// Drawn at 24 pt in the sidebar; everything scales with `size`, so the pause's feeling
/// icons can use the very same tile larger.
struct SidebarIconTile: View {
    let systemName: String
    let background: Color
    var size: CGFloat = 24

    var body: some View {
        let scale = size / 24
        ZStack {
            RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                .fill(background)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 11 * scale)
                        .blendMode(.screen)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.5 * max(1, scale * 0.8))
                }
                .shadow(color: Color.black.opacity(0.18), radius: 1.2 * scale, y: scale)

            Image(systemName: systemName)
                .font(.system(size: 14.5 * scale, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.white)
                .shadow(color: Color.black.opacity(0.16), radius: 0.5 * scale, y: 0.5 * scale)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Sliding panel

/// A panel that slides in over the content from the trailing edge.
///
/// Geometry copied from the reference build in Budget-Tracker: the panel is flush to the
/// window's top, bottom and trailing edges and rounded only on its leading corners, so it
/// reads as a drawer pulled out of the side rather than a card floating in the corner.
/// The page behind the panel stops taking input while the inspector is open.
struct SlidingPanel<PanelContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var width: CGFloat = 400
    let onOutsideClick: () -> Void
    @ViewBuilder var panel: () -> PanelContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(!isPresented)
            .accessibilityHidden(isPresented)
            .overlay(alignment: .trailing) {
                GeometryReader { geometry in
                    let panelWidth = min(max(width, 360), 460, geometry.size.width)
                    ZStack(alignment: .trailing) {
                        if isPresented {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture(perform: onOutsideClick)
                                .padding(.trailing, panelWidth)
                                .accessibilityHidden(true)

                            panelSurface
                                .frame(width: panelWidth)
                                .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }
            }
            .clipped()
            .animation(reduceMotion ? nil : .easeIn(duration: 0.24), value: isPresented)
    }

    private var panelSurface: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12, style: .continuous)
        return panel()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                if reduceTransparency {
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                        .overlay { shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1) }
                } else {
                    Color.clear
                        .glassEffect(.regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.28)), in: shape)
                }
            }
            .clipShape(shape)
            .contentShape(shape)
            .accessibilityElement(children: .contain)
    }
}

extension View {
    /// Presents a trailing panel that slides over this view.
    func slidingPanel<PanelContent: View>(
        isPresented: Binding<Bool>,
        width: CGFloat = 400,
        onOutsideClick: @escaping () -> Void,
        @ViewBuilder panel: @escaping () -> PanelContent
    ) -> some View {
        modifier(SlidingPanel(isPresented: isPresented, width: width, onOutsideClick: onOutsideClick, panel: panel))
    }
}
