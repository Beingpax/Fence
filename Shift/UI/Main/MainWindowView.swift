import SwiftUI

/// The main window: a sidebar, and a pane per section.
///
/// Structure follows the platform rather than the web app it's inspired by. A
/// `NavigationSplitView` gives the standard sidebar behaviour for free, including the
/// collapse control, the translucent material, and full-height layout under the title bar.
struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @State private var section: Section? = .blocks
    @State private var editing: Block?
    @State private var isCreating = false

    enum Section: String, CaseIterable, Identifiable, Hashable {
        case dashboard, blocks, activity

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .blocks: "Blocks"
            case .activity: "Activity"
            }
        }

        var symbol: String {
            switch self {
            case .dashboard: "gauge.with.dots.needle.33percent"
            case .blocks: "shield.lefthalf.filled"
            case .activity: "list.bullet.rectangle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("Shift")
        .frame(minWidth: 820, minHeight: 520)
        .sheet(item: $editing) { block in
            BlockEditorView(block: block) { updated in
                if model.store.block(id: updated.id) == nil {
                    model.store.add(updated)
                } else if !model.store.update(updated) {
                    model.log("Edit refused · \(updated.name) is locked", symbol: "lock.fill")
                }
            }
        }
        .onChange(of: isCreating) { _, creating in
            guard creating else { return }
            editing = Block(name: "New block")
            isCreating = false
        }
    }

    private var sidebar: some View {
        List(selection: $section) {
            ForEach(Section.allCases) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        .safeAreaInset(edge: .bottom) {
            SidebarFooter()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch section ?? .blocks {
        case .dashboard:
            DashboardView(onCreateBlock: { isCreating = true }, onEdit: { editing = $0 })
        case .blocks:
            BlocksView(onEdit: { editing = $0 }, onCreate: { isCreating = true })
        case .activity:
            ActivityView()
        }
    }
}

// MARK: - Sidebar footer

private struct SidebarFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            Divider()
            HStack(spacing: Theme.Space.tight) {
                Circle()
                    .fill(model.isWatching ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text(model.isWatching ? "Watching" : "Idle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }
            .padding(.horizontal, Theme.Space.snug)
            .padding(.bottom, Theme.Space.snug)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.isWatching ? "Shift is watching" : "Shift is idle")
    }
}

// MARK: - Blocks

struct BlocksView: View {
    @Environment(AppModel.self) private var model
    let onEdit: (Block) -> Void
    let onCreate: () -> Void

    @State private var unlockTarget: Block?

    var body: some View {
        Group {
            if model.store.blocks.isEmpty {
                EmptyBlocksView(onCreate: onCreate)
            } else {
                list
            }
        }
        .navigationTitle("Blocks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onCreate) {
                    Label("New block", systemImage: "plus")
                }
                .help("Create a block")
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
                    BlockRow(
                        block: block,
                        onEdit: { onEdit(block) },
                        onRequestStringUnlock: { unlockTarget = block }
                    )
                }
            }
            .padding(Theme.Space.loose)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct EmptyBlocksView: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.base) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No blocks yet")
                .font(.title2.weight(.semibold))
            Text("A block is a named set of sites and apps, with its own schedule and its own lock. Make one for deep work, one for evenings, one that's always on.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button(action: onCreate) {
                Label("Create your first block", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.vast)
    }
}

/// One block, as a card. Everything that matters is on one line of text plus a switch.
struct BlockRow: View {
    @Environment(AppModel.self) private var model
    let block: Block
    let onEdit: () -> Void
    let onRequestStringUnlock: () -> Void

    @State private var showingLockedNotice = false

    private var isActive: Bool { block.isActive() }
    private var isLocked: Bool { block.lock.isLocked() }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.base) {
            BlockBadge(symbol: block.symbol, tint: block.tint, isActive: isActive)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.Space.tight) {
                    Text(block.name)
                        .font(.headline)
                    if isActive {
                        Text("Active")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.16), in: Capsule())
                            .foregroundStyle(.green)
                    }
                    if block.breaks.isOnBreak() {
                        Text("On a break")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.16), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text(block.contentsSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(block.scheduleSummary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: Theme.Space.snug)

            VStack(alignment: .trailing, spacing: Theme.Space.tight) {
                Toggle("", isOn: Binding(
                    get: { block.isEnabled },
                    set: { toggle(to: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel("\(block.name) enabled")

                Label(block.lock.statusText(), systemImage: isLocked ? "lock.fill" : "lock.open")
                    .font(.caption2)
                    .foregroundStyle(isLocked ? .orange : .secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(Theme.Space.base)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(isActive ? block.tint.color.opacity(0.45) : Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button("Edit…", action: onEdit)
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
                    .font(.headline)
                Text("No copy and paste. The typing is the friction.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(challenge)
                .font(.system(.body, design: .monospaced))
                .textSelection(.disabled)
                .padding(Theme.Space.snug)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))

            TextField("Type it here", text: $typed)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit(attempt)

            if failed {
                Label("That doesn't match yet.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Unlock", action: attempt)
                    .buttonStyle(.borderedProminent)
                    .disabled(typed.isEmpty)
            }
        }
        .padding(Theme.Space.loose)
        .frame(width: 460)
        .onAppear {
            challenge = BlockStore.randomChallenge(length: block.lock.stringLength)
        }
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
                    systemImage: "list.bullet.rectangle",
                    description: Text("Blocks, nudges and shields show up here as they happen.")
                )
            } else {
                List(model.activity) { event in
                    HStack(spacing: Theme.Space.snug) {
                        Image(systemName: event.symbol)
                            .frame(width: 18)
                            .foregroundStyle(.secondary)
                        Text(event.text)
                        Spacer()
                        Text(event.date, style: .time)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    .font(.callout)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Activity")
    }
}
