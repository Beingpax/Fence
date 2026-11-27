import SwiftUI

/// Your blocks, as one calm list.
///
/// The header speaks in the dashboard's voice (coral small caps, then a big title). Below
/// it, every block is a row in a single paper card, in the order you made them, so a row
/// never jumps when you switch it on or off. Each row holds only the main things: the icon,
/// the name, how it stands right now, and the control. The user asked for no list of apps
/// and sites and no extra labels; the editor has the details.
///
/// Replaced a card grid on 26 Nov 2026 that the user found busy and glitchy to scroll.
/// Rules that keep this one smooth: a plain `VStack` (no lazy container recycling rows), no
/// entrance or looping animations, nothing that changes size on hover, and only the status
/// line follows the clock.
struct BlocksView: View {
    @Environment(AppModel.self) private var model
    let onSelect: (Block) -> Void
    let onAddBlock: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PlayRhythm.section + 6) {
                header
                if model.store.blocks.isEmpty {
                    EmptyBlocks(onAddBlock: onAddBlock)
                } else {
                    list
                }
            }
            .padding(.horizontal, PlayRhythm.page)
            .padding(.top, 22)
            .padding(.bottom, 32)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: PlayRhythm.inner) {
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow.uppercased())
                    .font(PlayType.rounded(11, .bold))
                    .tracking(0.9)
                    .foregroundStyle(Paper.coralText)
                Text("Your blocks")
                    .font(PlayType.rounded(30, .bold))
                    .foregroundStyle(Paper.ink)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: PlayRhythm.inner)

            Button(action: onAddBlock) {
                Label("New block", systemImage: "plus")
            }
            .buttonStyle(PillButtonStyle())
            .fixedSize()
        }
    }

    private var eyebrow: String {
        let total = model.store.blocks.count
        let on = model.store.activeBlockIDs.count
        if total == 0 { return "Nothing guarded yet" }
        if on == 0 { return "\(total) block\(total == 1 ? "" : "s") · all quiet" }
        return "\(on) of \(total) on right now"
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.store.blocks.enumerated()), id: \.element.id) { index, block in
                if index > 0 {
                    Rectangle()
                        .fill(Paper.hairline)
                        .frame(height: 1)
                        // Starts under the name, not under the icon.
                        .padding(.leading, BlockRow.iconSize + BlockRow.spacing + BlockRow.inset)
                        .padding(.trailing, BlockRow.inset)
                }
                BlockRow(block: block, onSelect: { onSelect(block) })
            }
        }
        .padding(6)
        .paperCard(radius: 22)
    }
}

// MARK: - One row

private struct BlockRow: View {
    @Environment(AppModel.self) private var model
    let block: Block
    let onSelect: () -> Void

    static let iconSize: CGFloat = 40
    static let spacing: CGFloat = 14
    static let inset: CGFloat = 12

    @State private var isHovering = false
    @State private var showingLockedNotice = false

    private var isActive: Bool { model.store.activeBlockIDs.contains(block.id) }
    private var isLocked: Bool { block.isLocked() }
    private var showsLock: Bool { isLocked && !block.requiresUnlockChallenge() }

    var body: some View {
        HStack(spacing: Self.spacing) {
            Image(systemName: block.symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isActive ? Paper.onCoral : Paper.ink.opacity(0.75))
                .frame(width: Self.iconSize, height: Self.iconSize)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isActive ? Paper.coral : Paper.tile)
                }

            HStack(spacing: 6) {
                Text(block.name)
                    .font(PlayType.rounded(15, .semibold))
                    .foregroundStyle(Paper.ink)
                    .lineLimit(1)
                if showsLock {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Paper.coralText)
                        .help(block.lockStatus())
                        .accessibilityLabel(block.lockStatus())
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            // Only this follows the clock: "On until 5:00 PM", "Starts 9:00 PM".
            TimelineView(.everyMinute) { timeline in
                StatusLabel(status: status(now: timeline.date))
            }
            .fixedSize()

            control
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Paper.tile.opacity(isHovering ? 0.9 : 0))
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .contextMenu {
            Button("Edit…", action: onSelect)
            if block.canStartTimedRun {
                Divider()
                startButtons
            }
            Divider()
            Button("Delete", role: .destructive) {
                if !model.store.delete(id: block.id) { showingLockedNotice = true }
            }
            .disabled(isLocked)
        }
        .alert("“\(block.name)” is locked", isPresented: $showingLockedNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(block.lockStatus())
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Edit", onSelect)
    }

    // MARK: The control

