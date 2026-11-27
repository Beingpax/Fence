import SwiftUI

/// The playful pieces shared by onboarding and Settings: paper cards, the mascot peeking
/// over a card, the custom switch, and buttons that squish. Drawn by hand, never stock
/// controls, in the Sorbet palette (`Paper`).

enum PlayType {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// A faint dot grid, like the paper in a notebook. Gives the background texture without
/// colour.
struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 22
            let dot = Color.primary.opacity(0.05)
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(dot))
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A white card with a hairline and the faintest shadow.
struct PaperCard: ViewModifier {
    var radius: CGFloat = 20

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background(shape.fill(Paper.card))
            .overlay { shape.strokeBorder(Paper.hairline, lineWidth: 1) }
            .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
}

extension View {
    func paperCard(radius: CGFloat = 20) -> some View {
        modifier(PaperCard(radius: radius))
    }
}

/// A paper card with the mascot peeking over its top edge, holding on with both hands.
/// Drawn the same way as the nudge card: the body is clipped at the card's edge, so it rises
/// from behind it, and the hands are drawn in front.
struct MascotCard<Content: View>: View {
    let mood: MascotMood
    let start: Date
    let animates: Bool
    /// Centred over the card by default; Settings puts it on the right, beside the title.
    let mascotAlignment: HorizontalAlignment
    let content: () -> Content

    @State private var risen = false

    init(
        mood: MascotMood,
        start: Date,
        animates: Bool,
        mascotAlignment: HorizontalAlignment = .center,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.mood = mood
        self.start = start
        self.animates = animates
        self.mascotAlignment = mascotAlignment
        self.content = content
    }

    private var mascotInset: CGFloat { mascotAlignment == .center ? 0 : 20 }

    var body: some View {
        ZStack(alignment: Alignment(horizontal: mascotAlignment, vertical: .top)) {
            MascotView(mood: mood, layer: .body, animates: animates, start: start)
                .offset(y: risen ? 0 : 70)
                .frame(width: MascotView.size.width, height: MascotView.cardEdgeOffset, alignment: .top)
                .clipped()
                .padding(.horizontal, mascotInset)
                .allowsHitTesting(false)

            content()
                .frame(maxWidth: .infinity)
                .paperCard(radius: 26)
                .padding(.top, MascotView.cardEdgeOffset)

            MascotView(mood: mood, layer: .hands, animates: animates, start: start)
                .opacity(risen ? 1 : 0)
                .offset(y: risen ? 0 : 6)
                .padding(.horizontal, mascotInset)
                .allowsHitTesting(false)
        }
        .onAppear {
            guard animates else {
                risen = true
                return
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.68).delay(0.2)) { risen = true }
        }
    }
}

struct SmallCaps: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(PlayType.rounded(10, .bold))
            .tracking(0.9)
            .foregroundStyle(.secondary)
    }
}

/// A switch drawn to match. It's the one place the system accent colour appears.
struct PaperSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Capsule(style: .continuous)
                .fill(isOn ? Color.accentColor : Color.primary.opacity(0.14))
                .frame(width: 46, height: 27)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .padding(3)
                }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.68), value: isOn)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

/// Squishes a little when pressed, and springs back.
struct SquishButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A small coral capsule for the one action inside a card.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PlayType.rounded(12, .bold))
            .foregroundStyle(Paper.onCoral)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule(style: .continuous).fill(Paper.coral))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Pages

