import Combine
import SwiftUI

/// The journal: every pause, one calm card per day.
///
/// Reads `ReachJournal`, the SQLite file every pause writes to. At the top, how many pauses
/// each of the last two weeks held, because the habit breaking looks like that line falling
/// over weeks. Below, each day that had a pause: when, what was reached for, the feeling
/// named, the words written about it, and how it ended.
///
/// Information, never a grade: no streaks, no scores, no red. Turning back is mint because
/// it's the thing done; "I need it" access is coral; anything else stays neutral.
struct JournalView: View {
    /// How far back the page reads. The database keeps everything.
    private static let shownDays = 28
    private static let trendDays = 14

    @State private var entries: [ReachEntry] = []
    @State private var loaded = false

    var body: some View {
        let now = Date()
        ScrollView {
            VStack(alignment: .leading, spacing: PlayRhythm.section + 4) {
                header(now: now)
                if loaded && entries.isEmpty {
                    emptyCard
                } else if loaded {
                    TrendCard(counts: dailyCounts(now: now), now: now)
                    facts(now: now)
                    ForEach(days) { group in
                        DayCard(day: group.day, entries: group.entries, now: now)
                    }
                }
            }
            .padding(.horizontal, PlayRhythm.page)
            .padding(.top, 22)
            .padding(.bottom, 32)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.never)
        .task { await reload() }
        .onReceive(
            DistributedNotificationCenter.default()
                .publisher(for: ReachJournal.changed)
                .receive(on: RunLoop.main)
        ) { _ in
            Task { await reload() }
        }
    }

    private func reload() async {
        let start = Calendar.current.date(byAdding: .day, value: -(Self.shownDays - 1), to: Calendar.current.startOfDay(for: .now)) ?? .now
        entries = await ReachJournal.shared.entries(since: start)
        loaded = true
    }

    // MARK: Header

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(summaryLine(now: now).uppercased())
                .font(PlayType.rounded(11, .bold))
                .tracking(0.9)
                .foregroundStyle(Paper.coralText)
            Text("Your journal")
                .font(PlayType.rounded(30, .bold))
                .foregroundStyle(Paper.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func summaryLine(now: Date) -> String {
        let week = pauses(inLast: 7, now: now)
        guard !week.isEmpty else { return "No pulls this week" }
        let back = week.filter(\.turnedBack).count
        let total = week.count == 1 ? "1 pull" : "\(week.count) pulls"
        return "\(total) this week · \(back) turned back"
    }

    // MARK: Facts

    @ViewBuilder
    private func facts(now: Date) -> some View {
        let thisWeek = pauses(inLast: 7, now: now)
        let lastWeek = pauses(inLast: 14, now: now).count - thisWeek.count
        HStack(spacing: PlayRhythm.tile) {
            FactPill(symbol: "calendar", text: "\(lastWeek) the week before")
            if let feeling = mostCommonFeeling(in: thisWeek) {
                FactPill(symbol: feeling.symbol, text: "Mostly \(feeling.shortLabel.lowercased())")
            }
            if let hour = peakHour(in: thisWeek) {
                FactPill(symbol: "clock", text: "Most around \(hourLabel(hour))")
            }
            if let target = mostCommonTarget(in: thisWeek) {
                FactPill(symbol: "scope", text: target)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Empty

    private var emptyCard: some View {
        HStack(spacing: PlayRhythm.inner) {
            Image(systemName: "book.closed")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Paper.coralText)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Paper.coralSoft))
            Text("No pulls yet")
                .font(PlayType.rounded(16, .bold))
                .foregroundStyle(Paper.ink)
            Spacer(minLength: 0)
        }
        .help("Every time Shift catches a pull, it lands here: when, what for, and what you wrote about it.")
        .padding(PlayRhythm.card)
        .paperCard(radius: 20)
    }

    // MARK: Working it out

    private var days: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.startedAt) }
        return grouped.keys.sorted(by: >).map { DayGroup(day: $0, entries: grouped[$0] ?? []) }
    }

    private func pauses(inLast days: Int, now: Date) -> [ReachEntry] {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) else { return [] }
        return entries.filter { $0.startedAt >= start }
    }

    /// Pauses per day, oldest first, ending today.
    private func dailyCounts(now: Date) -> [DayCount] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let counts = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.startedAt) }.mapValues(\.count)
        return (0..<Self.trendDays).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayCount(day: day, count: counts[day] ?? 0)
        }
    }

    private func mostCommonFeeling(in entries: [ReachEntry]) -> UrgeReason? {
        let counts = Dictionary(grouping: entries.compactMap(\.feeling), by: { $0 }).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key
    }

    private func mostCommonTarget(in entries: [ReachEntry]) -> String? {
        let counts = Dictionary(grouping: entries.map(\.target), by: { $0 }).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key
    }

    private func peakHour(in entries: [ReachEntry]) -> Int? {
        guard entries.count >= 3 else { return nil }
        let calendar = Calendar.current
        let counts = Dictionary(grouping: entries, by: { calendar.component(.hour, from: $0.startedAt) }).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(.dateTime.hour())
    }
}

private struct DayGroup: Identifiable {
    let day: Date
    let entries: [ReachEntry]
    var id: Date { day }
}

private struct DayCount: Identifiable {
    let day: Date
    let count: Int
    var id: Date { day }
}

// MARK: - The trend