    /// A timed block that isn't running can't simply be switched on: it needs a length.
    /// So it gets a Start menu instead of a switch, rather than a hint to right-click.
    @ViewBuilder
    private var control: some View {
        if block.canStartTimedRun {
            Menu {
                startButtons
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(SoftPillButtonStyle())
            .fixedSize()
            .help("Run this block for a while")
        } else {
            FenceSwitch(
                isOn: .constant(block.isEnabled),
                isLocked: isLocked,
                action: toggle
            )
            .accessibilityLabel("\(block.name) enabled")
        }
    }

    @ViewBuilder
    private var startButtons: some View {
        ForEach([25, 50, 90], id: \.self) { minutes in
            Button("Start for \(minutes) minutes") {
                if model.store.startManualRun(id: block.id, minutes: minutes) {
                    model.log("Started \(block.name) for \(minutes) minutes", symbol: "timer")
                }
            }
        }
    }

    private func toggle(_ enabled: Bool) {
        switch model.store.setEnabled(enabled, for: block.id) {
        case .changed:
            model.log("\(block.name) \(enabled ? "on" : "off")", symbol: enabled ? "shield.fill" : "shield.slash")
        case .refusedLocked:
            showingLockedNotice = true
        case .needsRandomString:
            model.requestBlockUnlock(id: block.id)
        case .needsTimedStart:
            break
        }
    }

    // MARK: Words

    private func status(now: Date) -> StatusLabel.Status {
        if isActive {
            if case .manual = block.schedule, let ends = block.manualRunEndsAt {
                return .on("On until \(ends.formatted(date: .omitted, time: .shortened))")
            }
            if let end = DayPlan.currentEnd(of: block, now: now) { return .on("On until \(end)") }
            return .on("On")
        }
        if block.canStartTimedRun { return .hidden }
        if showsLock { return .locked(block.lockStatus(at: now)) }
        guard block.isEnabled else { return .quiet("Off") }
        if let next = Self.nextStart(of: block, now: now) { return .quiet(next) }
        return .quiet("No times set")
    }

    /// The next time this block starts within a week: "Starts 9:00 PM", "Tomorrow 9:00 AM",
    /// "Mon 9:00 AM". Read from the windows' own start times, so the small hours of last
    /// night's window are never mistaken for a new start.
    private static func nextStart(of block: Block, now: Date) -> String? {
        guard case .scheduled(let windows) = block.schedule else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let minute = Int(DayPlan.minutes(of: now))
        for offset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)) else { continue }
            let starts = windows
                .filter { $0.days.contains(weekday) && $0.start != $0.end }
                .map(\.start.minutes)
                .filter { offset > 0 || $0 > minute }
            guard let first = starts.min() else { continue }
            let time = DayPlan.clock(Double(first), now: day)
            switch offset {
            case 0: return "Starts \(time)"
            case 1: return "Tomorrow \(time)"
            default: return "\(day.formatted(.dateTime.weekday(.abbreviated))) \(time)"
            }
        }
        return nil
    }
}

// MARK: - Pieces

private struct StatusLabel: View {
    enum Status: Equatable {
        case on(String)
        case locked(String)
        case quiet(String)
        case hidden
    }

    let status: Status

    var body: some View {
        switch status {
        case .on(let text):
            HStack(spacing: 6) {
                Circle()
                    .fill(Paper.mint)
                    .frame(width: 7, height: 7)
                Text(text)
            }
            .font(PlayType.rounded(12.5, .semibold))
            .foregroundStyle(Paper.mint)
        case .locked(let text):
            Text(text)
                .font(PlayType.rounded(12.5, .semibold))
                .foregroundStyle(Paper.coralText)
        case .quiet(let text):
            Text(text)
                .font(PlayType.rounded(12.5))
                .foregroundStyle(.secondary)
        case .hidden:
            EmptyView()
        }
    }
}

/// No blocks yet: the mascot holds a welcome card.
private struct EmptyBlocks: View {
    let onAddBlock: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        MascotCard(mood: .thinking, start: start, animates: !reduceMotion) {
            VStack(spacing: PlayRhythm.inner) {
                Text("Let’s make your first block")
                    .font(PlayType.rounded(20, .bold))
                    .foregroundStyle(Paper.ink)
                Text("Pick the sites and apps that pull at you, and when. I’ll step in before they load.")
                    .font(PlayType.rounded(13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onAddBlock) {
                    Label("New block", systemImage: "plus")
                }
                .buttonStyle(PillButtonStyle())
            }
            .padding(26)
        }
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
    }
}
