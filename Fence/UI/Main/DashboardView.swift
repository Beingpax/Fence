import Combine
import SwiftUI

/// The dashboard is your day, as tiles over a timeline.
///
/// At the top, a few tiles answer the questions people open it with: what's guarding me
/// right now and until when (the coral "now" tile), hello and a new block (the greeting
/// tile, with the mascot), how many pulls today, and what starts next. Below, every block
/// is a lane across the day: solid coral while it's on, faded once done, outlined when it
/// comes later, dashed while switched off. Today's pulls are dots in a lane of their own,
/// and a coral line marks now.
///
/// Chosen on 26 Nov 2026 from `Studies/dashboard-ideas.html` (the "Timeline" idea with the
/// Bento tiles). Replaced the ribbon with the mascot walking along it, which the user found
/// badly animated. Motion is small on purpose: bars grow in once, the mascot breathes.
///
/// Several blocks on at once: the "now" tile names how many and lists them (up to three),
/// each with when it stops and, for a scheduled window, how far through it you are,
/// soonest to end first. One block gets the big line and a bar. None turns the tile calm
/// and white, with what starts next.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    let onAddBlock: () -> Void

    /// When today's pulls started, from the journal.
    @State private var pulls: [Date] = []
    /// The page's width, which picks side-by-side or stacked tiles. Starts wide so the
    /// common case doesn't flash the stacked layout first.
    @State private var width: CGFloat = 1000

    /// Below this the top tiles stack in one column.
    private static let sideBySide: CGFloat = 700
    /// The page grows with the window up to this, then stays centred.
    private static let maxPageWidth: CGFloat = 1180
    /// Side by side, the top tiles have one fixed height (26 Nov 2026, the user's call:
    /// width follows the window, height doesn't). Several blocks on need a little more.
    private static let tileHeight: CGFloat = 300
    private static let tileHeightSeveral: CGFloat = 336

    var body: some View {
        // The tiles and the timeline follow the clock, so the page redraws once a minute.
        TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            ScrollView {
                VStack(alignment: .leading, spacing: PlayRhythm.section) {
                    if needsAttention { permissions }
                    tiles(now: now)
                    DayTimeline(
                        now: now,
                        blocks: model.store.blocks,
                        pulls: todaysPulls(now: now),
                        onAddBlock: onAddBlock
                    )
                }
                // Measure the width we're given, never the width the contents ask for.
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .padding(.horizontal, PlayRhythm.page)
                .padding(.top, 22)
                .padding(.bottom, 32)
                .frame(maxWidth: Self.maxPageWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
            // Read again when the day turns, so yesterday's pulls fall away at midnight.
            .task(id: Calendar.current.startOfDay(for: now)) { await reloadPulls() }
        }
        .onReceive(
            DistributedNotificationCenter.default()
                .publisher(for: ReachJournal.changed)
                .receive(on: RunLoop.main)
        ) { _ in
            Task { await reloadPulls() }
        }
    }

    private func reloadPulls() async {
        let entries = await ReachJournal.shared.entries(since: Calendar.current.startOfDay(for: .now))
        pulls = entries.map(\.startedAt).sorted()
    }

    private func todaysPulls(now: Date) -> [Date] {
        pulls.filter { Calendar.current.isDate($0, inSameDayAs: now) }
    }

    // MARK: The tiles

    /// The clock follows the tile's width, within reason.
    private func clockSize(width: CGFloat) -> CGFloat {
        min(100, max(60, width * 0.2))
    }

    @ViewBuilder
    private func tiles(now: Date) -> some View {
        let guards = active
            .map { DayPlan.guardInfo(for: $0, now: now) }
            .sorted { $0.minutesLeft < $1.minutesLeft }
        let next = DayPlan.nextStart(in: model.store.blocks, now: now)
        let pullsToday = todaysPulls(now: now)

        if width >= Self.sideBySide {
            let height = guards.count > 1 ? Self.tileHeightSeveral : Self.tileHeight
            let column = (width - PlayRhythm.section) / 2
            HStack(alignment: .top, spacing: PlayRhythm.section) {
                VStack(spacing: PlayRhythm.section) {
                    greeting(now: now)
                    HStack(spacing: PlayRhythm.section) {
                        PullsTile(now: now, pulls: pullsToday, open: openJournal)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        NextTile(next: next)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                NowTile(
                    now: now,
                    guards: guards,
                    next: next,
                    hasBlocks: !model.store.blocks.isEmpty,
                    clockSize: clockSize(width: column)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: height)
        } else {
            VStack(spacing: PlayRhythm.section) {
                greeting(now: now)
                NowTile(now: now, guards: guards, next: next, hasBlocks: !model.store.blocks.isEmpty, clockSize: 60)
                HStack(spacing: PlayRhythm.section) {
                    PullsTile(now: now, pulls: pullsToday, open: openJournal)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    NextTile(next: next)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func openJournal() {
        model.mainSection = .journal
    }

    // MARK: The greeting tile

    /// The date, the greeting and one sentence, with New block in the top corner and the
    /// mascot standing in the bottom corner as an overlay, so it takes no room of its own.
    private func greeting(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: PlayRhythm.inner) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                        .font(PlayType.rounded(11, .bold))
                        .tracking(0.9)
                        .foregroundStyle(Paper.coralText)
                    Text(greetingLine(now: now))
                        .font(PlayType.rounded(26, .bold))
                        .foregroundStyle(Paper.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 0)
                Button(action: onAddBlock) {
                    Label("New block", systemImage: "plus")
                }
                .buttonStyle(PillButtonStyle())
                .fixedSize()
            }
            Text(sentence(now: now))
                .font(PlayType.rounded(13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                // Clear of the mascot in the corner.
                .padding(.trailing, PeekingMascot.footprint)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            PeekingMascot(mood: mood)
                .padding(.trailing, 10)
        }
        // The mascot stands behind the tile's bottom edge; anything below it is cut away.
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .paperCard(radius: 24)
    }

    private func greetingLine(now: Date) -> String {
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
        return model.store.blocks.isEmpty ? .hello : .idle
    }

    /// One sentence, in a friend's voice. The "now" tile already says what's on, so this
    /// doesn't repeat it.
    private func sentence(now: Date) -> String {
        if needsAttention { return "One setting needs your OK before I can guard you properly. It’s just above." }
        if model.store.blocks.isEmpty { return "Make a block and I’ll stand guard over your day." }
        if !active.isEmpty { return "If anything on your lists pulls at you, I’ll step in." }
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
        .paperCard(radius: 24)
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
}

// MARK: - The day, worked out

/// Where each block falls on today's timeline, in minutes from local midnight.
enum DayPlan {
    static let dayMinutes: Double = 24 * 60

    struct Span: Hashable {
        var start: Double
        var end: Double

        func contains(_ minute: Double) -> Bool { start <= minute && minute < end }
    }

    /// What one running block is doing for you, for the "now" tile.
    struct Guard: Identifiable {
        let block: Block
        /// When it stops, short: "until 5:00 PM", "all day".
        let until: String
        /// When the current window began, for a scheduled block: "Since 1:00 PM".
        let since: String?
        /// How far through the current window, 0 to 1, when there is one.
        let progress: Double?
        /// "2 h 20 min to go", when it has an end.
        let remaining: String?
        /// The lock's own words while it's locked: "Locked until restart".
        let lockNote: String?
        /// For ordering: the block that stops soonest comes first. Infinite when it doesn't.
        let minutesLeft: Double

        var id: Block.ID { block.id }

        /// Everything in one line, for a block without a progress bar.
        var summary: String {
            var parts = [until.prefix(1).uppercased() + until.dropFirst()]
            if progress == nil, let remaining { parts.append(remaining) }
            if let lockNote { parts.append(lockNote) }
            return parts.joined(separator: " · ")
        }
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

    /// A schedule time, with the end of the day as midnight.
    private static func clock(_ time: TimeOfDay) -> String {
        time.minutes >= 24 * 60 ? "midnight" : time.formatted
    }

    /// When the running block stops guarding you. An overnight window answers with its
    /// real end the next morning, not midnight.
    static func currentEnd(of block: Block, now: Date) -> String? {
        switch block.schedule {
        case .always:
            return block.lock.isLocked(at: now) ? block.lock.engagedUntil.map { $0.formatted(date: .omitted, time: .shortened) } : nil
        case .scheduled(let windows):
            return windows.first { $0.contains(now) }.map { clock($0.end) }
        case .manual:
            guard let ends = block.manualRunEndsAt, ends > now else { return nil }
            return ends.formatted(date: .omitted, time: .shortened)
        }
    }

    /// What a running block is doing for you right now.
    static func guardInfo(for block: Block, now: Date, calendar: Calendar = .current) -> Guard {
        let lockNote = block.isLocked(at: now) ? block.lockStatus(at: now) : nil
        switch block.schedule {
        case .scheduled(let windows):
            if let window = windows.first(where: { $0.contains(now) }) {
                let start = Double(window.start.minutes), end = Double(window.end.minutes)
                var length = end - start
                if length <= 0 { length += dayMinutes }
                var elapsed = minutes(of: now, calendar: calendar) - start
                if elapsed < 0 { elapsed += dayMinutes }
                let left = max(0, length - elapsed)
                return Guard(
                    block: block,
                    until: "until \(clock(window.end))",
                    since: "Since \(clock(window.start))",
                    progress: min(1, max(0, elapsed / length)),
                    remaining: remainingText(left),
                    lockNote: lockNote,
                    minutesLeft: left
                )
            }
        case .manual:
            if let ends = block.manualRunEndsAt, ends > now {
                let left = ends.timeIntervalSince(now) / 60
                return Guard(
                    block: block,
                    until: "until \(ends.formatted(date: .omitted, time: .shortened))",
                    since: nil,
                    progress: nil,
                    remaining: remainingText(left),
                    lockNote: lockNote,
                    minutesLeft: left
                )
            }
        case .always:
            break
        }
        return Guard(block: block, until: "all day", since: nil, progress: nil, remaining: nil, lockNote: lockNote, minutesLeft: .infinity)
    }

    /// "2 h 20 min to go", "45 min to go".
    static func remainingText(_ minutes: Double) -> String {
        let total = max(1, Int(minutes.rounded(.up)))
        let hours = total / 60, rest = total % 60
        if hours == 0 { return "\(rest) min to go" }
        if rest == 0 { return "\(hours) h to go" }
        return "\(hours) h \(rest) min to go"
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

// MARK: - The "now" tile

/// What's guarding you right now. Coral while anything is on, calm white when nothing is.
private struct NowTile: View {
    let now: Date
    let guards: [DayPlan.Guard]
    let next: (block: Block, time: String)?
    let hasBlocks: Bool
    /// Grows with the tile.
    let clockSize: CGFloat

    /// The most blocks listed by name; the rest are counted.
    private static let listed = 3

    private var isOn: Bool { !guards.isEmpty }
    private var ink: Color { isOn ? Paper.onCoralSolid : Paper.ink }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Text("RIGHT NOW")
                .font(PlayType.rounded(11, .bold))
                .tracking(0.9)
                .foregroundStyle(isOn ? AnyShapeStyle(Paper.onCoralSolid.opacity(0.85)) : AnyShapeStyle(Paper.coralText))

            ClockText(now: now, size: clockSize)
                .foregroundStyle(ink)
                .padding(.top, 6)

            Spacer(minLength: 16)

            if guards.count == 1, let only = guards.first {
                single(only)
            } else if guards.count > 1 {
                several
            } else {
                quiet
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if isOn {
                shape.fill(Paper.coralSolid)
                    .overlay(alignment: .topTrailing) { rings }
                    .clipShape(shape)
                    .shadow(color: Paper.coralSolid.opacity(0.28), radius: 14, y: 8)
            }
        }
        .modifier(CalmCard(isCalm: !isOn))
        .accessibilityElement(children: .combine)
    }

    /// Two faint rings in the corner, so the coral isn't a flat slab.
    private var rings: some View {
        ZStack {
            Circle().strokeBorder(Paper.onCoralSolid.opacity(0.16), lineWidth: 2)
            Circle().strokeBorder(Paper.onCoralSolid.opacity(0.10), lineWidth: 2).padding(36)
        }
        .frame(width: 260, height: 260)
        .offset(x: 80, y: -80)
        .allowsHitTesting(false)
    }

    // MARK: One block on

    private func single(_ item: DayPlan.Guard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("\(item.block.name) has your back")
                    .font(PlayType.rounded(20, .bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if item.lockNote != nil {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                        .opacity(0.85)
                }
            }
            if let progress = item.progress, let since = item.since, let remaining = item.remaining {
                ProgressBar(fraction: progress, height: 10, color: Paper.onCoralSolid)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                HStack {
                    Text(since)
                    Spacer(minLength: 8)
                    Text(remaining)
                }
                .font(PlayType.rounded(12.5, .semibold))
                .opacity(0.88)
                if let lock = item.lockNote {
                    Text(lock)
                        .font(PlayType.rounded(12, .semibold))
                        .opacity(0.75)
                        .padding(.top, 4)
                }
            } else {
                Text(item.summary)
                    .font(PlayType.rounded(12.5, .semibold))
                    .opacity(0.88)
                    .padding(.top, 6)
            }
        }
        .foregroundStyle(Paper.onCoralSolid)
    }

    // MARK: Several on

    private var several: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(guards.count) blocks have your back")
                .font(PlayType.rounded(20, .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            VStack(spacing: 9) {
                ForEach(guards.prefix(Self.listed)) { item in
                    GuardRow(item: item)
                }
            }
            if guards.count > Self.listed {
                Text("and \(guards.count - Self.listed) more")
                    .font(PlayType.rounded(12, .semibold))
                    .opacity(0.8)
            }
        }
        .foregroundStyle(Paper.onCoralSolid)
    }

    // MARK: Nothing on

    private var quiet: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("All quiet")
                .font(PlayType.rounded(20, .bold))
                .foregroundStyle(Paper.ink)
            Text(quietLine)
                .font(PlayType.rounded(13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var quietLine: String {
        if !hasBlocks { return "Make a block, and it shows here while it guards you." }
        if let next { return "Nothing is on. \(next.block.name) starts at \(next.time)." }
        return "Nothing is on. Switch a block on whenever you’d like backup."
    }
}

/// The white card the "now" tile becomes when nothing is on.
private struct CalmCard: ViewModifier {
    let isCalm: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isCalm {
            content.paperCard(radius: 24)
        } else {
            content
        }
    }
}

/// One running block in the "now" tile, when several are on.
private struct GuardRow: View {
    let item: DayPlan.Guard

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.block.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Paper.coralSolid)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Paper.onCoralSolid))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(item.block.name)
                        .font(PlayType.rounded(13.5, .bold))
                        .lineLimit(1)
                    if item.lockNote != nil {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .opacity(0.8)
                            .help(item.lockNote ?? "")
                    }
                    Spacer(minLength: 8)
                    Text(item.until)
                        .font(PlayType.rounded(12, .semibold))
                        .opacity(0.85)
                        .lineLimit(1)
                        .fixedSize()
                }
                if let progress = item.progress {
                    ProgressBar(fraction: progress, height: 5, color: Paper.onCoralSolid)
                }
            }
        }
        .help(item.summary)
    }
}

/// A track with a filled part from its leading edge. The fill keeps its round ends.
private struct ProgressBar: View {
    let fraction: Double
    let height: CGFloat
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        Capsule(style: .continuous)
            .fill(color.opacity(0.28))
            .overlay(alignment: .leading) {
                LeadingCapsule(fraction: shown ? fraction : 0)
                    .fill(color)
            }
            .frame(height: height)
            .onAppear {
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(.smooth(duration: 0.9).delay(0.15)) { shown = true }
                }
            }
            .accessibilityHidden(true)
    }
}

/// A capsule covering `fraction` of the width, never narrower than it is tall.
private struct LeadingCapsule: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let width = max(rect.height, rect.width * CGFloat(min(1, max(0, fraction))))
        return Capsule(style: .continuous).path(in: CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height))
    }
}

