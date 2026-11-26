import SwiftUI

/// The dashboard is your day.
///
/// Every block is a lane on a ribbon from midnight to midnight: coral where it will guard
/// you, faded where that's already done, dashed while it's switched off, and solid coral
/// while it's on right now. The mascot lives on the ribbon. It peeks over the card's top
/// edge at the current time and walks along it as the day goes, holding on, with the "now"
/// line running down from its hands. Beside it, a speech bubble says the one thing worth
/// knowing right now, on whichever side has room.
///
/// Replaced the greeting-and-stat-card dashboard on 26 Nov 2026 at the user's request: a
/// different idea, not a restyle. Sorbet throughout (coral leads, mint means on/done).
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    let onAddBlock: () -> Void
    let onSelect: (Block) -> Void

    var body: some View {
        // The ribbon and the sentence follow the clock, so the page redraws once a minute.
        TimelineView(.everyMinute) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: PlayRhythm.section + 4) {
                    header(now: timeline.date)
                    if needsAttention { permissions }
                    DayStage(
                        now: timeline.date,
                        blocks: model.store.blocks,
                        sentence: sentence(now: timeline.date),
                        mood: mood,
                        onAddBlock: onAddBlock,
                        onSelect: onSelect
                    )
                    facts(now: timeline.date)
                }
                .padding(.horizontal, PlayRhythm.page)
                .padding(.top, 22)
                .padding(.bottom, 32)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
        }
    }

    // MARK: Header

    private func header(now: Date) -> some View {
        HStack(alignment: .bottom, spacing: PlayRhythm.inner) {
            VStack(alignment: .leading, spacing: 3) {
                Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                    .font(PlayType.rounded(11, .bold))
                    .tracking(0.9)
                    .foregroundStyle(Paper.coralText)
                Text(greeting(now: now))
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

    private func greeting(now: Date) -> String {
        switch Calendar.current.component(.hour, from: now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Hello, night owl"
        }
    }

    // MARK: What the mascot says

    private var active: [Block] { model.store.displayedActiveBlocks }

    private var mood: MascotMood {
        if needsAttention { return .curious }
        return model.store.blocks.isEmpty ? .happy : .calm
    }

    /// One sentence, in a friend's voice, about right now.
    private func sentence(now: Date) -> String {
        if needsAttention { return "One setting needs your OK before I can guard you properly. It’s just above." }
        if model.store.blocks.isEmpty { return "Make a block and I’ll stand guard over your day." }

        if !active.isEmpty {
            let names = ListFormatter.localizedString(byJoining: active.map(\.name))
            let verb = active.count == 1 ? "has" : "have"
            if active.count == 1, let end = DayPlan.currentEnd(of: active[0], now: now) {
                return "\(names) \(verb) your back until \(end)."
            }
            return "\(names) \(verb) your back. Breathe easy."
        }
        if let next = DayPlan.nextStart(in: model.store.blocks, now: now) {
            return "All quiet for now. \(next.block.name) takes over at \(next.time)."
        }
        return "All quiet. Switch a block on whenever you’d like backup."
    }

    // MARK: Permissions

    private var backgroundNeedsAttention: Bool {
        !model.backgroundBlockingAllowed || model.backgroundServiceOffline
    }

    private var needsAttention: Bool {
        model.browserAccessNeedsAttention || backgroundNeedsAttention || model.launchAtLoginNeedsApproval
    }

    private var permissions: some View {
        VStack(spacing: 0) {
            if backgroundNeedsAttention {
                permissionRow(.backgroundBlocking, symbol: "bolt.horizontal.fill")
            }
            if model.browserAccessNeedsAttention {
                if backgroundNeedsAttention { RowDivider() }
                permissionRow(.browserAccess, symbol: "safari.fill")
            }
            if model.launchAtLoginNeedsApproval {
                if backgroundNeedsAttention || model.browserAccessNeedsAttention { RowDivider() }
                permissionRow(.openAtLogin, symbol: "power")
            }
        }
        .padding(PlayRhythm.card)
        .paperCard(radius: 20)
    }

    private func permissionRow(_ permission: BlockingPermissionRow.Permission, symbol: String) -> some View {
        let feedback = BlockingPermissionRow.feedback(for: permission, model: model)
        return PermissionLine(
            symbol: symbol,
            title: BlockingPermissionRow.title(for: permission),
            detail: feedback.detail,
            action: feedback.action
        )
    }

    // MARK: Facts

    @ViewBuilder
    private func facts(now: Date) -> some View {
        let blocks = model.store.blocks
        if !blocks.isEmpty {
            let paused = blocks.reduce(0) { $0 + $1.stats.timesTriggered }
            let last = blocks.compactMap(\.stats.lastTriggered).max()
            HStack(spacing: PlayRhythm.tile) {
                FactPill(symbol: "wind", text: paused == 1 ? "Paused once" : "Paused \(paused) times")
                if let last {
                    FactPill(symbol: "clock", text: "Last pause \(last.formatted(.relative(presentation: .named, unitsStyle: .wide)))")
                }
                if !active.isEmpty, let next = DayPlan.nextStart(in: blocks, now: now) {
                    FactPill(symbol: "calendar", text: "Next: \(next.block.name) at \(next.time)")
                }
                Spacer(minLength: PlayRhythm.inner)
                HStack(spacing: 12) {
                    LegendKey(kind: .on, text: "On now")
                    LegendKey(kind: .later, text: "Later")
                    LegendKey(kind: .off, text: "Off")
                }
                .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - The day, worked out

/// Where each block falls on today's ribbon, in minutes from local midnight.
enum DayPlan {
    static let dayMinutes: Double = 24 * 60

    struct Span: Hashable {
        var start: Double
        var end: Double

        func contains(_ minute: Double) -> Bool { start <= minute && minute < end }
    }

    static func minutes(of date: Date, calendar: Calendar = .current) -> Double {
        date.timeIntervalSince(calendar.startOfDay(for: date)) / 60
    }

    /// Today's spans for one block. A window that runs past midnight shows its evening on
    /// the day it starts, and its small hours on the next.
    static func spans(for block: Block, now: Date, calendar: Calendar = .current) -> [Span] {
        switch block.schedule {
        case .always:
            return [Span(start: 0, end: dayMinutes)]
        case .scheduled(let windows):
            let weekdayValue = calendar.component(.weekday, from: now)
            guard let today = Weekday(rawValue: weekdayValue),
                  let yesterday = Weekday(rawValue: weekdayValue == 1 ? 7 : weekdayValue - 1)
            else { return [] }
            var spans: [Span] = []
            for window in windows {
                let start = Double(window.start.minutes), end = Double(window.end.minutes)
                if start < end {
                    if window.days.contains(today) { spans.append(Span(start: start, end: end)) }
                } else if start > end {
                    if window.days.contains(today) { spans.append(Span(start: start, end: dayMinutes)) }
                    if window.days.contains(yesterday), end > 0 { spans.append(Span(start: 0, end: end)) }
                }
            }
            return spans.sorted { $0.start < $1.start }
        case .manual:
            guard block.isEnabled, let ends = block.manualRunEndsAt, ends > now else { return [] }
            let current = minutes(of: now, calendar: calendar)
            let end = calendar.isDate(ends, inSameDayAs: now) ? minutes(of: ends, calendar: calendar) : dayMinutes
            return [Span(start: current, end: max(current + 1, end))]
        }
    }

    /// A clock time for a minute of today. The end of the day reads as midnight.
    static func clock(_ minute: Double, now: Date, calendar: Calendar = .current) -> String {
        if minute >= dayMinutes { return "midnight" }
        let date = calendar.startOfDay(for: now).addingTimeInterval(minute * 60)
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// When the running block stops guarding you today, if it does.
    static func currentEnd(of block: Block, now: Date) -> String? {
        if case .always = block.schedule {
            return block.lock.isLocked(at: now) ? block.lock.engagedUntil.map { $0.formatted(date: .omitted, time: .shortened) } : nil
        }
        let minute = minutes(of: now)
        guard let span = spans(for: block, now: now).first(where: { $0.contains(minute) }) else { return nil }
        return clock(span.end, now: now)
    }

    /// The next switched-on block to start later today.
    static func nextStart(in blocks: [Block], now: Date) -> (block: Block, time: String)? {
        let minute = minutes(of: now)
        let upcoming = blocks
            .filter { $0.isEnabled && !$0.isActive(at: now) }
            .compactMap { block in spans(for: block, now: now).first { $0.start > minute }.map { (block, $0.start) } }
            .min { $0.1 < $1.1 }
        return upcoming.map { ($0.0, clock($0.1, now: now)) }
    }
}

// MARK: - The stage: the mascot on top of your day

private struct DayStage: View {
    let now: Date
    let blocks: [Block]
    let sentence: String
    let mood: MascotMood
    let onAddBlock: () -> Void
    let onSelect: (Block) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0
    @State private var start = Date()
    @State private var risen = false

    /// Fixed columns, so the ribbon, the needle and the mascot agree on where "now" is.
    static let inset: CGFloat = PlayRhythm.card
    static let labelWidth: CGFloat = 176
    static let switchWidth: CGFloat = 52
    static let gap: CGFloat = PlayRhythm.inner

    private var band: CGFloat { MascotView.cardEdgeOffset }
    private var mascotWidth: CGFloat { MascotView.size.width }
    /// The body is narrower than the drawing box, which leaves room for a waving hand.
    private let bodyHalfWidth: CGFloat = 64

    private var trackStart: CGFloat { Self.inset + Self.labelWidth + Self.gap }
    private var trackWidth: CGFloat {
        max(1, width - Self.inset * 2 - Self.labelWidth - Self.switchWidth - Self.gap * 2)
    }

    private var nowFraction: CGFloat { CGFloat(DayPlan.minutes(of: now) / DayPlan.dayMinutes) }

    /// Where the needle falls, from the card's leading edge.
    private var needleX: CGFloat {
        blocks.isEmpty ? width / 2 : trackStart + trackWidth * nowFraction
    }

    /// The mascot's drawing box, centred on the needle but kept inside the card.
    private var mascotX: CGFloat {
        min(max(needleX - mascotWidth / 2, -20), max(0, width - mascotWidth + 20))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            bubble

            MascotView(mood: mood, layer: .body, animates: !reduceMotion, start: start)
                .offset(y: risen ? 0 : 80)
                .frame(width: mascotWidth, height: band, alignment: .top)
                .clipped()
                .offset(x: mascotX)
                .allowsHitTesting(false)

            card
                .padding(.top, band)

            MascotView(mood: mood, layer: .hands, animates: !reduceMotion, start: start)
                .opacity(risen ? 1 : 0)
                .offset(x: mascotX, y: risen ? 0 : 6)
                .allowsHitTesting(false)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.85), value: mascotX)
        .onAppear {
            guard !reduceMotion else {
                risen = true
                return
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.66).delay(0.25)) { risen = true }
        }
    }

    // MARK: The speech bubble

    /// Beside the mascot's head, on whichever side has more room.
    private var bubble: some View {
        let left = needleX - bodyHalfWidth - 14
        let right = width - (needleX + bodyHalfWidth + 14)
        let onLeft = left >= right
        let room = max(160, min(380, onLeft ? left : right))
        return SpeechBubble(text: sentence, tailOnTrailingEdge: onLeft)
            .frame(width: room, alignment: onLeft ? .trailing : .leading)
            .frame(height: band - 18, alignment: .center)
            .offset(x: onLeft ? max(0, left - room) : needleX + bodyHalfWidth + 14)
            .opacity(width > 0 ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.86), value: onLeft)
    }

    // MARK: The card

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            if blocks.isEmpty {
                empty
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                        DayLane(
                            block: block,
                            now: now,
                            index: index,
                            trackWidth: trackWidth,
                            onSelect: { onSelect(block) }
                        )
                    }
                }
                .overlay(alignment: .topLeading) { needle }

                axis
                    .padding(.top, 8)
            }
        }
        .padding(Self.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(radius: 26)
    }

    /// The "now" line, falling from the mascot's hands through every lane.
    private var needle: some View {
        Capsule()
            .fill(Paper.coral)
            .frame(width: 2)
            .frame(maxHeight: .infinity)
            // Up to the card's top edge, where the mascot holds on.
            .padding(.top, -Self.inset)
            .offset(x: needleX - Self.inset - 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var axis: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Paper.hairline)
                .frame(width: trackWidth, height: 1)
            ForEach([0.0, 6, 12, 18, 24], id: \.self) { hour in
                // The hour alone, in the system's own format: "6 AM", or "06" where the
                // clock is 24-hour.
                Text(Calendar.current.startOfDay(for: now).addingTimeInterval(hour * 3600).formatted(.dateTime.hour()))
                    .font(PlayType.rounded(10, .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 64)
                    .offset(x: trackWidth * hour / 24 - 32, y: 5)
            }
            Text(now.formatted(date: .omitted, time: .shortened))
                .font(PlayType.rounded(10.5, .bold))
                .foregroundStyle(Paper.onCoral)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(Capsule(style: .continuous).fill(Paper.coral))
                .fixedSize()
                .frame(width: 80)
                .offset(x: trackWidth * nowFraction - 40, y: 2)
        }
        .frame(height: 22, alignment: .top)
        .padding(.leading, Self.labelWidth + Self.gap)
        .accessibilityHidden(true)
    }

    private var empty: some View {
        VStack(spacing: PlayRhythm.inner) {
            Text("Blocks appear here as lanes across your day, coral wherever they guard you.")
                .font(PlayType.rounded(13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onAddBlock) {
                Label("Make your first block", systemImage: "plus")
            }
            .buttonStyle(PillButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

// MARK: - One lane

private struct DayLane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let block: Block
    let now: Date
    let index: Int
    let trackWidth: CGFloat
    let onSelect: () -> Void

    @State private var isHovering = false
    @State private var drawn = false

    private var isActive: Bool { model.store.activeBlockIDs.contains(block.id) }
    private var nowMinute: Double { DayPlan.minutes(of: now) }

    var body: some View {
        HStack(spacing: DayStage.gap) {
            label
                .frame(width: DayStage.labelWidth, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)

            track
                .frame(width: trackWidth, height: 26, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)

            ShiftSwitch(
                isOn: .constant(block.isEnabled),
                isLocked: block.isLocked(),
                action: toggle
            )
            .accessibilityLabel("\(block.name) enabled")
            .disabled(block.canStartTimedRun)
            .frame(width: DayStage.switchWidth, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Paper.tile.opacity(isHovering ? 1 : 0))
                .padding(.horizontal, -8)
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .contextMenu {
            Button("Edit", action: onSelect)
            if block.canStartTimedRun {
                Divider()
                ForEach([25, 50, 90], id: \.self) { minutes in
                    Button("Start for \(minutes) minutes") {
                        if model.store.startManualRun(id: block.id, minutes: minutes) {
                            model.log("Started \(block.name) for \(minutes) minutes", symbol: "timer")
                        }
                    }
                }
            }
        }
        .onAppear {
            guard !reduceMotion else {
                drawn = true
                return
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82).delay(0.15 + Double(index) * 0.08)) { drawn = true }
        }
        .accessibilityElement(children: .contain)
    }

    private var label: some View {
        HStack(spacing: 10) {
            Image(systemName: block.symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isActive ? Paper.onCoral : Paper.ink.opacity(0.75))
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isActive ? Paper.coral : Paper.tile)
                }
                .scaleEffect(isActive && !reduceMotion ? 1.04 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.name)
                    .font(PlayType.rounded(14, .semibold))
                    .foregroundStyle(Paper.ink)
                    .lineLimit(1)
                Text(status)
                    .font(PlayType.rounded(11.5, showsLock ? .semibold : .regular))
                    .foregroundStyle(showsLock ? AnyShapeStyle(Paper.coralText) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
        }
    }

    private var showsLock: Bool { block.isLocked() && !block.requiresUnlockChallenge() }

    private var status: String {
        if showsLock { return block.lockStatus() }
        if block.canStartTimedRun { return "Right-click to start a run" }
        if isActive { return block.contentsSummary }
        return block.isEnabled ? block.scheduleSummary : "Switched off"
    }

    // MARK: The ribbon

    private var track: some View {
        let spans = DayPlan.spans(for: block, now: now)
        return ZStack(alignment: .leading) {
            // The rail every lane runs along, so empty hours still read as time.
            Capsule(style: .continuous)
                .fill(Paper.tile)
                .frame(height: 6)

            ForEach(spans, id: \.self) { span in
                segments(for: span)
            }
        }
        .scaleEffect(x: drawn ? 1 : 0.02, anchor: .leading)
        .opacity(drawn ? 1 : 0)
        .help(spanHelp(spans))
    }

    /// One span, split at now: what's behind you fades, what's ahead stays bright.
    @ViewBuilder
    private func segments(for span: DayPlan.Span) -> some View {
        let past = DayPlan.Span(start: span.start, end: min(span.end, nowMinute))
        let ahead = DayPlan.Span(start: max(span.start, nowMinute), end: span.end)

        if !block.isEnabled {
            // Switched off, so nothing was guarded earlier either: the whole window is dashed.
            piece(span, style: .off)
        } else {
            if past.end > past.start {
                piece(past, style: .done)
            }
            if ahead.end > ahead.start {
                if isActive && span.contains(nowMinute) {
                piece(ahead, style: .on, label: "until \(DayPlan.clock(span.end, now: now))")
                } else {
                    piece(ahead, style: .later, label: DayPlan.clock(span.start, now: now))
                }
            }
        }
    }

    private func piece(_ span: DayPlan.Span, style: LaneStyle, label: String? = nil) -> some View {
        let x = trackWidth * span.start / DayPlan.dayMinutes
        let width = max(6, trackWidth * (span.end - span.start) / DayPlan.dayMinutes)
        return Segment(style: style, label: width > 74 ? label : nil)
            .frame(width: width, height: 22)
            .offset(x: x)
    }

    private func spanHelp(_ spans: [DayPlan.Span]) -> String {
        guard !spans.isEmpty else { return block.scheduleSummary }
        return spans.map { "\(DayPlan.clock($0.start, now: now)) – \(DayPlan.clock($0.end, now: now))" }
            .joined(separator: ", ")
    }

    private func toggle(_ enabled: Bool) {
        switch model.store.setEnabled(enabled, for: block.id) {
        case .needsRandomString:
            model.requestBlockUnlock(id: block.id)
        case .needsTimedStart:
            onSelect()
        case .changed, .refusedLocked:
            break
        }
    }
}

// MARK: - Pieces

private enum LaneStyle {
    case on, later, done, off
}

private struct Segment: View {
    let style: LaneStyle
    let label: String?

    var body: some View {
        let shape = Capsule(style: .continuous)
        ZStack(alignment: .leading) {
            switch style {
            case .on:
                shape.fill(Paper.coral)
            case .later:
                shape.fill(Paper.coralSoft)
                shape.strokeBorder(Paper.coral, lineWidth: 1.5)
            case .done:
                shape.fill(Paper.hairline)
            case .off:
                shape.strokeBorder(Paper.ink.opacity(0.28), style: StrokeStyle(lineWidth: 1.3, dash: [4, 3]))
            }
            if let label {
                Text(label)
                    .font(PlayType.rounded(10.5, .bold))
                    .foregroundStyle(style == .on ? Paper.onCoral : Paper.coralText)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
            }
        }
    }
}

private struct LegendKey: View {
    let kind: LaneStyle
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Segment(style: kind, label: nil)
                .frame(width: 16, height: 9)
            Text(text)
                .font(PlayType.rounded(11, .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// What the mascot says, with a little tail pointing back at it.
private struct SpeechBubble: View {
    let text: String
    let tailOnTrailingEdge: Bool

    var body: some View {
        Text(text)
            .font(PlayType.rounded(16, .bold))
            .foregroundStyle(Paper.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .paperCard(radius: 20)
            // The tail's base overlaps the bubble's edge by a point, hiding the hairline
            // there, so bubble and tail read as one shape.
            .overlay(alignment: tailOnTrailingEdge ? .trailing : .leading) {
                ZStack {
                    BubbleTail(closed: true).fill(Paper.card)
                    BubbleTail(closed: false).stroke(Paper.hairline, lineWidth: 1)
                }
                .frame(width: 10, height: 18)
                .scaleEffect(x: tailOnTrailingEdge ? 1 : -1)
                .offset(x: tailOnTrailingEdge ? 9 : -9)
                .allowsHitTesting(false)
            }
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.25), value: text)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A tail pointing right from its base on the left edge. Open, it's just the two outer
/// sides, for the outline.
private struct BubbleTail: Shape {
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        if closed { path.closeSubpath() }
        return path
    }
}

private struct FactPill: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Paper.coralText)
            Text(text)
                .font(PlayType.rounded(12, .semibold))
                .foregroundStyle(Paper.ink.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule(style: .continuous).fill(Paper.card))
        .overlay(Capsule(style: .continuous).strokeBorder(Paper.hairline, lineWidth: 1))
    }
}
