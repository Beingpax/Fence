import SwiftUI

/// What is happening right now, and anything standing in the way of it working.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    let onAddBlock: () -> Void
    let onSelect: (Block) -> Void

    private var active: [Block] { model.store.activeBlocks }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.base) {
                header

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
            .mainPageInsets()
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: Header

    private var header: some View {
        PageHeader("Dashboard", subtitle: subtitle) {
            if !active.isEmpty {
                Circle()
                    .fill(Color(nsColor: .systemGreen))
                    .frame(width: 8, height: 8)
                    .frame(width: 24, height: 36, alignment: .trailing)
                    .help("A block is active")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("A block is active")
            }
        }
    }

    /// The one line that answers "is anything happening right now".
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
        return active.map(\.name).joined(separator: ", ")
    }

    // MARK: Stats

    private var stats: some View {
        HStack(spacing: Theme.Space.snug) {
            StatTile(
                value: "\(active.count)",
                label: "Active now",
                symbol: "bolt.fill",
                tint: Color(nsColor: .secondaryLabelColor)
            )
            StatTile(
                value: "\(model.store.blocks.reduce(0) { $0 + $1.stats.timesTriggered })",
                label: "Times paused",
                symbol: "wind",
                tint: Color(nsColor: .secondaryLabelColor)
            )
        }
    }

    // MARK: Lists

    private var idle: some View {
        Panel("Your blocks", icon: "shield.lefthalf.filled") {
            if model.store.blocks.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.snug) {
                    Text("No blocks yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button(action: onAddBlock) {
                        Label("Add a block", systemImage: "plus")
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
                detail: "Allow Shift to read window titles and browser addresses for your blocks.",
                symbol: "exclamationmark.triangle.fill",
                tint: .orange,
                action: { model.requestAccessibilityPermission() }
            ))
        }
        return issues
    }
}

// MARK: - Pieces

struct PermissionIssue: Identifiable {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var id: String { title }
}

struct PermissionRow: View {
    let issue: PermissionIssue

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.snug) {
            Image(systemName: issue.symbol)
                .foregroundStyle(issue.tint)
                .accessibilityHidden(true)
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
        .glassSurface(padding: Theme.Space.snug, tint: issue.tint)
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
            BlockBadge(symbol: block.symbol, tint: block.tint, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(block.name)
                    .font(.callout.weight(.medium))
                Text(block.isActive() ? block.contentsSummary : block.scheduleSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.tight)

            if block.isLocked(), !block.requiresUnlockChallenge() {
                Label(block.lockStatus(), systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }

            ShiftSwitch(
                isOn: .constant(block.isEnabled),
                isLocked: block.isLocked(),
                action: { enabled in
                    if model.store.setEnabled(enabled, for: block.id) == .needsRandomString {
                        model.requestBlockUnlock(id: block.id)
                    }
                }
            )
            .accessibilityLabel("\(block.name) enabled")
            .disabled(block.canStartTimedRun)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .padding(.vertical, 2)
    }
}
