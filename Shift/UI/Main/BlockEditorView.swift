import AppKit
import SwiftUI

/// Edits one block, in the trailing inspector.
///
/// Changes are applied as you make them rather than behind a Save button, which is what
/// the rest of macOS does for settings-shaped editing. The store refuses anything that
/// would weaken a locked block, so the inspector shows which parts are frozen instead of
/// letting an edit fail silently.
struct BlockInspector: View {
    @Environment(AppModel.self) private var model

    @State private var draft: Block
    @State private var newSite = ""
    @State private var newException = ""
    @State private var isShowingAppPicker = false

    private let onClose: () -> Void

    init(block: Block, onClose: @escaping () -> Void) {
        _draft = State(initialValue: block)
        self.onClose = onClose
    }

    private var isLocked: Bool { draft.lock.isLocked() }
    private var tint: Color { draft.tint.color }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                identity
                if isLocked { lockedBanner }
                sites
                apps
                exceptions
                schedule
                breaks
                lock
                friction
                deleteButton
            }
            .padding(Theme.Space.base)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background {
            VisualEffect(surface: .sidebar, blending: .behindWindow).ignoresSafeArea()
        }
        .onChange(of: draft) { _, updated in
            // Runtime fields are untouched here, so a refused edit just reverts the draft.
            if !model.store.update(updated), let current = model.store.block(id: updated.id) {
                draft = current
            }
        }
        .sheet(isPresented: $isShowingAppPicker) {
            AppPickerView(selected: $draft.list.apps, tint: tint)
        }
    }

    // MARK: Identity

    private var identity: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            HStack(spacing: Theme.Space.snug) {
                BlockBadge(symbol: draft.symbol, tint: draft.tint, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Block name", text: $draft.name)
                        .textFieldStyle(.plain)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text(draft.contentsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close inspector")
            }

            HStack(spacing: 6) {
                ForEach(BlockTint.allCases) { option in
                    Button {
                        draft.tint = option
                    } label: {
                        Circle()
                            .fill(option.color.gradient)
                            .frame(width: 20, height: 20)
                            .overlay {
                                if draft.tint == option {
                                    Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.symbols, id: \.self) { symbol in
                        Button {
                            draft.symbol = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 14))
                                .frame(width: 30, height: 30)
                                .background {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(draft.symbol == symbol ? AnyShapeStyle(tint.opacity(0.25)) : AnyShapeStyle(Color.primary.opacity(0.05)))
                                }
                                .foregroundStyle(draft.symbol == symbol ? tint : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .glassSurface(padding: Theme.Space.base, tint: tint)
    }

    private var lockedBanner: some View {
        HStack(alignment: .top, spacing: Theme.Space.tight) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.lock.statusText())
                    .font(.caption.weight(.semibold))
                Text("You can add to this block, but not weaken it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(Theme.Space.snug)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        }
    }

    // MARK: Lists

    private var sites: some View {
        Panel("Websites", icon: "globe") {
            HStack(spacing: Theme.Space.tight) {
                ShiftTextField(
                    prompt: "instagram.com or youtube.com/shorts",
                    text: $newSite,
                    symbol: "plus",
                    onSubmit: addSite
                )
                Button("Add", action: addSite)
                    .buttonStyle(.shiftSoft)
                    .disabled(newSite.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if draft.list.siteCount == 0 {
                EmptyHint(text: "No sites yet. A slash blocks part of a site, so the rest keeps working.")
            } else {
                ChipFlow(
                    items: draft.list.hosts + draft.list.paths,
                    symbol: "globe",
                    canRemove: !isLocked
                ) { entry in
                    draft.list.hosts.removeAll { $0 == entry }
                    draft.list.paths.removeAll { $0 == entry }
                }
            }
        }
    }

    private var apps: some View {
        Panel("Apps", icon: "app.badge") {
            Button {
                isShowingAppPicker = true
            } label: {
                Label("Choose apps", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.shiftSoft)

            if draft.list.apps.isEmpty {
                EmptyHint(text: "No apps yet. Blocked apps are quit when they come up.")
            } else {
                ChipFlow(
                    items: draft.list.apps,
                    symbol: "app.badge",
                    canRemove: !isLocked,
                    label: { InstalledApps.shared.name(for: $0) ?? $0 },
                    image: { InstalledApps.shared.icon(for: $0) }
                ) { entry in
                    draft.list.apps.removeAll { $0 == entry }
                }
            }
        }
    }

    private var exceptions: some View {
        Panel("Always allow", subtitle: "Exceptions win over everything else in this block.", icon: "checkmark.shield") {
            HStack(spacing: Theme.Space.tight) {
                ShiftTextField(
                    prompt: "docs.google.com",
                    text: $newException,
                    symbol: "plus",
                    onSubmit: addException
                )
                Button("Add", action: addException)
                    .buttonStyle(.shiftSoft)
                    .disabled(newException.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !draft.list.exceptions.isEmpty {
                ChipFlow(items: draft.list.exceptions, symbol: "checkmark", canRemove: true) { entry in
                    draft.list.exceptions.removeAll { $0 == entry }
                }
            }
        }
    }

    // MARK: Schedule

    private var schedule: some View {
        Panel("When it applies", icon: "calendar") {
            SegmentedSelector(
                selection: scheduleKind,
                options: [
                    .init(.always, "Always", symbol: "infinity"),
                    .init(.scheduled, "Schedule", symbol: "calendar"),
                    .init(.manual, "On demand", symbol: "play.fill"),
                ],
                tint: tint
            )
            .disabled(isLocked)

            switch draft.schedule {
            case .always:
                EmptyHint(text: "Active whenever the block is switched on.")

            case .scheduled(let windows):
                VStack(spacing: Theme.Space.snug) {
                    ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                        WindowEditor(
                            window: binding(for: index),
                            tint: tint,
                            canDelete: windows.count > 1,
                            onDelete: { removeWindow(at: index) }
                        )
                    }
                    Button {
                        guard case .scheduled(var all) = draft.schedule else { return }
                        all.append(ScheduleWindow())
                        draft.schedule = .scheduled(all)
                    } label: {
                        Label("Add a time window", systemImage: "plus")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.shiftSoft)
                }
                .disabled(isLocked)

            case .manual(let minutes):
                VStack(alignment: .leading, spacing: Theme.Space.tight) {
                    Text("How long each run lasts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SegmentedSelector(
                        selection: Binding(
                            get: { minutes ?? 0 },
                            set: { draft.schedule = .manual(minutes: $0 == 0 ? nil : $0) }
                        ),
                        options: [
                            .init(0, "Open"),
                            .init(25, "25m"),
                            .init(50, "50m"),
                            .init(90, "90m"),
                        ],
                        tint: tint
                    )
                }
                .disabled(isLocked)
            }
        }
    }

    // MARK: Breaks, lock, friction

    private var breaks: some View {
        Panel("Breaks", subtitle: "Decided now, not in the moment of weakness.", icon: "cup.and.saucer") {
            PanelRow(title: "Allow breaks") {
                ShiftSwitch(isOn: $draft.breaks.isEnabled, tint: tint)
                    .disabled(isLocked)
            }

            if draft.breaks.isEnabled {
                VStack(alignment: .leading, spacing: Theme.Space.tight) {
                    Text("Each break lasts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SegmentedSelector(
                        selection: $draft.breaks.minutes,
                        options: [
                            .init(2, "2m"), .init(5, "5m"), .init(10, "10m"), .init(15, "15m"),
                        ],
                        tint: tint
                    )
                }

                VStack(alignment: .leading, spacing: Theme.Space.tight) {
                    Text("How many a day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SegmentedSelector(
                        selection: $draft.breaks.allowance,
                        options: [
                            .init(1, "1"), .init(2, "2"), .init(3, "3"), .init(5, "5"),
                        ],
                        tint: tint
                    )
                }
            }
        }
    }

    private var lock: some View {
        Panel("Lock", subtitle: "Engages the moment the block is switched on.", icon: "lock") {
            VStack(spacing: Theme.Space.tight) {
                ForEach(LockMethod.allCases) { method in
                    OptionCard(
                        title: method.title,
                        detail: method.detail,
                        symbol: method.symbol,
                        isSelected: draft.lock.method == method,
                        tint: tint
                    ) {
                        draft.lock.method = method
                    }
                    .disabled(isLocked)
                }
            }

            switch draft.lock.method {
            case .duration:
                SegmentedSelector(
                    selection: $draft.lock.duration,
                    options: [
                        .init(TimeInterval(1800), "30m"),
                        .init(TimeInterval(3600), "1h"),
                        .init(TimeInterval(14400), "4h"),
                        .init(TimeInterval(28800), "8h"),
                        .init(TimeInterval(86400), "1d"),
                    ],
                    tint: tint
                )
                .disabled(isLocked)
            case .untilTime:
                HStack {
                    Text("Until").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    TimeField(time: $draft.lock.untilTime, tint: tint)
                        .disabled(isLocked)
                }
            case .randomString:
                VStack(alignment: .leading, spacing: Theme.Space.tight) {
                    Text("Characters to type")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SegmentedSelector(
                        selection: $draft.lock.stringLength,
                        options: [.init(16, "16"), .init(32, "32"), .init(64, "64"), .init(128, "128")],
                        tint: tint
                    )
                    .disabled(isLocked)
                }
            case .none, .restart:
                EmptyView()
            }
        }
    }

    private var friction: some View {
        Panel("When you hit it", icon: "hand.raised") {
            VStack(spacing: Theme.Space.tight) {
                ForEach(Friction.allCases) { level in
                    OptionCard(
                        title: level.title,
                        detail: level.summary,
                        symbol: level.symbol,
                        isSelected: draft.friction == level,
                        tint: tint
                    ) {
                        draft.friction = level
                    }
                }
            }

            ShiftTextField(prompt: "Goal, optional. e.g. Finish chapter 3", text: $draft.goal, symbol: "scope")
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            let id = draft.id
            onClose()
            _ = model.store.delete(id: id)
        } label: {
            Label("Delete this block", systemImage: "trash")
                .font(.callout)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.shiftSoft)
        .foregroundStyle(isLocked ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.red))
        .disabled(isLocked)
        .padding(.top, Theme.Space.tight)
    }

    // MARK: Helpers

    private enum ScheduleKind: Hashable { case always, scheduled, manual }

    private var scheduleKind: Binding<ScheduleKind> {
        Binding(
            get: {
                switch draft.schedule {
                case .always: .always
                case .scheduled: .scheduled
                case .manual: .manual
                }
            },
            set: { kind in
                switch kind {
                case .always:
                    draft.schedule = .always
                case .scheduled:
                    if case .scheduled = draft.schedule { return }
                    draft.schedule = .scheduled([ScheduleWindow()])
                case .manual:
                    if case .manual = draft.schedule { return }
                    draft.schedule = .manual(minutes: 50)
                }
            }
        )
    }

    private func binding(for index: Int) -> Binding<ScheduleWindow> {
        Binding(
            get: {
                guard case .scheduled(let all) = draft.schedule, all.indices.contains(index) else {
                    return ScheduleWindow()
                }
                return all[index]
            },
            set: { updated in
                guard case .scheduled(var all) = draft.schedule, all.indices.contains(index) else { return }
                all[index] = updated
                draft.schedule = .scheduled(all)
            }
        )
    }

    private func removeWindow(at index: Int) {
        guard case .scheduled(var all) = draft.schedule, all.indices.contains(index) else { return }
        all.remove(at: index)
        draft.schedule = .scheduled(all)
    }

    private func addSite() {
        let value = newSite.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return }
        if value.contains("/") {
            if !draft.list.paths.contains(value) { draft.list.paths.append(value) }
        } else {
            if !draft.list.hosts.contains(value) { draft.list.hosts.append(value) }
        }
        newSite = ""
    }

    private func addException() {
        let value = newException.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty, !draft.list.exceptions.contains(value) else { return }
        draft.list.exceptions.append(value)
        newException = ""
    }

    static let symbols = [
        "shield.lefthalf.filled", "moon.stars.fill", "brain.head.profile", "book.closed.fill",
        "briefcase.fill", "gamecontroller.fill", "bubble.left.and.bubble.right.fill",
        "tv.fill", "cart.fill", "newspaper.fill", "bolt.fill", "leaf.fill",
    ]
}

// MARK: - Small pieces

private struct EmptyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Wrapping row of chips.
struct ChipFlow: View {
    let items: [String]
    var symbol: String?
    var canRemove: Bool = true
    var label: ((String) -> String)?
    var image: ((String) -> NSImage?)?
    let onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 130), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(items, id: \.self) { item in
                Chip(
                    text: label?(item) ?? item,
                    symbol: symbol,
                    image: image?(item),
                    onRemove: canRemove ? { onRemove(item) } : nil
                )
            }
        }
    }
}

/// One recurring time window: the days, and the two ends of the range.
struct WindowEditor: View {
    @Binding var window: ScheduleWindow
    var tint: Color = .accentColor
    var canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            HStack {
                Text(window.summary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Remove this time window")
                }
            }

            DayPicker(days: $window.days, tint: tint)

            HStack(spacing: Theme.Space.snug) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("From").font(.caption2).foregroundStyle(.tertiary)
                    TimeField(time: $window.start, tint: tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("To").font(.caption2).foregroundStyle(.tertiary)
                    TimeField(time: $window.end, tint: tint)
                }
            }
        }
        .glassSurface(radius: Theme.Radius.control, padding: Theme.Space.snug)
    }
}

// MARK: - App picker

/// Every installed app, searchable, with icons. Replaces sending people to an open panel.
struct AppPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: [String]
    var tint: Color = .accentColor

    @State private var catalog = InstalledApps.shared
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.snug) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Choose apps")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text("\(selected.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ShiftTextField(prompt: "Search", text: $query, symbol: "magnifyingglass")
                    .frame(width: 200)
                Button("Done") { dismiss() }
                    .buttonStyle(.shiftProminent(tint))
            }
            .padding(Theme.Space.base)

            Divider()

            if catalog.isLoading {
                ProgressView("Looking for apps…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180), spacing: Theme.Space.tight)],
                        spacing: Theme.Space.tight
                    ) {
                        ForEach(catalog.matching(query)) { app in
                            AppTile(
                                app: app,
                                isSelected: selected.contains(app.bundleID),
                                tint: tint
                            ) {
                                if let index = selected.firstIndex(of: app.bundleID) {
                                    selected.remove(at: index)
                                } else {
                                    selected.append(app.bundleID)
                                }
                            }
                        }
                    }
                    .padding(Theme.Space.base)
                }
            }
        }
        .frame(width: 640, height: 520)
        .background {
            VisualEffect(surface: .window, blending: .behindWindow).ignoresSafeArea()
        }
        .onAppear { catalog.loadIfNeeded() }
    }
}

private struct AppTile: View {
    let app: InstalledApp
    let isSelected: Bool
    var tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.tight) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                }
                Text(app.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassSurface(radius: Theme.Radius.control, padding: Theme.Space.tight, tint: isSelected ? tint : nil, isSelected: isSelected)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