/// Two weeks of pauses as bars, today on the right in full coral. Fewer, shorter bars over
/// the weeks is what the habit breaking looks like.
private struct TrendCard: View {
    let counts: [DayCount]
    let now: Date

    private let plotHeight: CGFloat = 96

    var body: some View {
        let peak = max(counts.map(\.count).max() ?? 0, 1)
        VStack(alignment: .leading, spacing: PlayRhythm.inner) {
            SmallCaps(text: "Pulls, last two weeks")

            HStack(alignment: .bottom, spacing: PlayRhythm.tile) {
                ForEach(counts) { item in
                    column(day: item.day, count: item.count, peak: peak)
                }
            }
        }
        .padding(PlayRhythm.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(radius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func column(day: Date, count: Int, peak: Int) -> some View {
        let isToday = Calendar.current.isDate(day, inSameDayAs: now)
        let height = count == 0 ? 4 : max(8, plotHeight * CGFloat(count) / CGFloat(peak))
        return VStack(spacing: 6) {
            Text(count == 0 ? " " : "\(count)")
                .font(PlayType.rounded(10, .bold))
                .monospacedDigit()
                .foregroundStyle(isToday ? Paper.coralText : .secondary)

            RoundedRectangle(cornerRadius: count == 0 ? 2 : 6, style: .continuous)
                .fill(count == 0 ? Paper.tile : (isToday ? Paper.coral : Paper.coral.opacity(0.4)))
                .frame(height: height)
                .frame(maxHeight: plotHeight, alignment: .bottom)

            Text(isToday ? "Today" : day.formatted(.dateTime.weekday(.narrow)))
                .font(PlayType.rounded(10, isToday ? .bold : .semibold))
                .foregroundStyle(isToday ? Paper.coralText : .secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .help("\(day.formatted(.dateTime.weekday(.wide).day().month(.wide))): \(count == 1 ? "1 pull" : "\(count) pulls")")
    }

    private var accessibilitySummary: String {
        let total = counts.map(\.count).reduce(0, +)
        let today = counts.last?.count ?? 0
        return "\(total) pulls in the last two weeks, \(today) today."
    }
}

// MARK: - A day

/// One day at a glance: only where the pulls went and why (26 Nov 2026, the user's call).
/// No counts anywhere on the card, not even on the pills, and no hour strip: how many
/// pulls and how many turned back read as a score. Most frequent comes first. Every pull,
/// with its time and the words written about it, stays in the journal database for later
/// analysis. A list of every pull was replaced the same day: it read like a log file.
private struct DayCard: View {
    let day: Date
    let entries: [ReachEntry]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: PlayRhythm.inner) {
            Text(title)
                .font(PlayType.rounded(16, .bold))
                .foregroundStyle(Paper.ink)
                .accessibilityAddTraits(.isHeader)

            SummaryLine(label: "Where", items: sites.map { Tally(text: $0, symbol: nil) })
            if !feelings.isEmpty {
                SummaryLine(label: "Why", items: feelings.map { Tally(text: $0.shortLabel, symbol: $0.symbol) })
            }
        }
        .padding(PlayRhythm.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(radius: 20)
    }

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    /// Each site or app once, most pulled first.
    private var sites: [String] {
        var counts: [String: Int] = [:]
        for entry in entries {
            let name: String = entry.rule.isEmpty ? entry.target : entry.rule
            counts[name, default: 0] += 1
        }
        let names: [String] = Array(counts.keys)
        return names.sorted { (a: String, b: String) -> Bool in
            let countA = counts[a] ?? 0
            let countB = counts[b] ?? 0
            return countA != countB ? countA > countB : a < b
        }
    }

    /// Each feeling named once, most often first.
    private var feelings: [UrgeReason] {
        var counts: [UrgeReason: Int] = [:]
        for entry in entries {
            if let feeling = entry.feeling { counts[feeling, default: 0] += 1 }
        }
        let order: [UrgeReason] = UrgeReason.allCases
        let named: [UrgeReason] = order.filter { counts[$0] != nil }
        return named.sorted { (a: UrgeReason, b: UrgeReason) -> Bool in
            let countA = counts[a] ?? 0
            let countB = counts[b] ?? 0
            if countA != countB { return countA > countB }
            return (order.firstIndex(of: a) ?? 0) < (order.firstIndex(of: b) ?? 0)
        }
    }
}

private struct Tally: Hashable {
    let text: String
    let symbol: String?
}

/// A small-caps label and a row of pills, each a name. Wraps onto a second row
/// rather than squeezing.
private struct SummaryLine: View {
    let label: String
    let items: [Tally]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PlayRhythm.inner) {
            SmallCaps(text: label)
                .frame(width: 44, alignment: .leading)
            WrappingRow(spacing: PlayRhythm.tile) {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 5) {
                        if let symbol = item.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Paper.ink.opacity(0.7))
                        }
                        Text(item.text)
                            .font(PlayType.rounded(12, .semibold))
                            .foregroundStyle(Paper.ink.opacity(0.85))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(Paper.tile))
                }
            }
        }
    }
}

/// Lays pills out left to right and wraps onto new rows. Shared by the Journal and the
/// Dashboard.
struct WrappingRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

private extension ReachEntry {
    /// Closed at the pause, or before it during the heads-up.
    var turnedBack: Bool { outcome == .closed || outcome == .leftEarly }
}