/// The time, big, with AM or PM small beside it where the clock is 12-hour.
private struct ClockText: View {
    let now: Date
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.07) {
            Text(now.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()))
                .font(PlayType.rounded(size, .heavy))
                .kerning(-size * 0.035)
                .monospacedDigit()
            if let period = Self.period(for: now) {
                Text(period)
                    .font(PlayType.rounded(size * 0.32, .bold))
                    .opacity(0.8)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(now.formatted(date: .omitted, time: .shortened))
    }

    /// "AM" or "PM", or nothing where the clock is 24-hour.
    static func period(for date: Date) -> String? {
        guard let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current),
              format.contains("a")
        else { return nil }
        let calendar = Calendar.current
        return calendar.component(.hour, from: date) < 12 ? calendar.amSymbol : calendar.pmSymbol
    }
}

// MARK: - Pulls today and Up next

/// How many times something pulled today, with a small strip of when. Opens the Journal.
private struct PullsTile: View {
    let now: Date
    let pulls: [Date]
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                TileLabel(text: "Pulls today")
                Text("\(pulls.count)")
                    .font(PlayType.rounded(40, .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Paper.ink)
                    .padding(.top, 6)
                Text(lastLine)
                    .font(PlayType.rounded(12, .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 14)
                PullStrip(now: now, pulls: pulls)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(SquishButtonStyle())
        .paperCard(radius: 24)
        .help("Open the Journal")
        .accessibilityLabel("\(pulls.count) pulls today. \(lastLine)")
    }

    private var lastLine: String {
        guard let last = pulls.last else { return "None so far" }
        return "Last at \(last.formatted(date: .omitted, time: .shortened))"
    }
}

/// Midnight to midnight as 24 hourly squares, shaded like the timeline's pulls lane, with a
/// line for now.
private struct PullStrip: View {
    let now: Date
    let pulls: [Date]

