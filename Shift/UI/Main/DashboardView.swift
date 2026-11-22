import SwiftUI

/// What is happening right now, and anything standing in the way of it working.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    let onCreateBlock: () -> Void
    let onEdit: (Block) -> Void

    private var active: [Block] { model.store.activeBlocks }
    private var locked: [Block] { model.store.blocks.filter { $0.lock.isLocked() } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.loose) {
                statusHeader

                if !permissionIssues.isEmpty {
                    PermissionBanner(issues: permissionIssues)
                }

                if active.isEmpty {
                    idleCard
                } else {
                    activeSection
                }

                statsRow
            }
            .padding(Theme.Space.loose)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Dashboard")
        .scrollBounceBehavior(.basedOnSize)
    }

    private var statusHeader: some View {
        HStack(alignment: .center, spacing: Theme.Space.base) {
            ZStack {
                Circle()
                    .fill(model.isWatching ? Color.green.opacity(0.16) : Color.secondary.opacity(0.12))
                    .frame(width: 54, height: 54)
                Image(systemName: model.isWatching ? "eye.fill" : "eye.slash")
                    .font(.title2)
                    .foregroundStyle(model.isWatching ? .green : .secondary)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.isWatching ? "Shift is watching" : "Nothing is blocked right now")
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var subtitle: String {
        if active.isEmpty {
            let scheduled = model.store.blocks.filter {
                if case .scheduled = $0.schedule { return $0.isEnabled }
                return false
            }
            if !scheduled.isEmpty {
                return "\(scheduled.count) scheduled block\(scheduled.count == 1 ? "" : "s") waiting for their window."
            }
            return "Switch a block on, or create one."
        }
        let names = active.map(\.name).joined(separator: ", ")
        return locked.isEmpty ? names : "\(names) · \(locked.count) locked"
    }

    private var idleCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            Text("No block is active")
                .font(.headline)
            Text("Blocks only police the screen while they're on and inside their schedule.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(action: onCreateBlock) {
                Label("New block", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.base)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            SectionLabel(text: "Active now")
            ForEach(active) { block in
                Button {
                    onEdit(block)
                } label: {
                    HStack(spacing: Theme.Space.snug) {
                        BlockBadge(symbol: block.symbol, tint: block.tint, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(block.name).font(.callout.weight(.medium))
                            Text(block.contentsSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if block.lock.isLocked() {
                            Label(block.lock.statusText(), systemImage: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(Theme.Space.snug)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
        }
    }

    private var statsRow: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            SectionLabel(text: "Today")
            HStack(spacing: Theme.Space.snug) {
                StatTile(
                    value: "\(model.store.blocks.reduce(0) { $0 + $1.stats.timesTriggered })",
                    label: "Times stopped"
                )
                StatTile(value: "\(model.store.blocks.count)", label: "Blocks")
                StatTile(value: "\(locked.count)", label: "Locked")
            }
        }
    }

    private var permissionIssues: [PermissionBanner.Issue] {
        var issues: [PermissionBanner.Issue] = []
        if !model.accessibilityGranted {
            issues.append(.init(
                title: "Accessibility is off",
                detail: "Without it Shift can't tell which window is in front, so nothing will be blocked.",
                actionTitle: "Grant…",
                action: { model.requestAccessibilityPermission() }
            ))
        }
        let needsScreen = model.store.blocks.contains { !$0.list.keywords.isEmpty }
        if needsScreen && !model.screenRecordingGranted {
            issues.append(.init(
                title: "Screen Recording is off",
                detail: "A block uses on-screen keywords, which need screen access to read.",
                actionTitle: "Grant…",
                action: { model.requestScreenRecordingPermission() }
            ))
        }
        return issues
    }
}

struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.snug)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct PermissionBanner: View {
    struct Issue: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let actionTitle: String
        let action: () -> Void
    }

    let issues: [Issue]

    var body: some View {
        VStack(spacing: Theme.Space.tight) {
            ForEach(issues) { issue in
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
                    Button(issue.actionTitle, action: issue.action)
                        .buttonStyle(.bordered)
                }
                .padding(Theme.Space.snug)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
        }
    }
}
