import AppKit
import SwiftUI

/// A block's schedule as a week you paint on.
///
/// Seven day columns of half-hour cells, midnight at the top.
/// - Drag across empty days and hours to add that stretch.
/// - Click a coral stretch to select it; Delete (the button or the key) removes it.
/// - Drag a stretch to move it, to other hours or another day; drag its top or bottom edge
///   to make it start or end at another time.
///
/// Quick picks add weekends or the whole week, and Clear empties it. Underneath, one plain
/// line per time window says what was chosen. No instructions on screen (26 Nov 2026, the
/// user's call): the pointer changes over a stretch and its edges, and that's the hint.
///
/// Replaced the row of day letters and two time pills per window on 26 Nov 2026 at the
/// user's request, and lives in a sheet (`ScheduleSheet`) rather than inside the editor. A
/// Draw / Erase switch came and went the same day: selecting and deleting replaced erasing.
/// The schedule is still saved as `ScheduleWindow`s: runs that share the same hours become
/// one window across those days, and a run to midnight that carries on from midnight the next
/// day is saved as one overnight window. Times snap to the half hour.
struct WeekCalendar: View {
    @Binding var windows: [ScheduleWindow]
    /// Points per half hour. 6 is the smallest that still drags comfortably.
    var rowHeight: CGFloat = 9

    @Environment(\.isEnabled) private var isEnabled
    @State private var gridWidth: CGFloat = 0
    @State private var action: Action?
    @State private var hover: Hit?
    /// The stretch clicked last, ready to delete.
    @State private var selected: Run?

    /// One half hour on one day. `day` is the column, in the order this Mac shows the week.
    struct Cell: Hashable {
        var day: Int
        var slot: Int
    }

    /// One unbroken coral stretch in one column. `end` is exclusive.
    struct Run: Hashable {
        var day: Int
        var start: Int
        var end: Int

        var cells: Set<Cell> { Set((start..<end).map { Cell(day: day, slot: $0) }) }
    }

    enum Edge { case top, bottom }

    /// What the pointer is over.
    private enum Hit: Equatable {
        case empty(Cell)
        case body(Run)
        case edge(Run, Edge)
    }

    /// The drag in progress.
    private enum Action {
        /// A rectangle that adds.
        case paint(anchor: Cell, current: Cell)
        /// An existing stretch picked up and carried.
        case move(Run, days: Int, slots: Int)
        /// An existing stretch with one end pulled.
        case resize(Run, Edge, slots: Int)
    }

    static let slotMinutes = 30
    static let slots = 24 * 60 / slotMinutes
    static let hourColumn: CGFloat = 40
    static let columnGap: CGFloat = 5
    /// Less movement than this between press and release is a click, not a drag.
    private static let clickTolerance: CGFloat = 3

    private var gridHeight: CGFloat { CGFloat(Self.slots) * rowHeight }

    /// The week in the order this Mac shows it, starting on the locale's first weekday.
    static var week: [Weekday] {
        let first = Calendar.current.firstWeekday
        return (0..<7).compactMap { Weekday(rawValue: (first - 1 + $0) % 7 + 1) }
    }

    private var week: [Weekday] { Self.week }

    /// What's saved, as cells.
    private var saved: Set<Cell> { Self.cells(from: windows, week: week) }

    /// What to draw: the saved cells with the drag in progress applied.
    private var shown: Set<Cell> {
        guard let action else { return saved }
        return Self.apply(action, to: saved)
    }

    /// The selection, only while that exact stretch still exists.
    private var currentSelection: Run? {
        guard let selected else { return nil }
        let cells = saved
        guard selected.cells.isSubset(of: cells),
              selected.start == 0 || !cells.contains(Cell(day: selected.day, slot: selected.start - 1)),
              selected.end == Self.slots || !cells.contains(Cell(day: selected.day, slot: selected.end))
        else { return nil }
        return selected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 6) {
                WeekPick(title: "Weekends", symbol: "sun.max") {
                    add(days: [.saturday, .sunday], from: 0, to: 24 * 60)
                }
                WeekPick(title: "All week", symbol: "square.grid.3x3.fill") {
                    add(days: Set(Weekday.allCases), from: 0, to: 24 * 60)
                }
                WeekPick(title: "Clear", symbol: "xmark", isQuiet: true) {
                    windows = []
                    selected = nil
                }
                Spacer(minLength: 8)
                if let run = currentSelection {
                    Button {
                        delete(run)
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(PlayType.rounded(12, .semibold))
                            .foregroundStyle(Paper.onCoralSolid)
                            .padding(.horizontal, 11)
                            .frame(height: 26)
                            .background(Capsule(style: .continuous).fill(Paper.coralSolid))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(SquishButtonStyle())
                    .keyboardShortcut(.delete, modifiers: [])
                    .help("Delete \(describe(run))")
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: currentSelection)

            VStack(spacing: 6) {
                dayHeader
                HStack(alignment: .top, spacing: 0) {
                    hourLabels
                    grid
                }
            }
            summary
        }
    }

