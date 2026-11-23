import SwiftUI

/// The last seven days of reaching for blocked sites, and the plans for next time.
///
/// The pattern is the point. Most reaches cluster around one feeling at one time of day,
/// and once you can see that, you can decide in advance what to do instead. Those
/// decisions are if-then plans ("When the work gets hard, I'll write the next tiny step"),
/// one of the best-supported tools in behaviour change, and the pause shows them back to
/// you in your own words at exactly the moment they apply.
struct WeekPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let week = model.urges.week()
        Panel("Your week", subtitle: subtitle(week), icon: "chart.bar") {
            if week.total == 0 {
                Text("Nothing yet. Each time you reach for a blocked site, Shift notes what you were after, so you can see your pattern here and plan for it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.base) {
                    if !week.byReason.isEmpty {
                        bars(week)
                    }
                    if let insight = insight(week) {
                        Text(insight)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    plans(week)
                }
            }
        }
    }

    private func subtitle(_ week: UrgeWeek) -> String? {
        guard week.total > 0 else { return nil }
        let reaches = "You reached for a blocked site \(week.total) time\(week.total == 1 ? "" : "s")"
        guard week.turnedBack > 0 else { return reaches + "." }
        let share = Double(week.turnedBack) / Double(week.total)
        let tail = share >= 0.5 ? " That’s a habit changing." : ""
        return reaches + " and turned back \(week.turnedBack) of them." + tail
    }

    private func bars(_ week: UrgeWeek) -> some View {
        let most = week.byReason.first?.1 ?? 1
        return VStack(spacing: Theme.Space.tight) {
            ForEach(week.byReason, id: \.0) { reason, count in
                HStack(spacing: Theme.Space.snug) {
                    Label(reason.shortLabel, systemImage: reason.symbol)
                        .font(.caption)
                        .frame(width: 104, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary.opacity(0.6))
                            Capsule()
                                .fill(.primary.opacity(0.55))
                                .frame(width: max(6, geometry.size.width * CGFloat(count) / CGFloat(most)))
                        }
                    }
                    .frame(height: 8)
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(reason.shortLabel): \(count)")
            }
        }
    }

    private func insight(_ week: UrgeWeek) -> String? {
        var parts: [String] = []
        if let top = week.topReason {
            let feeling = switch top {
            case .bored: "bored"
            case .tired: "drained"
            case .stuck: "stuck on something hard"
            case .anxious: "anxious"
            case .lonely: "feeling alone"
            case .needed: "after something specific"
            }
            parts.append("Most often, you were \(feeling)")
        }
        if let hour = week.peakHour {
            let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
            let time = date.formatted(.dateTime.hour())
            parts.append(parts.isEmpty ? "Most reaches came around \(time)" : "usually around \(time)")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ") + ". That’s the moment to plan for."
    }

    /// One plan per craving that showed up this week, plus any written before.
    private func plans(_ week: UrgeWeek) -> some View {
        let seen = week.byReason.map(\.0)
        let reasons = UrgeReason.allCases.filter { seen.contains($0) || model.urges.plan(for: $0) != nil }

        return VStack(alignment: .leading, spacing: Theme.Space.snug) {
            Text("Plan for next time")
                .font(.callout.weight(.semibold))
            Text("Decide now, while it’s easy. Shift will show you your plan in the pause.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(reasons) { reason in
                HStack(spacing: Theme.Space.snug) {
                    Text(reason.planLead)
                        .font(.callout)
                        .frame(width: 210, alignment: .leading)
                    ShiftTextField(prompt: reason.planExample, text: Binding(
                        get: { model.urges.plans[reason] ?? "" },
                        set: { model.urges.setPlan($0, for: reason) }
                    ))
                }
            }
        }
        .padding(.top, Theme.Space.tight)
    }
}
