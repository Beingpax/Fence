import SwiftUI

/// Shift's own controls.
///
/// Built rather than borrowed, because the stock macOS controls are tuned for dense
/// settings windows and this app wants something bolder and more spacious. They still
/// behave like system controls: full keyboard and VoiceOver support, Reduce Motion
/// respected, and the accent colour honoured.

// MARK: - Segmented selector

/// A pill selector with a sliding indicator. Used anywhere a small set of options needs
/// to be visible at once.
struct SegmentedSelector<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        var symbol: String?
        var id: Value { value }

        init(_ value: Value, _ title: String, symbol: String? = nil) {
            self.value = value
            self.title = title
            self.symbol = symbol
        }
    }

    @Binding var selection: Value
    let options: [Option]
    var tint: Color = .accentColor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option.value == selection
                Button {
                    if reduceMotion {
                        selection = option.value
                    } else {
                        withAnimation(.snappy(duration: 0.22)) { selection = option.value }
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let symbol = option.symbol {
                            Image(systemName: symbol).font(.caption.weight(.semibold))
                        }
                        Text(option.title)
                            .font(.callout.weight(isSelected ? .semibold : .regular))
                    }
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(tint.gradient)
                                .matchedGeometryEffect(id: "segment", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background {
            Capsule(style: .continuous).fill(.quaternary.opacity(0.6))
        }
        .overlay {
            Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

// MARK: - Switch

/// A chunkier switch than the system one, so a block's on/off state reads from across
/// the room. Locked blocks show a keyhole instead of a knob.
struct ShiftSwitch: View {
    @Binding var isOn: Bool
    var tint: Color = .accentColor
    var isLocked: Bool = false
    var action: ((Bool) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let width: CGFloat = 50
    private let height: CGFloat = 29

    var body: some View {
        Button {
            let next = !isOn
            if let action {
                action(next)
            } else {
                isOn = next
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.14)))
                    .frame(width: width, height: height)

                Circle()
                    .fill(.white)
                    .frame(width: height - 6, height: height - 6)
                    .overlay {
                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(tint)
                        }
                    }
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                    .padding(.horizontal, 3)
            }
            .frame(width: width, height: height)
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

// MARK: - Option cards

/// A selectable card. Used for lock methods and friction levels, where each option needs
/// a sentence of explanation that a popup menu can't carry.
struct OptionCard: View {
    let title: String
    let detail: String
    let symbol: String
    let isSelected: Bool
    /// Kept for call sites that want an accent, but the card itself stays neutral.
    var tint: Color = .accentColor
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Theme.Space.snug) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.22),
                            lineWidth: isSelected ? 5.5 : 1.5
                        )
                        .frame(width: 15, height: 15)
                }
                .frame(width: 18)

                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.snug)
            .padding(.vertical, 9)
            .background {
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                if isSelected {
                    shape.fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
                } else if isHovering {
                    shape.fill(Color.primary.opacity(0.04))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(detail)
    }
}

// MARK: - Time

/// A time field built from two scrolling number columns rather than a stock date picker,
/// so it matches the rest of the app and reads at a glance.
struct TimeField: View {
    @Binding var time: TimeOfDay
    var tint: Color = .accentColor

    private var use24Hour: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return !format.contains("a")
    }

    var body: some View {
        HStack(spacing: 4) {
            NumberStepper(
                value: Binding(
                    get: { displayHour },
                    set: { setDisplayHour($0) }
                ),
                range: use24Hour ? 0...23 : 1...12,
                width: 44,
                tint: tint
            )
            .accessibilityLabel("Hour")

            Text(":")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)

            NumberStepper(
                value: Binding(
                    get: { time.minute },
                    set: { time = TimeOfDay(hour: time.hour, minute: $0) }
                ),
                range: 0...59,
                step: 5,
                width: 44,
                tint: tint
            )
            .accessibilityLabel("Minute")

            if !use24Hour {
                SegmentedSelector(
                    selection: Binding(
                        get: { time.hour < 12 },
                        set: { isMorning in
                            let hour = time.hour % 12
                            time = TimeOfDay(hour: isMorning ? hour : hour + 12, minute: time.minute)
                        }
                    ),
                    options: [.init(true, "AM"), .init(false, "PM")],
                    tint: tint
                )
                .frame(width: 96)
            }
        }
    }

    private var displayHour: Int {
        if use24Hour { return time.hour }
        let hour = time.hour % 12
        return hour == 0 ? 12 : hour
    }

    private func setDisplayHour(_ newValue: Int) {
        if use24Hour {
            time = TimeOfDay(hour: newValue, minute: time.minute)
            return
        }
        let isMorning = time.hour < 12
        let base = newValue % 12
        time = TimeOfDay(hour: isMorning ? base : base + 12, minute: time.minute)
    }
}

