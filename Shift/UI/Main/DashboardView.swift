import SwiftUI

/// What is happening right now, and anything standing in the way of it working.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    let onAddBlock: () -> Void
    let onSelect: (Block) -> Void

    private var active: [Block] { model.store.activeBlocks }
    private var locked: [Block] { model.store.blocks.filter { $0.lock.isLocked() } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.base) {
                hero

                if !permissionIssues.isEmpty {
                    VStack(spacing: Theme.Space.tight) {
                        ForEach(permissionIssues) { issue in
                            PermissionRow(issue: issue)
                        }
                    }
                }

                stats

                if active.isEmpty {
                    idle
                } else {
                    activeList
                }
            }
            .padding(Theme.Space.loose)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Dashboard").font(.headline)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: onAddBlock) {
                    Label("New block", systemImage: "plus")
                }
                .help("Add a block")
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: Theme.Space.base) {
            ZStack {
                Circle()
                    .fill(model.isWatching ? AnyShapeStyle(Color.green.gradient.opacity(0.22)) : AnyShapeStyle(Color.secondary.opacity(0.12)))
                    .frame(width: 62, height: 62)
                Image(systemName: model.isWatching ? "eye.fill" : "eye.slash.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(model.isWatching ? .green : .secondary)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.isWatching ? "Shift is watching" : "Nothing is blocked")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .glassSurface(radius: Theme.Radius.panel, padding: Theme.Space.loose)
    }

    private var subtitle: String {
        if active.isEmpty {
            let waiting = model.store.blocks.filter { block in
                if case .scheduled = block.schedule { return block.isEnabled }
                return false
            }
            if !waiting.isEmpty {
                return "\(waiting.count) scheduled block\(waiting.count == 1 ? "" : "s") waiting for their window."
            }
            return model.store.blocks.isEmpty ? "Add a block to get started." : "Switch a block on when you're ready."
        }
        let names = active.map(\.name).joined(separator: ", ")
        return locked.isEmpty ? names : "\(names) · \(locked.count) locked"
    }

    // MARK: Stats

    private var stats: some View {
        HStack(spacing: Theme.Space.snug) {
            StatTile(
                value: "\(active.count)",
                label: "Active now",
                symbol: "bolt.fill",
                tint: .green
            )
            StatTile(
                value: "\(model.store.blocks.reduce(0) { $0 + $1.stats.timesTriggered })",
                label: "Times stopped",
                symbol: "hand.raised.fill",
                tint: .orange
            )
            StatTile(
                value: "\(locked.count)",
                label: "Locked",
                symbol: "lock.fill",
                tint: .indigo
            )
        }
    }

    // MARK: Lists

    private var idle: some View {
        Panel("Your blocks", icon: "shield.lefthalf.filled") {
            if model.store.blocks.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.snug) {
                    Text("No blocks yet. Start from a ready-made one.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button(action: onAddBlock) {
                        Label("Browse blocks", systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(.shiftProminent)
                }
            } else {
                VStack(spacing: Theme.Space.tight) {
                    ForEach(model.store.blocks) { block in
                        BlockMiniRow(block: block, onSelect: { onSelect(block) })
                    }
                }
            }
        }
    }

    private var activeList: some View {
        Panel("Active now", icon: "bolt.fill") {
            VStack(spacing: Theme.Space.tight) {
                ForEach(active) { block in
                    BlockMiniRow(block: block, onSelect: { onSelect(block) })
                }
            }
        }
    }

    private var permissionIssues: [PermissionIssue] {
        var issues: [PermissionIssue] = []
        if !model.accessibilityGranted {
            issues.append(PermissionIssue(
                title: "Accessibility is off",
                detail: "Without it Shift can't tell which window is in front, so nothing will be blocked.",
                action: { model.requestAccessibilityPermission() }
            ))
        }
        return issues
    }
}

// MARK: - Pieces

struct PermissionIssue: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let action: () -> Void
}

struct PermissionRow: View {
    let issue: PermissionIssue

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.snug) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title).font(.callout.weight(.semibold))
                Text(issue.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.tight)
            Button("Grant", action: issue.action)
                .buttonStyle(.shiftSoft)
        }
        .padding(Theme.Space.snug)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var symbol: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(padding: Theme.Space.base)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// A one-line block row with a switch, used on the dashboard.
struct BlockMiniRow: View {
    @Environment(AppModel.self) private var model
    let block: Block
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.snug) {
            BlockBadge(symbol: block.symbol, tint: block.tint, size: 28, isActive: block.isActive())

            VStack(alignment: .leading, spacing: 1) {
                Text(block.name)
                    .font(.callout.weight(.medium))
                Text(block.isActive() ? block.contentsSummary : block.scheduleSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.tight)

            if block.lock.isLocked() {
                Label(block.lock.statusText(), systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }

            ShiftSwitch(
                isOn: .constant(block.isEnabled),
                tint: block.tint.color,
                isLocked: block.lock.isLocked(),
                action: { enabled in
                    _ = model.store.setEnabled(enabled, for: block.id)
                }
            )
            .accessibilityLabel("\(block.name) enabled")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .padding(.vertical, 2)
    }
}
