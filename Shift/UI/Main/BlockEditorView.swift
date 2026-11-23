import AppKit
import SwiftUI

/// Edits a draft and applies it when the user saves.
struct BlockInspector: View {
    @Environment(AppModel.self) private var model

    @State private var draft: Block
    @State private var original: Block
    @State private var isShowingAppPicker = false
    @State private var isShowingSaveError = false
    @State private var isShowingDiscardConfirmation = false

    private let isNew: Bool
    private let dismissalRequest: Int
    private let onClose: () -> Void

    init(block: Block, isNew: Bool, dismissalRequest: Int, onClose: @escaping () -> Void) {
        _draft = State(initialValue: block)
        _original = State(initialValue: block)
        self.isNew = isNew
        self.dismissalRequest = dismissalRequest
        self.onClose = onClose
    }

    private var savedBlock: Block? { model.store.block(id: draft.id) }
    private var isLocked: Bool { savedBlock?.isLocked() == true }
    private var canRequestUnlock: Bool {
        guard let savedBlock else { return false }
        return savedBlock.requiresUnlockChallenge() && !savedBlock.lock.isLocked()
    }
    private var tint: Color { draft.tint.color }
    private var hasChanges: Bool { draft != original }
    private var canSave: Bool {
        (isNew || hasChanges) && !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.snug) {
                    identity
                    blockedItems
                    schedule
                    breaks
                    lock
                }
                .padding(Theme.Space.base)
            }
            .scrollBounceBehavior(.basedOnSize)

            Hairline()

            footer
        }
        .background {
            VisualEffect(surface: .sidebar, blending: .behindWindow).ignoresSafeArea()
        }
        .onChange(of: isLocked) { _, locked in
            if locked { preserveLockedRules() }
        }
        .onChange(of: dismissalRequest) { _, _ in
            requestClose()
        }
        .sheet(isPresented: $isShowingAppPicker) {
            AppPickerView(selected: $draft.list.apps, tint: tint, canRemove: !isLocked)
        }
        .alert("Couldn’t save block", isPresented: $isShowingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The block changed while you were editing. Review the draft and try again.")
        }
        .confirmationDialog("Discard unsaved changes?", isPresented: $isShowingDiscardConfirmation) {
            Button("Discard changes", role: .destructive, action: onClose)
            Button("Keep editing", role: .cancel) {}
        }
    }

    private func requestClose() {
        if hasChanges {
            isShowingDiscardConfirmation = true
        } else {
            onClose()
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Space.snug) {
            if isLocked, !canRequestUnlock, let savedBlock {
                Label(savedBlock.lock.statusText(), systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isLocked {
                if canSave {
                    Button("Save", action: save)
                        .buttonStyle(.shiftSoft)
                        .keyboardShortcut("s", modifiers: .command)
                }

                if canRequestUnlock {
                    Button {
                        model.requestBlockUnlock(id: draft.id)
                    } label: {
                        Label("Unlock", systemImage: "lock.open")
                    }
                    .buttonStyle(.shiftProminent(tint))
                }
            } else {
                Button("Save", action: save)
                    .buttonStyle(.shiftProminent(tint))
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.45)
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(Theme.Space.base)
    }

    private func save() {
        guard canSave else { return }
        var updated = draft
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if isNew {
            model.store.add(updated)
        } else if !model.store.update(updated) {
            preserveLockedRules()
            isShowingSaveError = true
            return
        }
        onClose()
    }

    /// A draft can already be open when the block is locked from the menu bar.
    /// Restore protected settings while keeping additions and cosmetic edits.
    private func preserveLockedRules() {
        guard let saved = model.store.block(id: draft.id), saved.isLocked() else { return }
        func adding(_ values: [String], to savedValues: [String]) -> [String] {
            var seen = Set(savedValues)
            return savedValues + values.filter { seen.insert($0).inserted }
        }

        var allowed = saved
        allowed.list.hosts = adding(draft.list.hosts, to: saved.list.hosts)
        allowed.list.paths = adding(draft.list.paths, to: saved.list.paths)
        allowed.list.apps = adding(draft.list.apps, to: saved.list.apps)
        allowed.name = draft.name
        allowed.tint = draft.tint
        allowed.symbol = draft.symbol
        original = saved
        draft = allowed
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
                Button(action: requestClose) {
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

    private var blockedItems: some View {
        Panel {
            sites
            Hairline()
                .padding(.vertical, Theme.Space.hair)
            apps
        }
    }

    private var sites: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            PanelHeading(
                title: "Websites",
                icon: "globe",
                help: "Enter a domain to block the whole site, or include a path such as youtube.com/shorts to block just that part."
            )
            SiteEntryField(label: "Website to block", prompt: "example.com", onAdd: addSite)

            BlockEntryList(items: draft.list.hosts + draft.list.paths, symbol: "globe", canRemove: !isLocked) { entry in
                draft.list.hosts.removeAll { $0 == entry }
                draft.list.paths.removeAll { $0 == entry }
            }
        }
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            PanelHeading(title: "Apps", icon: "app.badge")
                .frame(minHeight: 26)
            Button {
                isShowingAppPicker = true
            } label: {
                EntryActionRow {
                    Text("Choose apps")
                        .font(.callout.weight(.medium))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            BlockEntryList(
                items: draft.list.apps,
                symbol: "app.badge",
                canRemove: !isLocked,
                label: { InstalledApps.shared.name(for: $0) ?? $0 },
                image: { InstalledApps.shared.icon(for: $0) }
            ) { entry in
                draft.list.apps.removeAll { $0 == entry }
            }
        }
        .onAppear {
            if !draft.list.apps.isEmpty { InstalledApps.shared.loadIfNeeded() }
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
                    .init(.manual, "None", symbol: "calendar.badge.minus"),
                ],
                tint: tint
            )
            .disabled(isLocked)

            switch draft.schedule {
            case .always:
                EmptyView()

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

            case .manual:
                Text("Start a timed run from the block’s context menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Breaks and lock

    private var breaks: some View {
        Panel {
            HStack(spacing: Theme.Space.tight) {
                PanelHeading(title: "Breaks", icon: "cup.and.saucer")
                ShiftSwitch(isOn: $draft.breaks.isEnabled, tint: tint)
                    .accessibilityLabel("Allow breaks")
                    .disabled(isLocked)
            }
            Text(draft.breaks.isEnabled
                 ? "Up to \(BreakPlan.dailyAllowance) short breaks a day. When you tell the pause you need a site for something specific, just that site opens for one or two minutes. The block stays on."
                 : "Off: every reach is closed. Turn on to allow \(BreakPlan.dailyAllowance) short breaks a day, for when you really need a site.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lock: some View {
        Panel("Lock", icon: "lock") {
            LockMethodPicker(selection: $draft.lock.method, tint: tint)
                .disabled(isLocked)

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
                HStack(spacing: Theme.Space.snug) {
                    Text("Characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    SegmentedSelector(
                        selection: Binding(
                            get: { draft.lock.challengeLength },
                            set: { draft.lock.stringLength = $0 }
                        ),
                        options: BlockLock.challengeLengths.map { .init($0, String($0)) },
                        tint: tint
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Characters to type")
                    .disabled(isLocked)
                }
            case .none, .restart:
                EmptyView()
            }
        }
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
                    draft.schedule = .manual(minutes: nil)
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

    private func addSite(_ address: WebsiteAddress) {
        draft.list.addWebsite(address)
    }

    static let symbols = [
        "shield.lefthalf.filled", "moon.stars.fill", "brain.head.profile", "book.closed.fill",
        "briefcase.fill", "gamecontroller.fill", "bubble.left.and.bubble.right.fill",
        "tv.fill", "cart.fill", "newspaper.fill", "bolt.fill", "leaf.fill",
    ]
}

// MARK: - Block entries

private struct SiteEntryField: View {
    let label: String
    let prompt: String
    let onAdd: (WebsiteAddress) -> Void

    @State private var text = ""
    @State private var showsInvalidEntry = false
    @FocusState private var isFocused: Bool

    private var trimmedEntry: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            EntryActionRow(isFocused: isFocused) {
                TextField(label, text: $text, prompt: Text(prompt))
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .onSubmit(submit)

                Button("Add", action: submit)
                    .buttonStyle(.borderless)
                    .font(.callout.weight(.semibold))
                    .disabled(trimmedEntry.isEmpty)
            }

            if showsInvalidEntry {
                Text("Enter a website like example.com.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: text) { _, _ in showsInvalidEntry = false }
    }

    private func submit() {
        let entry = trimmedEntry
        guard !entry.isEmpty else { return }
        isFocused = true

        guard let address = WebsiteAddress(entry: entry) else {
            showsInvalidEntry = true
            return
        }
        onAdd(address)
        text = ""
    }
}

private struct EntryActionRow<Content: View>: View {
    var isFocused = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)

        HStack(spacing: Theme.Space.tight) {
            Image(systemName: "plus")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            content()
        }
        .padding(.horizontal, Theme.Space.snug)
        .frame(minHeight: 32)
        .background { shape.fill(.quaternary.opacity(0.5)) }
        .overlay {
            shape.strokeBorder(isFocused ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct BlockEntryList: View {
    let items: [String]
    let symbol: String
    var canRemove = true
    var label: ((String) -> String)?
    var image: ((String) -> NSImage?)?
    let onRemove: (String) -> Void

    var body: some View {
        if !items.isEmpty {
            BlockEntryLayout {
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
}

/// Fills each row in entry order using the chips' natural widths, capped for long labels.
private struct BlockEntryLayout: Layout {
    private let maxItemWidth: CGFloat = 176
    private let spacing = Theme.Space.tight

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(in: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrangement(in: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, layout.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: nil)
            )
        }
    }

    private func arrangement(in width: CGFloat?, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let availableWidth = max(0, width ?? .infinity)
        var frames: [CGRect] = []
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0

        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let itemWidth = min(ideal.width, maxItemWidth, availableWidth)
            let itemHeight = itemWidth < ideal.width
                ? subview.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)).height
                : ideal.height

            if x > 0, x + itemWidth > availableWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            frames.append(CGRect(x: x, y: y, width: itemWidth, height: itemHeight))
            contentWidth = max(contentWidth, x + itemWidth)
            rowHeight = max(rowHeight, itemHeight)
            x += itemWidth + spacing
        }

        let size = CGSize(width: availableWidth.isFinite ? availableWidth : contentWidth, height: y + rowHeight)
        return (size, frames)
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
    var canRemove = true

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
                            let isSelected = selected.contains(app.bundleID)
                            AppTile(
                                app: app,
                                isSelected: isSelected,
                                tint: tint
                            ) {
                                if let index = selected.firstIndex(of: app.bundleID) {
                                    guard canRemove else { return }
                                    selected.remove(at: index)
                                } else {
                                    selected.append(app.bundleID)
                                }
                            }
                            .disabled(isSelected && !canRemove)
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
                Group {
                    if let icon = app.icon {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "app")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
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
            .padding(Theme.Space.tight)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .strokeBorder(Color.primary.opacity(0.08))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