/// The top of a playful page: a big title and one line on the left, and the mascot on the
/// right holding a card. The title sits at the foot of the mascot's space, just above the
/// card, so there's no empty band between them.
struct PlayHero<Content: View>: View {
    let title: String
    let subtitle: String?
    let mood: MascotMood
    let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    init(title: String, subtitle: String? = nil, mood: MascotMood, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.mood = mood
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MascotCard(mood: mood, start: start, animates: !reduceMotion, mascotAlignment: .trailing) {
                content()
                    .padding(PlayRhythm.card)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(PlayType.rounded(30, .bold))
                    .foregroundStyle(Paper.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(PlayType.rounded(13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: 300, alignment: .leading)
            .frame(height: MascotView.cardEdgeOffset - PlayRhythm.inner, alignment: .bottomLeading)
        }
    }
}

/// One spacing scale for the playful pages (Settings, Dashboard), so gaps read as a
/// pattern rather than guesses.
/// Bigger gaps separate bigger things: page edge > sections > card padding > inside a card
/// > between rows > between tiles.
enum PlayRhythm {
    /// Page edges.
    static let page: CGFloat = 28
    /// Between sections.
    static let section: CGFloat = 14
    /// Inside a card's edge.
    static let card: CGFloat = 18
    /// Between a card's heading and its content, and inside tiles.
    static let inner: CGFloat = 12
    /// Above and below a divider between two rows.
    static let row: CGFloat = 11
    /// Between tiles that sit side by side.
    static let tile: CGFloat = 8
}

/// A titled paper card with a coral icon, holding a few rows.
struct PlaySection<Content: View>: View {
    let symbol: String
    let title: String
    var subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: PlayRhythm.inner) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Paper.coralText)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Paper.coralSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(PlayType.rounded(16, .bold))
                        .foregroundStyle(Paper.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(PlayType.rounded(12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            content()
        }
        .padding(PlayRhythm.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(radius: 20)
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Paper.hairline)
            .frame(height: 1)
            .padding(.vertical, PlayRhythm.row)
    }
}

/// A permission: a mint check once it's allowed, otherwise a neutral tile and the one
/// coral action that fixes it. No "Done" badge; the check says it.
struct PermissionLine: View {
    let symbol: String
    let title: String
    let detail: String
    let action: (title: String, perform: () -> Void)?

    private var isDone: Bool { action == nil }

    var body: some View {
        HStack(alignment: .center, spacing: PlayRhythm.inner) {
            Image(systemName: isDone ? "checkmark" : symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isDone ? Paper.onMint : Paper.ink.opacity(0.75))
                .frame(width: 40, height: 40)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isDone ? Paper.mint : Paper.tile)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PlayType.rounded(14, .semibold))
                    .foregroundStyle(Paper.ink)
                // Only while something needs doing: the instruction is how to fix it.
                if !isDone {
                    Text(detail)
                        .font(PlayType.rounded(12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: PlayRhythm.inner)
            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(PillButtonStyle())
                    .fixedSize()
            }
        }
        .help(isDone ? detail : "")
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isDone)
    }
}

/// The quieter pill, for secondary actions: a soft neutral capsule with a dark label.
struct SoftPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SoftPill(configuration: configuration)
    }

    private struct SoftPill: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(PlayType.rounded(12, .bold))
                .foregroundStyle(Paper.ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Capsule(style: .continuous).fill(Paper.tile))
                .overlay(Capsule(style: .continuous).strokeBorder(Paper.hairline, lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
        }
    }
}

/// A solid capsule with a soft shadow, so it reads as floating above whatever scrolls
/// beneath it. Primary is coral; secondary is a white card with a dark label.
struct FloatingButtonStyle: ButtonStyle {
    let isPrimary: Bool
    /// The size of the app's ordinary buttons (13 pt, 14 by 8 padding), for floating over a
    /// compact panel like the block editor. Onboarding uses the larger default.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        FloatingButton(configuration: configuration, isPrimary: isPrimary, compact: compact)
    }

    private struct FloatingButton: View {
        let configuration: ButtonStyleConfiguration
        let isPrimary: Bool
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(compact ? .callout.weight(.semibold) : PlayType.rounded(15, .bold))
                .foregroundStyle(isPrimary ? Paper.onCoral : Paper.ink)
                .padding(.horizontal, compact ? Theme.Space.base : 22)
                .padding(.vertical, compact ? 8 : 12)
                .background {
                    Capsule(style: .continuous).fill(isPrimary ? Paper.coral : Paper.card)
                }
                .overlay {
                    if !isPrimary {
                        Capsule(style: .continuous).strokeBorder(Paper.hairline, lineWidth: 1)
                    }
                }
                .shadow(
                    color: .black.opacity(isEnabled ? (compact ? 0.16 : 0.18) : 0.05),
                    radius: compact ? 10 : 16,
                    y: compact ? 4 : 7
                )
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
                .contentShape(Capsule())
        }
    }
}