    var body: some View {
        VStack(spacing: 5) {
            let counts = PullHeat.counts(pulls)
            let peak = counts.max() ?? 0
            Canvas { context, size in
                let gap: CGFloat = 1.5
                let cell = (size.width - gap * 23) / 24
                for hour in 0..<24 {
                    let rect = CGRect(x: CGFloat(hour) * (cell + gap), y: 2, width: cell, height: size.height - 4)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 2.5, style: .continuous),
                        with: .color(PullHeat.fill(count: counts[hour], peak: peak))
                    )
                }
                let x = size.width * DayPlan.minutes(of: now) / DayPlan.dayMinutes
                let line = Path(roundedRect: CGRect(x: x - 1, y: 0, width: 2, height: size.height), cornerRadius: 1)
                context.fill(line, with: .color(Paper.ink))
            }
            .frame(height: 16)
            HStack {
                Text(hour(0))
                Spacer(minLength: 4)
                Text(hour(12))
                Spacer(minLength: 4)
                Text(hour(24))
            }
            .font(PlayType.rounded(9.5, .semibold))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        .accessibilityHidden(true)
    }

    private func hour(_ value: Double) -> String {
        Calendar.current.startOfDay(for: now).addingTimeInterval(value * 3600).formatted(.dateTime.hour())
    }
}