/// A number you can click, scroll or arrow through.
struct NumberStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var width: CGFloat = 52
    var tint: Color = .accentColor

    var body: some View {
        VStack(spacing: 0) {
            stepButton(symbol: "chevron.up", delta: step)
            Text(String(format: "%02d", value))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .frame(width: width)
                .padding(.vertical, 1)
            stepButton(symbol: "chevron.down", delta: -step)
        }
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(by: step)
            case .decrement: adjust(by: -step)
            @unknown default: break
            }
        }
    }

    private func stepButton(symbol: String, delta: Int) -> some View {
        Button {
            adjust(by: delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: width, height: 13)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }

    /// Wraps rather than clamping, which is what people expect from a clock.
    private func adjust(by delta: Int) {
        let span = range.upperBound - range.lowerBound + 1
        var next = value + delta
        while next > range.upperBound { next -= span }
        while next < range.lowerBound { next += span }
        value = next
    }
}

// MARK: - Days

/// Seven toggleable day pills, with shortcuts for the two sets people actually use.
struct DayPicker: View {
    @Binding var days: Set<Weekday>
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HStack(spacing: 5) {
                ForEach(Weekday.allCases) { day in
                    let isOn = days.contains(day)
                    Button {
                        if isOn { days.remove(day) } else { days.insert(day) }
                    } label: {
                        Text(day.letter)
                            .font(.caption.weight(.bold))
                            .frame(width: 30, height: 30)
                            .background {
                                Circle().fill(isOn ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.07)))
                            }
                            .foregroundStyle(isOn ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.shortTitle)
                    .accessibilityValue(isOn ? "on" : "off")
                }
            }

            HStack(spacing: Theme.Space.tight) {
                quickSet("Weekdays", Weekday.weekdays)
                quickSet("Every day", Set(Weekday.allCases))
                quickSet("Weekends", [.saturday, .sunday])
            }
        }
    }

    private func quickSet(_ title: String, _ value: Set<Weekday>) -> some View {
        Button(title) { days = value }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(days == value ? tint : .secondary)
    }
}

// MARK: - Chips

/// A removable token. Used for every list of sites and apps in the app.
struct Chip: View {
    let text: String
    var symbol: String?
    var image: NSImage?
    var tint: Color = .secondary
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 5) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 14, height: 14)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.caption2)
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Remove \(text)")
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, onRemove == nil ? 8 : 6)
        .padding(.vertical, 5)
        .background {
            Capsule(style: .continuous).fill(.quaternary.opacity(0.55))
        }
        .overlay {
            Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

/// A text field styled to match the rest of the controls.
struct ShiftTextField: View {
    let prompt: String
    @Binding var text: String
    var symbol: String?
    var onSubmit: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Space.tight) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
                .onSubmit { onSubmit?() }
        }
        .padding(.horizontal, Theme.Space.snug)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

/// The app's primary button. Bolder and rounder than the stock one.
struct ProminentButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Space.base)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous).fill(tint.gradient)
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// The quieter sibling, for secondary actions.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, Theme.Space.base)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous).fill(.quaternary.opacity(0.6))
            }
            .overlay {
                Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension ButtonStyle where Self == ProminentButtonStyle {
    static var shiftProminent: ProminentButtonStyle { ProminentButtonStyle() }
    static func shiftProminent(_ tint: Color) -> ProminentButtonStyle { ProminentButtonStyle(tint: tint) }
}

extension ButtonStyle where Self == SoftButtonStyle {
    static var shiftSoft: SoftButtonStyle { SoftButtonStyle() }
}

// MARK: - Icon button

/// A square icon button with a hover background.
///
/// The stock borderless button renders a bare glyph with no hit-target feedback, which
/// reads as an afterthought in a dense footer. This gives every icon the same size, the
/// same corner radius and the same hover response.
struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color?
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovering && !isDisabled ? Color.primary.opacity(0.08) : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }

    private var foreground: AnyShapeStyle {
        if isDisabled { return AnyShapeStyle(.tertiary) }
        if let tint { return AnyShapeStyle(tint) }
        return AnyShapeStyle(.secondary)
    }
}

/// A hairline that matches the rest of the surfaces, rather than `Divider`'s hard line.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }
}
