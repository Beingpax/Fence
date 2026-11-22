import SwiftUI

/// Sections of the main window. Settings is one of these rather than a separate window:
/// a menu bar app with two windows is one window too many.
enum MainSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, blocks, activity, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .blocks: "Blocks"
        case .activity: "Activity"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.33percent"
        case .blocks: "shield.lefthalf.filled"
        case .activity: "clock.arrow.circlepath"
        case .settings: "gearshape.fill"
        }
    }
}

/// The main window.
///
/// Layout follows IINA: a translucent sidebar on the left, content in the middle, and an
/// inspector that slides in from the trailing edge for editing. Nothing is modal, so the
/// list stays visible and selected while a block is being changed.
struct MainWindowView: View {
    @Environment(AppModel.self) private var model

    @State private var selectedBlockID: Block.ID?
    @State private var isInspectorPresented = false
    @State private var isShowingTemplates = false

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            Sidebar()
        } detail: {
            detail
                .inspector(isPresented: $isInspectorPresented) {
                    inspector
                        .inspectorColumnWidth(min: 340, ideal: 400, max: 520)
                }
        }
        .navigationTitle("")
        .frame(minWidth: 900, minHeight: 560)
        .translucentWindowBackground()
        .sheet(isPresented: $isShowingTemplates) {
            TemplateGalleryView { template in
                let block = template.makeBlock()
                model.store.add(block)
                selectedBlockID = block.id
                isInspectorPresented = true
            }
        }
        .onChange(of: selectedBlockID) { _, newValue in
            if newValue != nil { isInspectorPresented = true }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.mainSection {
        case .dashboard:
            DashboardView(
                onAddBlock: { isShowingTemplates = true },
                onSelect: { selectedBlockID = $0.id }
            )
        case .blocks:
            BlocksView(
                selection: $selectedBlockID,
                onAddBlock: { isShowingTemplates = true }
            )
        case .activity:
            ActivityView()
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let id = selectedBlockID, let block = model.store.block(id: id) {
            BlockInspector(block: block) {
                isInspectorPresented = false
                selectedBlockID = nil
            }
            .id(block.id)
        } else {
            ContentUnavailableView(
                "Nothing selected",
                systemImage: "sidebar.right",
                description: Text("Pick a block to edit it here.")
            )
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let selection = Binding<MainSection?>(
            get: { model.mainSection },
            set: { if let new = $0 { model.mainSection = new } }
        )

        VStack(spacing: 0) {
            List(selection: selection) {
                ForEach(MainSection.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .font(.callout.weight(.medium))
                        .padding(.vertical, 3)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            WatchStatus()
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        .background {
            VisualEffect(surface: .sidebar, blending: .behindWindow).ignoresSafeArea()
        }
    }
}

/// The one piece of live state worth keeping on screen at all times.
private struct WatchStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Theme.Space.tight) {
            ZStack {
                Circle()
                    .fill(model.isWatching ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                if model.isWatching {
                    Circle()
                        .stroke(Color.green.opacity(0.35), lineWidth: 5)
                        .frame(width: 7, height: 7)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(model.isWatching ? "Watching" : "Idle")
                    .font(.caption.weight(.medium))
                Text(statusDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Space.base)
        .padding(.vertical, Theme.Space.snug)
        .accessibilityElement(children: .combine)
    }

    private var statusDetail: String {
        let active = model.store.activeBlocks.count
        if active == 0 { return "No block active" }
        return "\(active) block\(active == 1 ? "" : "s") active"
    }
}

// MARK: - Blocks

struct BlocksView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: Block.ID?
    let onAddBlock: () -> Void

    @State private var unlockTarget: Block?

    var body: some View {
        Group {
            if model.store.blocks.isEmpty {
                EmptyBlocksView(onAddBlock: onAddBlock)
            } else {
                list
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Blocks")
                    .font(.headline)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: onAddBlock) {
                    Label("New block", systemImage: "plus")
                }
                .help("Add a block")
            }
        }
        .sheet(item: $unlockTarget) { block in
            RandomStringUnlockView(block: block)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Space.snug) {
                ForEach(model.store.blocks) { block in
                    BlockCard(
                        block: block,
                        isSelected: selection == block.id,
                        onSelect: { selection = block.id },
                        onRequestStringUnlock: { unlockTarget = block }
                    )
                }

                Button(action: onAddBlock) {
                    Label("Add a block", systemImage: "plus")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Space.base)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .strokeBorder(
                                    Color.primary.opacity(0.14),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                                )
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, Theme.Space.tight)
            }
            .padding(Theme.Space.loose)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// One block as a card: badge, name, what and when, lock state, and the switch.
struct BlockCard: View {
    @Environment(AppModel.self) private var model
    let block: Block
    let isSelected: Bool
    let onSelect: () -> Void
    let onRequestStringUnlock: () -> Void

    @State private var showingLockedNotice = false

    private var isActive: Bool { block.isActive() }
    private var isLocked: Bool { block.lock.isLocked() }

    var body: some View {
        HStack(spacing: Theme.Space.base) {
            BlockBadge(symbol: block.symbol, tint: block.tint, size: 40, isActive: isActive)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Theme.Space.tight) {
                    Text(block.name)
                        .font(.system(.headline, design: .rounded))
                    if isActive {
                        StatusTag(text: "Active", tint: .green)
                    }
                    if block.breaks.isOnBreak() {
                        StatusTag(text: "On a break", tint: .orange)
                    }
                }

                Text(block.contentsSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: Theme.Space.tight) {
                    Label(block.scheduleSummary, systemImage: scheduleSymbol)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if isLocked {
                        Label(block.lock.statusText(), systemImage: "lock.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
                .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: Theme.Space.snug)

            ShiftSwitch(
                isOn: .constant(block.isEnabled),
                tint: block.tint.color,
                isLocked: isLocked,
                action: { toggle(to: $0) }
            )
            .accessibilityLabel("\(block.name) enabled")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .glassSurface(tint: isActive ? block.tint.color : nil, isSelected: isSelected)
        .contextMenu {
            Button("Edit", action: onSelect)
            if case .manual = block.schedule, !block.isEnabled {
                Button("Start for 25 minutes") { model.store.startManualRun(id: block.id, minutes: 25) }
                Button("Start for 50 minutes") { model.store.startManualRun(id: block.id, minutes: 50) }
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
            Text(block.lock.statusText())
        }
    }

    private var scheduleSymbol: String {
        switch block.schedule {
        case .always: "infinity"
        case .scheduled: "calendar"
        case .manual: "play.circle"
        }
    }

    private func toggle(to enabled: Bool) {
        switch model.store.setEnabled(enabled, for: block.id) {
        case .changed:
            model.log("\(block.name) \(enabled ? "on" : "off")", symbol: enabled ? "shield.fill" : "shield.slash")
        case .refusedLocked:
            showingLockedNotice = true
        case .needsRandomString:
            onRequestStringUnlock()
        }
    }
}

struct StatusTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }
}

// MARK: - Empty state

private struct EmptyBlocksView: View {
    let onAddBlock: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.base) {
            BlockBadge(symbol: "shield.lefthalf.filled", tint: .indigo, size: 60)
                .shadow(color: .indigo.opacity(0.25), radius: 16, y: 6)

            VStack(spacing: Theme.Space.tight) {
                Text("Pick something to block")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text("Start from one of the ready-made blocks, then make it yours. Each one keeps its own list, schedule and lock.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button(action: onAddBlock) {
                Label("Browse blocks", systemImage: "square.grid.2x2")
            }
            .buttonStyle(.shiftProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.vast)
    }
}

// MARK: - Template gallery

struct TemplateGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (BlockTemplate) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a block")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text("Ready-made, and editable afterwards.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(Theme.Space.loose)

            Divider()

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 230), spacing: Theme.Space.snug)],
                    spacing: Theme.Space.snug
                ) {
                    ForEach(BlockTemplate.all) { template in
                        TemplateCard(template: template) {
                            onPick(template)
                            dismiss()
                        }
                    }
                }
                .padding(Theme.Space.loose)
            }
        }
        .frame(width: 720, height: 520)
        .background {
            VisualEffect(surface: .window, blending: .behindWindow).ignoresSafeArea()
        }
    }
}