/// The next block to switch itself on today.
private struct NextTile: View {
    let next: (block: Block, time: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                TileLabel(text: "Up next")
                Spacer(minLength: 6)
                if let next {
                    Image(systemName: next.block.symbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Paper.coralSolid)
                }
            }
            if let next {
                Text(next.time)
                    .font(PlayType.rounded(30, .heavy))
                    .foregroundStyle(Paper.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 10)
                Text(next.block.name)
                    .font(PlayType.rounded(12.5, .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Nothing else today")
                    .font(PlayType.rounded(17, .bold))
                    .foregroundStyle(Paper.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                Text("No more blocks start today.")
                    .font(PlayType.rounded(12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .paperCard(radius: 24)
        .accessibilityElement(children: .combine)
    }
}

/// The coral small caps at the top of a tile.
private struct TileLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(PlayType.rounded(11, .bold))
            .tracking(0.9)
            .foregroundStyle(Paper.coralText)
    }
}

// MARK: - The mascot in the greeting tile

/// The mascot, smaller than usual, standing behind the greeting tile's bottom edge with its
/// hands on it. The tile clips whatever falls below.
private struct PeekingMascot: View {
    let mood: MascotMood

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private static let pointScale: CGFloat = 0.72
    /// How much width text beside it should leave free.
    static var footprint: CGFloat { MascotView.size(pointScale: pointScale).width - 14 }

    var body: some View {
        let size = MascotView.size(pointScale: Self.pointScale)
        let edge = MascotView.cardEdgeOffset(pointScale: Self.pointScale)
        ZStack(alignment: .top) {
            MascotView(mood: mood, layer: .body, animates: !reduceMotion, start: start, pointScale: Self.pointScale)
                .frame(width: size.width, height: edge, alignment: .top)
                .clipped()
            MascotView(mood: mood, layer: .hands, animates: !reduceMotion, start: start, pointScale: Self.pointScale)
        }
        // As tall as the body above the edge, so the edge meets the tile's bottom; the hands
        // hang a little below and are cut there.
        .frame(width: size.width, height: edge, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - The timeline

/// Every block as a lane across the day, then a lane of today's pulls, with a line at now.
///
/// Display only (26 Nov 2026, the user's call): no switches, no clicking into a block, no
/// menu and no hover. Blocks are changed on the Blocks page.
private struct DayTimeline: View {
    let now: Date
    let blocks: [Block]
    let pulls: [Date]
    let onAddBlock: () -> Void

    @State private var width: CGFloat = 0
    /// The hour square under the pointer, and the one clicked to keep its card open.
    @State private var hoveredHour: Int?
    @State private var pinnedHour: Int?

    /// Fixed columns, so the lanes, the axis and the now line agree on where "now" is.
    static let labelWidth: CGFloat = 156
    static let gap: CGFloat = PlayRhythm.inner
    static let laneHeight: CGFloat = 36

    private var trackWidth: CGFloat {
        max(1, width - Self.labelWidth - Self.gap)
    }

    private var nowFraction: CGFloat { CGFloat(DayPlan.minutes(of: now) / DayPlan.dayMinutes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    TileLabel(text: "Your day")
                    Spacer(minLength: 16)
                    legend
                }
                TileLabel(text: "Your day")
            }

            if blocks.isEmpty {
                empty
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    axis
                    VStack(spacing: 6) {
                        ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                            DayLane(block: block, now: now, index: index, trackWidth: trackWidth)
                                // The block lanes are display only.
                                .allowsHitTesting(false)
                        }
                        PullLane(pulls: pulls, trackWidth: trackWidth, hovered: $hoveredHour, pinned: $pinnedHour)
                    }
                    .overlay(alignment: .topLeading) { nowLine }
                    // Above the now line, so the line never cuts through it.
                    .overlay(alignment: .bottomLeading) { hourCard }
                }
                // Measure the width we're given, never the width the contents ask for:
                // the bars are placed from it, so it must be free to shrink.
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            }
        }
        .padding(PlayRhythm.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(radius: 24)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            LegendKey(style: .on, text: "On now")
            LegendKey(style: .done, text: "Done")
            LegendKey(style: .later, text: "Later")
            HStack(spacing: 5) {
                HStack(spacing: 2) {
                    ForEach([1, 2, 4], id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(PullHeat.fill(count: level, peak: 4))
                            .frame(width: 8, height: 8)
                    }
                }
                Text("Pulls an hour")
                    .font(PlayType.rounded(11, .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
        .accessibilityHidden(true)
    }

    /// Through every lane, from the time pill on the axis.
    private var nowLine: some View {
        Capsule()
            .fill(Paper.coralSolid)
            .frame(width: 2)
            .frame(maxHeight: .infinity)
            .padding(.top, -8)
            .offset(x: Self.labelWidth + Self.gap + trackWidth * nowFraction - 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The hour's span and how many pulls it held, floating over its square: while the
    /// pointer is on it, or after a click until the square is clicked again.
    @ViewBuilder
    private var hourCard: some View {
        if let hour = hoveredHour ?? pinnedHour {
            let count = PullHeat.counts(pulls)[hour]
            let centre = Self.labelWidth + Self.gap + trackWidth * (CGFloat(hour) + 0.5) / 24
            PullHourCard(now: now, hour: hour, count: count)
                .frame(width: PullHourCard.width)
                .offset(x: centre - PullHourCard.width / 2, y: -(Self.laneHeight + 10))
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// Hour labels over the lanes, every three hours when there's room, and the time now.
    /// Placed by offset, so they never change the card's size.
    private var axis: some View {
        let step: Double = trackWidth > 440 ? 3 : 6
        let hours = Array(stride(from: 0.0, through: 24, by: step))
        return ZStack(alignment: .topLeading) {
            ForEach(hours, id: \.self) { hour in
                Text(Calendar.current.startOfDay(for: now).addingTimeInterval(hour * 3600).formatted(.dateTime.hour()))
                    .font(PlayType.rounded(10, .semibold))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .frame(width: 64)
                    .offset(x: trackWidth * hour / 24 - 32, y: 3)
                    // Hidden where the time pill would cover it.
                    .opacity(abs(CGFloat(hour / 24) - nowFraction) * trackWidth < 40 ? 0 : 1)
            }
            Text(now.formatted(date: .omitted, time: .shortened))
                .font(PlayType.rounded(10.5, .bold))
                .foregroundStyle(Paper.onCoralSolid)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule(style: .continuous).fill(Paper.coralSolid))
                .fixedSize()
                .frame(width: 90)
                .offset(x: trackWidth * nowFraction - 45)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 20, maxHeight: 20, alignment: .topLeading)
        .padding(.leading, Self.labelWidth + Self.gap)
        .allowsHitTesting(false)
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

    @State private var drawn = false

    private var isActive: Bool { model.store.activeBlockIDs.contains(block.id) }
    private var nowMinute: Double { DayPlan.minutes(of: now) }

    var body: some View {
        HStack(spacing: DayTimeline.gap) {
            label
                .frame(width: DayTimeline.labelWidth, alignment: .leading)

            // Flexible, so the lane always fills the card; `trackWidth` only places the
            // bars inside it.
            track
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: DayTimeline.laneHeight, maxHeight: DayTimeline.laneHeight)
        }
        .padding(.vertical, 3)
        .onAppear {
            guard !reduceMotion else {
                drawn = true
                return
            }
            withAnimation(.smooth(duration: 0.6).delay(0.1 + Double(index) * 0.06)) { drawn = true }
        }
        .accessibilityElement(children: .combine)
    }

    private var label: some View {
        HStack(spacing: 10) {
            Image(systemName: block.symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isActive ? Paper.onCoralSolid : Paper.ink.opacity(0.75))
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isActive ? Paper.coralSolid : Paper.tile)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(block.name)
                    .font(PlayType.rounded(13.5, .semibold))
                    .foregroundStyle(Paper.ink)
                    .lineLimit(1)
                Text(status)
                    .font(PlayType.rounded(11, showsLock || isActive ? .semibold : .regular))
                    .foregroundStyle(statusStyle)
                    .lineLimit(1)
            }
        }
    }

    private var showsLock: Bool { block.isLocked() && !block.requiresUnlockChallenge() }

    private var status: String {
        if showsLock { return block.lockStatus() }
        if isActive { return DayPlan.currentEnd(of: block, now: now).map { "On until \($0)" } ?? "On" }
        if !block.isEnabled { return "Off" }
        let spans = DayPlan.spans(for: block, now: now)
        if let later = spans.first(where: { $0.start > nowMinute }) {
            return "Starts \(DayPlan.clock(later.start, now: now))"
        }
        return spans.isEmpty ? "Not on today" : "Done for today"
    }

    private var statusStyle: AnyShapeStyle {
        if showsLock { return AnyShapeStyle(Paper.coralText) }
        if isActive { return AnyShapeStyle(Paper.mint) }
        return AnyShapeStyle(.secondary)
    }

    // MARK: The track

    private var track: some View {
        let spans = DayPlan.spans(for: block, now: now)
        // The rail every lane runs along, so empty hours still read as time. The bars ride
        // in an overlay so they can never push the lane wider than the card.
        return RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Paper.tile.opacity(0.7))
            .overlay(alignment: .leading) {
                ZStack(alignment: .leading) {
                    ForEach(spans, id: \.self) { span in
                        bars(for: span)
                    }
                }
                .scaleEffect(x: drawn ? 1 : 0.02, anchor: .leading)
                .opacity(drawn ? 1 : 0)
            }
            .overlay(alignment: .leading) {
                if spans.isEmpty {
                    Text(block.isEnabled ? "Not on today" : "Off today")
                        .font(PlayType.rounded(11, .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 12)
                }
            }
    }

    /// One bar per span. A span that runs through now stays one continuous bar, its colour
    /// changing at the now line: done on the left, on (or later) on the right.
    @ViewBuilder
    private func bars(for span: DayPlan.Span) -> some View {
        let ahead: LaneStyle = isActive && span.contains(nowMinute) ? .on : .later
        let aheadLabel = ahead == .on ? onLabel(span) : "From \(DayPlan.clock(span.start, now: now))"

        if !block.isEnabled && !isActive {
            // Switched off, so nothing was guarded earlier either: the whole window is dashed.
            piece(span, style: .off, label: range(span))
        } else if span.end <= nowMinute {
            piece(span, style: .done, label: range(span))
        } else if span.start >= nowMinute {
            piece(span, style: .later, label: aheadLabel)
        } else {
            split(span, ahead: ahead, label: aheadLabel)
        }
    }

    private func split(_ span: DayPlan.Span, ahead: LaneStyle, label: String) -> some View {
        let x = trackWidth * span.start / DayPlan.dayMinutes
        let width = max(6, trackWidth * (span.end - span.start) / DayPlan.dayMinutes)
        let doneWidth = trackWidth * (nowMinute - span.start) / DayPlan.dayMinutes
        let fits = CGFloat(label.count) * 6.2 + 20 <= width - doneWidth
        return SplitBar(doneWidth: doneWidth, ahead: ahead, label: fits ? label : nil)
            .frame(width: width, height: DayTimeline.laneHeight - 10)
            .offset(x: x)
    }

    private func onLabel(_ span: DayPlan.Span) -> String {
        if span.start <= 0 && span.end >= DayPlan.dayMinutes { return "All day" }
        return "until \(DayPlan.currentEnd(of: block, now: now) ?? DayPlan.clock(span.end, now: now))"
    }

    private func range(_ span: DayPlan.Span) -> String {
        "\(DayPlan.clock(span.start, now: now)) – \(DayPlan.clock(span.end, now: now))"
    }

    private func piece(_ span: DayPlan.Span, style: LaneStyle, label: String?) -> some View {
        let x = trackWidth * span.start / DayPlan.dayMinutes
        let width = max(6, trackWidth * (span.end - span.start) / DayPlan.dayMinutes)
        // A label shows only where it has room.
        let fits = label.map { CGFloat($0.count) * 6.2 + 20 <= width } ?? false
        return LaneBar(style: style, label: fits ? label : nil)
            .frame(width: width, height: DayTimeline.laneHeight - 10)
            .offset(x: x)
    }
}

/// Today's pulls as 24 hourly squares, shaded by how many fell in each hour, like a
/// contribution chart for the day (26 Nov 2026, the user's call; thin lines per pull ran
/// together into a barcode on a busy day). No numbers on the squares: hovering one shows
/// its hour and count in a card, and a click keeps the card open. The only part of the
/// timeline that responds to the pointer.
private struct PullLane: View {
    let pulls: [Date]
    let trackWidth: CGFloat
    @Binding var hovered: Int?
    @Binding var pinned: Int?

    var body: some View {
        let counts = PullHeat.counts(pulls)
        let peak = counts.max() ?? 0
        let shown = hovered ?? pinned
        HStack(spacing: DayTimeline.gap) {
            HStack(spacing: 10) {
                Image(systemName: "wind")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Paper.ink.opacity(0.75))
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Paper.tile))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Pulls")
                        .font(PlayType.rounded(13.5, .semibold))
                        .foregroundStyle(Paper.ink)
                    Text(pulls.isEmpty ? "None today" : "\(pulls.count) today")
                        .font(PlayType.rounded(11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: DayTimeline.labelWidth, alignment: .leading)

            // One square per hour, equal widths, so each lines up with its hour on the axis.
            HStack(spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    let count = counts[hour]
                    let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
                    shape
                        .fill(PullHeat.fill(count: count, peak: peak))
                        .overlay {
                            if shown == hour {
                                shape.strokeBorder(Paper.ink.opacity(0.7), lineWidth: 1.5)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside {
                                hovered = hour
                            } else if hovered == hour {
                                hovered = nil
                            }
                        }
                        .onTapGesture {
                            pinned = pinned == hour ? nil : hour
                        }
                }
            }
            .padding(.vertical, 5)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: DayTimeline.laneHeight, maxHeight: DayTimeline.laneHeight)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pulls.isEmpty ? "No pulls today" : "\(pulls.count) pulls today")
    }
}

/// One hour's span and its pulls, in a small card over its square.
private struct PullHourCard: View {
    static let width: CGFloat = 128
    let now: Date
    let hour: Int
    let count: Int

    var body: some View {
        VStack(spacing: 1) {
            Text("\(time(hour)) – \(time(hour + 1))")
                .font(PlayType.rounded(11, .semibold))
                .foregroundStyle(.secondary)
            Text(count == 0 ? "No pulls" : count == 1 ? "1 pull" : "\(count) pulls")
                .font(PlayType.rounded(13.5, .bold))
                .foregroundStyle(Paper.ink)
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Paper.card))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Paper.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
    }

    private func time(_ hour: Int) -> String {
        Calendar.current.startOfDay(for: now).addingTimeInterval(Double(hour) * 3600).formatted(.dateTime.hour())
    }
}

/// Pulls counted by hour and shaded in four steps, relative to the day's busiest hour.
private enum PullHeat {
    static func counts(_ pulls: [Date]) -> [Int] {
        var counts = Array(repeating: 0, count: 24)
        for pull in pulls {
            let hour = Calendar.current.component(.hour, from: pull)
            if counts.indices.contains(hour) { counts[hour] += 1 }
        }
        return counts
    }

    /// 0 for none, then 1 to 4.
    static func level(count: Int, peak: Int) -> Int {
        guard count > 0, peak > 0 else { return 0 }
        return min(4, max(1, Int((Double(count) / Double(peak) * 4).rounded(.up))))
    }

    static func fill(count: Int, peak: Int) -> Color {
        switch level(count: count, peak: peak) {
        case 0: Paper.ink.opacity(0.06)
        case 1: Paper.coralSolid.opacity(0.25)
        case 2: Paper.coralSolid.opacity(0.5)
        case 3: Paper.coralSolid.opacity(0.75)
        default: Paper.coralSolid
        }
    }
}

// MARK: - Pieces

private enum LaneStyle {
    case on, later, done, off
}

private struct LaneBar: View {
    let style: LaneStyle
    let label: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ZStack(alignment: .leading) {
            switch style {
            case .on:
                shape.fill(Paper.coralSolid)
                    .shadow(color: Paper.coralSolid.opacity(0.35), radius: 5, y: 2)
            case .later:
                shape.fill(Paper.coralSolid.opacity(0.08))
                shape.strokeBorder(Paper.coralSolid, lineWidth: 1.5)
            case .done:
                // Behind you, so quiet and neutral: no coral at all.
                shape.fill(Paper.ink.opacity(0.13))
            case .off:
                shape.strokeBorder(Paper.ink.opacity(0.28), style: StrokeStyle(lineWidth: 1.3, dash: [4, 3]))
            }
            if let label {
                Text(label)
                    .font(PlayType.rounded(11, .bold))
                    .foregroundStyle(labelStyle)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
            }
        }
    }

    private var labelStyle: AnyShapeStyle {
        switch style {
        case .on: AnyShapeStyle(Paper.onCoralSolid)
        case .later: AnyShapeStyle(Paper.coralText)
        case .done: AnyShapeStyle(Paper.ink.opacity(0.55))
        case .off: AnyShapeStyle(.secondary)
        }
    }
}

/// One window that runs through now, as a single bar: done on the left of the now line, on
/// (or later) on the right, with no gap between them.
private struct SplitBar: View {
    let doneWidth: CGFloat
    let ahead: LaneStyle
    let label: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ZStack(alignment: .leading) {
            shape.fill(Paper.ink.opacity(0.13))
            Rectangle()
                .fill(ahead == .on ? Paper.coralSolid : Paper.coralSolid.opacity(0.08))
                .padding(.leading, doneWidth)
            if let label {
                Text(label)
                    .font(PlayType.rounded(11, .bold))
                    .foregroundStyle(ahead == .on ? AnyShapeStyle(Paper.onCoralSolid) : AnyShapeStyle(Paper.coralText))
                    .lineLimit(1)
                    .padding(.leading, doneWidth + 10)
                    .padding(.trailing, 10)
            }
        }
        .clipShape(shape)
        .overlay {
            if ahead == .later {
                shape.strokeBorder(Paper.coralSolid, lineWidth: 1.5)
            }
        }
        .shadow(color: ahead == .on ? Paper.coralSolid.opacity(0.3) : .clear, radius: 5, y: 2)
    }
}

private struct LegendKey: View {
    let style: LaneStyle
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            LaneBar(style: style, label: nil)
                .frame(width: 18, height: 9)
            Text(text)
                .font(PlayType.rounded(11, .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// A small fact in a pill, shared with the Journal.
struct FactPill: View {
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