    private func add(days: Set<Weekday>, from start: Int, to end: Int) {
        var cells = saved
        for (index, day) in week.enumerated() where days.contains(day) {
            for slot in (start / Self.slotMinutes)..<(end / Self.slotMinutes) {
                cells.insert(Cell(day: index, slot: slot))
            }
        }
        windows = Self.windows(from: cells, week: week)
        selected = nil
    }

    private func delete(_ run: Run) {
        windows = Self.windows(from: saved.subtracting(run.cells), week: week)
        selected = nil
    }

    // MARK: The grid

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.hourColumn, height: 1)
            ForEach(Array(week.enumerated()), id: \.offset) { index, day in
                Text(day.shortTitle)
                    .font(PlayType.rounded(12, .bold))
                    .foregroundStyle(isHighlighted(index) ? AnyShapeStyle(Paper.coralText) : AnyShapeStyle(.secondary))
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func isHighlighted(_ day: Int) -> Bool {
        if let action { return Self.outline(of: action).days.contains(day) }
        switch hover {
        case .empty(let cell)?: return cell.day == day
        case .body(let run)?, .edge(let run, _)?: return run.day == day
        case nil: return currentSelection?.day == day
        }
    }

    /// Every three hours, beside the line they label.
    private var hourLabels: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(Array(stride(from: 0, through: 24, by: 3)), id: \.self) { hour in
                Text(Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(hour) * 3600).formatted(.dateTime.hour()))
                    .font(PlayType.rounded(10, .semibold))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .offset(y: CGFloat(hour * 60 / Self.slotMinutes) * rowHeight - 6)
            }
        }
        .padding(.trailing, 8)
        .frame(width: Self.hourColumn, height: gridHeight, alignment: .topTrailing)
        .accessibilityHidden(true)
    }

    private var grid: some View {
        let cells = self.shown
        let rowHeight = self.rowHeight
        let outline = action.map { Self.outline(of: $0) }
        let selection = action == nil ? currentSelection : nil
        let hoveredRun: Run? = {
            guard action == nil, let hover else { return nil }
            switch hover {
            case .body(let run), .edge(let run, _): return run
            case .empty: return nil
            }
        }()
        let hoveredCell: Cell? = {
            guard action == nil, case .empty(let cell)? = hover else { return nil }
            return cell
        }()
        return Canvas { context, size in
            Self.draw(
                in: &context,
                size: size,
                rowHeight: rowHeight,
                shown: cells,
                outline: outline,
                selected: selection,
                hoveredRun: hoveredRun,
                hoveredCell: hoveredCell
            )
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: gridHeight, maxHeight: gridHeight)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged(dragChanged)
                .onEnded(dragEnded),
            including: isEnabled ? .all : .none
        )
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                hover = isEnabled ? hit(at: point) : nil
                if action == nil { cursor(for: hover).set() }
            case .ended:
                hover = nil
                if action == nil { NSCursor.arrow.set() }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Weekly schedule")
        .accessibilityValue(summaryLines.joined(separator: ", "))
    }

    private var columnWidth: CGFloat { max(1, gridWidth / 7) }

    private func cell(at point: CGPoint) -> Cell {
        Cell(
            day: min(6, max(0, Int(point.x / columnWidth))),
            slot: min(Self.slots - 1, max(0, Int(point.y / rowHeight)))
        )
    }

    /// The unbroken stretch in a column that covers a cell.
    private func run(containing cell: Cell, in cells: Set<Cell>) -> Run {
        var start = cell.slot, end = cell.slot + 1
        while start > 0 && cells.contains(Cell(day: cell.day, slot: start - 1)) { start -= 1 }
        while end < Self.slots && cells.contains(Cell(day: cell.day, slot: end)) { end += 1 }
        return Run(day: cell.day, start: start, end: end)
    }

    /// An empty cell, a stretch's body, or within a few points of its top or bottom edge.
    private func hit(at point: CGPoint) -> Hit {
        let cell = cell(at: point)
        let cells = saved
        guard cells.contains(cell) else { return .empty(cell) }
        let run = run(containing: cell, in: cells)
        let top = CGFloat(run.start) * rowHeight, bottom = CGFloat(run.end) * rowHeight
        let grip = min(6, (bottom - top) / 3)
        if point.y - top <= grip { return .edge(run, .top) }
        if bottom - point.y <= grip { return .edge(run, .bottom) }
        return .body(run)
    }

    private func cursor(for hit: Hit?) -> NSCursor {
        switch hit {
        case .empty?: return .crosshair
        case .body?: return .openHand
        case .edge?: return .rowResize
        case nil: return .arrow
        }
    }

    private func dragChanged(_ value: DragGesture.Value) {
        let slots = Int(((value.location.y - value.startLocation.y) / rowHeight).rounded())
        let days = Int(((value.location.x - value.startLocation.x) / columnWidth).rounded())

        guard let action else {
            switch hit(at: value.startLocation) {
            case .empty(let anchor):
                self.action = .paint(anchor: anchor, current: cell(at: value.location))
            case .body(let run):
                self.action = .move(run, days: days, slots: slots)
                NSCursor.closedHand.set()
            case .edge(let run, let edge):
                self.action = .resize(run, edge, slots: slots)
            }
            return
        }

        switch action {
        case .paint(let anchor, _):
            self.action = .paint(anchor: anchor, current: cell(at: value.location))
        case .move(let run, _, _):
            self.action = .move(run, days: days, slots: slots)
        case .resize(let run, let edge, _):
            self.action = .resize(run, edge, slots: slots)
        }
    }

    /// A click selects the stretch under it (or nothing, on empty space); a drag commits.
    private func dragEnded(_ value: DragGesture.Value) {
        defer {
            action = nil
            cursor(for: hover).set()
        }
        let distance = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
        guard distance >= Self.clickTolerance else {
            switch hit(at: value.startLocation) {
            case .body(let run), .edge(let run, _): selected = selected == run ? nil : run
            case .empty: selected = nil
            }
            return
        }
        guard let action else { return }
        windows = Self.windows(from: Self.apply(action, to: saved), week: week)
        switch action {
        case .paint: selected = nil
        case .move(let run, let days, let slots): selected = Self.moved(run, days: days, slots: slots)
        case .resize(let run, let edge, let slots): selected = Self.resized(run, edge, slots: slots)
        }
    }

    // MARK: Applying a drag

    private static func apply(_ action: Action, to cells: Set<Cell>) -> Set<Cell> {
        switch action {
        case .paint(let anchor, let current):
            return cells.union(rectangle(anchor, current))
        case .move(let run, let days, let slots):
            return cells.subtracting(run.cells).union(moved(run, days: days, slots: slots).cells)
        case .resize(let run, let edge, let slots):
            return cells.subtracting(run.cells).union(resized(run, edge, slots: slots).cells)
        }
    }

    private static func rectangle(_ a: Cell, _ b: Cell) -> Set<Cell> {
        var cells = Set<Cell>()
        for day in min(a.day, b.day)...max(a.day, b.day) {
            for slot in min(a.slot, b.slot)...max(a.slot, b.slot) { cells.insert(Cell(day: day, slot: slot)) }
        }
        return cells
    }

    /// Carried by whole days and half hours, kept inside the week and the day.
    private static func moved(_ run: Run, days: Int, slots: Int) -> Run {
        let shift = min(Self.slots - run.end, max(-run.start, slots))
        return Run(day: min(6, max(0, run.day + days)), start: run.start + shift, end: run.end + shift)
    }

    /// One end pulled, never past the other end.
    private static func resized(_ run: Run, _ edge: Edge, slots: Int) -> Run {
        switch edge {
        case .top: Run(day: run.day, start: min(run.end - 1, max(0, run.start + slots)), end: run.end)
        case .bottom: Run(day: run.day, start: run.start, end: max(run.start + 1, min(Self.slots, run.end + slots)))
        }
    }

    /// Where the drag is landing: the rectangle, or the stretch being carried or pulled.
    private static func outline(of action: Action) -> (days: ClosedRange<Int>, slots: Range<Int>) {
        switch action {
        case .paint(let anchor, let current):
            return (min(anchor.day, current.day)...max(anchor.day, current.day),
                    min(anchor.slot, current.slot)..<(max(anchor.slot, current.slot) + 1))
        case .move(let run, let days, let slots):
            let run = moved(run, days: days, slots: slots)
            return (run.day...run.day, run.start..<run.end)
        case .resize(let run, let edge, let slots):
            let run = resized(run, edge, slots: slots)
            return (run.day...run.day, run.start..<run.end)
        }
    }

    // MARK: Drawing

    /// Columns as soft tiles, faint lines every three hours, each stretch as one coral bar
    /// with its start time, a ring around the selected one, grips on the selected or hovered
    /// one, and the drag outlined.
    private static func draw(
        in context: inout GraphicsContext,
        size: CGSize,
        rowHeight: CGFloat,
        shown: Set<Cell>,
        outline: (days: ClosedRange<Int>, slots: Range<Int>)?,
        selected: Run?,
        hoveredRun: Run?,
        hoveredCell: Cell?
    ) {
        let column = size.width / 7
        func lane(_ day: Int) -> (x: CGFloat, width: CGFloat) {
            (CGFloat(day) * column + columnGap / 2, column - columnGap)
        }

        for day in 0..<7 {
            let (x, width) = lane(day)
            let rect = CGRect(x: x, y: 0, width: width, height: size.height)
            context.fill(Path(roundedRect: rect, cornerRadius: 8, style: .continuous), with: .color(Paper.tile))
            for hour in stride(from: 3, to: 24, by: 3) {
                let y = CGFloat(hour * 60 / slotMinutes) * rowHeight
                context.fill(Path(CGRect(x: x + 4, y: y - 0.5, width: width - 8, height: 1)), with: .color(Paper.hairline))
            }

            var slot = 0
            while slot < slots {
                guard shown.contains(Cell(day: day, slot: slot)) else {
                    slot += 1
                    continue
                }
                var end = slot
                while end < slots && shown.contains(Cell(day: day, slot: end)) { end += 1 }
                let run = Run(day: day, start: slot, end: end)
                let bar = CGRect(x: x + 2, y: CGFloat(slot) * rowHeight + 1, width: width - 4, height: CGFloat(end - slot) * rowHeight - 2)
                let shape = Path(roundedRect: bar, cornerRadius: 6, style: .continuous)
                context.fill(shape, with: .color(Paper.coralSolid))
                if run == selected {
                    let ring = Path(roundedRect: bar.insetBy(dx: -2, dy: -2), cornerRadius: 8, style: .continuous)
                    context.stroke(ring, with: .color(Paper.ink.opacity(0.85)), lineWidth: 2)
                }
                if bar.height >= 26 {
                    let label = Text(timeLabel(slot: slot))
                        .font(PlayType.rounded(9.5, .bold))
                        .foregroundStyle(Paper.onCoralSolid)
                    context.draw(label, at: CGPoint(x: bar.midX, y: bar.minY + 10), anchor: .center)
                }
                if run == selected || run == hoveredRun, bar.height >= 18 {
                    // Grips on both ends, so it's clear they can be pulled.
                    for y in [bar.minY + 3.5, bar.maxY - 3.5] {
                        let grip = CGRect(x: bar.midX - 8, y: y - 1.25, width: 16, height: 2.5)
                        context.fill(Path(roundedRect: grip, cornerRadius: 1.25), with: .color(Paper.onCoralSolid.opacity(0.85)))
                    }
                }
                slot = end
            }
        }

        if let outline {
            let first = lane(outline.days.lowerBound)
            let rect = CGRect(
                x: first.x,
                y: CGFloat(outline.slots.lowerBound) * rowHeight,
                width: CGFloat(outline.days.count) * column - columnGap,
                height: CGFloat(outline.slots.count) * rowHeight
            )
            context.stroke(
                Path(roundedRect: rect, cornerRadius: 7, style: .continuous),
                with: .color(Paper.ink.opacity(0.75)),
                lineWidth: 1.5
            )
        } else if let hoveredCell {
            let (x, width) = lane(hoveredCell.day)
            let rect = CGRect(x: x + 2, y: CGFloat(hoveredCell.slot) * rowHeight, width: width - 4, height: rowHeight)
            context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Paper.coralSolid.opacity(0.3)))
        }
    }

    private static func timeLabel(slot: Int) -> String {
        Calendar.current.startOfDay(for: .now)
            .addingTimeInterval(Double(slot * slotMinutes) * 60)
            .formatted(date: .omitted, time: .shortened)
    }

    // MARK: What it says

    /// One plain line per window, nothing else.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(summaryLines.prefix(3), id: \.self) { text in
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Paper.coralText)
                        .frame(width: 12)
                    Text(text)
                        .font(PlayType.rounded(12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if summaryLines.count > 3 {
                Text("and \(summaryLines.count - 3) more")
                    .font(PlayType.rounded(12, .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 18)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
    }

    private var summaryLines: [String] { windows.map(\.summary) }

    /// "Mon, 9:00 AM to 5:00 PM", for the Delete button's tooltip.
    private func describe(_ run: Run) -> String {
        let end = run.end >= Self.slots ? "midnight" : Self.timeLabel(slot: run.end)
        return "\(week[run.day].shortTitle), \(Self.timeLabel(slot: run.start)) to \(end)"
    }

    // MARK: Windows and cells

    /// The cells a schedule covers. An overnight window paints its evening on its own day
    /// and its small hours on the next.
    static func cells(from windows: [ScheduleWindow], week: [Weekday]) -> Set<Cell> {
        var cells = Set<Cell>()
        func paint(_ day: Weekday, from start: Int, to end: Int) {
            guard let column = week.firstIndex(of: day), end > start else { return }
            let first = start / slotMinutes
            let last = min(slots, (end + slotMinutes - 1) / slotMinutes)
            for slot in first..<max(first, last) { cells.insert(Cell(day: column, slot: slot)) }
        }
        for window in windows {
            let start = window.start.minutes, end = window.end.minutes
            for day in window.days {
                if start < end {
                    paint(day, from: start, to: end)
                } else if start > end {
                    paint(day, from: start, to: 24 * 60)
                    if let next = Weekday(rawValue: day.rawValue % 7 + 1) { paint(next, from: 0, to: end) }
                }
            }
        }
        return cells
    }

    /// The fewest windows that cover the cells: runs with the same hours share one window,
    /// and an evening run that carries on past midnight on each following day becomes one
    /// overnight window.
    static func windows(from cells: Set<Cell>, week: [Weekday]) -> [ScheduleWindow] {
        struct Hours: Hashable { var start: Int; var end: Int }
        var groups: [Hours: Set<Weekday>] = [:]
        for (column, day) in week.enumerated() {
            var slot = 0
            while slot < slots {
                guard cells.contains(Cell(day: column, slot: slot)) else {
                    slot += 1
                    continue
                }
                var end = slot
                while end < slots && cells.contains(Cell(day: column, slot: end)) { end += 1 }
                groups[Hours(start: slot * slotMinutes, end: end * slotMinutes), default: []].insert(day)
                slot = end
            }
        }

        var windows: [ScheduleWindow] = []
        // Join evenings to the mornings after them, when every evening day has one.
        for evening in groups.keys.filter({ $0.end == 24 * 60 && $0.start > 0 }).sorted(by: { $0.start < $1.start }) {
            guard let days = groups[evening] else { continue }
            let following = Set(days.compactMap { Weekday(rawValue: $0.rawValue % 7 + 1) })
            guard let morning = groups.keys.first(where: { $0.start == 0 && $0.end < 24 * 60 && groups[$0] == following }) else { continue }
            windows.append(ScheduleWindow(days: days, start: TimeOfDay(minutes: evening.start), end: TimeOfDay(minutes: morning.end)))
            groups[evening] = nil
            groups[morning] = nil
        }
        for (hours, days) in groups {
            windows.append(ScheduleWindow(days: days, start: TimeOfDay(minutes: hours.start), end: TimeOfDay(minutes: hours.end)))
        }
        return windows.sorted {
            $0.start.minutes != $1.start.minutes ? $0.start.minutes < $1.start.minutes : $0.end.minutes < $1.end.minutes
        }
    }
}

// MARK: - The sheet

/// The schedule, edited in a sheet of its own so the calendar has room. Cancel leaves the
/// block as it was; Done hands back the new windows.
struct ScheduleSheet: View {
    let initial: [ScheduleWindow]
    let onCancel: () -> Void
    let onDone: ([ScheduleWindow]) -> Void

    @State private var windows: [ScheduleWindow] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ON A SCHEDULE")
                    .font(PlayType.rounded(11, .bold))
                    .tracking(0.9)
                    .foregroundStyle(Paper.coralText)
                Text("When should it be on?")
                    .font(PlayType.rounded(24, .bold))
                    .foregroundStyle(Paper.ink)
            }

            // 7 pt a half hour keeps the sheet inside the main window's smallest height.
            WeekCalendar(windows: $windows, rowHeight: 7)

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                Button {
                    onDone(windows)
                } label: {
                    Text("Done")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Paper.coral)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 660)
        .background(Paper.background.ignoresSafeArea())
        .onAppear {
            guard !loaded else { return }
            windows = initial
            loaded = true
        }
    }
}

// MARK: - Pieces

/// A small pill that adds a common shape to the week.
private struct WeekPick: View {
    let title: String
    let symbol: String
    var isQuiet = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(PlayType.rounded(12, .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isQuiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(Paper.coralText))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                Capsule(style: .continuous)
                    .fill(isHovering ? Paper.coralSoft : Paper.tile)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(SquishButtonStyle())
        .onHover { isHovering = $0 }
    }
}