private struct TemplateCard: View {
    let template: BlockTemplate
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                BlockBadge(symbol: template.symbol, tint: template.tint, size: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(template.name)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(template.tagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HStack(spacing: Theme.Space.tight) {
                    if template.hosts.count + template.paths.count > 0 {
                        Chip(text: "\(template.hosts.count + template.paths.count) sites", symbol: "globe")
                    }
                    if !template.apps.isEmpty {
                        Chip(text: "\(template.apps.count) apps", symbol: "app.badge")
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassSurface(tint: template.tint.color, isSelected: isHovering)
        .onHover { isHovering = $0 }
        .accessibilityHint(template.tagline)
    }
}

// MARK: - Random string unlock

struct RandomStringUnlockView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let block: Block

    @State private var challenge = ""
    @State private var typed = ""
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.base) {
            VStack(alignment: .leading, spacing: Theme.Space.tight) {
                Text("Type this to unlock “\(block.name)”")
                    .font(.system(.headline, design: .rounded))
                Text("No copy and paste. The typing is the friction.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(challenge)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.disabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(radius: Theme.Radius.control, padding: Theme.Space.snug)

            ShiftTextField(prompt: "Type it here", text: $typed, symbol: "keyboard", onSubmit: attempt)

            if failed {
                Label("That doesn't match yet.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.shiftSoft)
                    .keyboardShortcut(.cancelAction)
                Button("Unlock", action: attempt)
                    .buttonStyle(.shiftProminent)
                    .disabled(typed.isEmpty)
            }
        }
        .padding(Theme.Space.loose)
        .frame(width: 480)
        .background {
            VisualEffect(surface: .window, blending: .behindWindow).ignoresSafeArea()
        }
        .onAppear { challenge = BlockStore.randomChallenge(length: block.lock.stringLength) }
    }

    private func attempt() {
        if model.store.unlockWithString(typed, challenge: challenge, for: block.id) {
            model.log("\(block.name) unlocked", symbol: "lock.open")
            dismiss()
        } else {
            failed = true
        }
    }
}

// MARK: - Activity

struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.activity.isEmpty {
                ContentUnavailableView(
                    "Nothing yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Blocks, nudges and shields show up here as they happen.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.activity) { event in
                            HStack(spacing: Theme.Space.snug) {
                                Image(systemName: event.symbol)
                                    .font(.caption)
                                    .frame(width: 20)
                                    .foregroundStyle(.secondary)
                                Text(event.text)
                                    .font(.callout)
                                Spacer()
                                Text(event.date, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, Theme.Space.snug)
                            .padding(.vertical, 7)
                            .background {
                                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                    .fill(.quaternary.opacity(0.4))
                            }
                        }
                    }
                    .padding(Theme.Space.loose)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Activity").font(.headline)
            }
        }
    }
}
