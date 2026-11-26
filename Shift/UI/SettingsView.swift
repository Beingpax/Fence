import SwiftUI

/// Settings, as a pane in the main window rather than a separate window.
///
/// Laid out the way macOS lays out its own settings: titled groups of rows on rounded
/// cards, 13 pt text, rows about 38 pt tall, mini system switches and small push buttons,
/// thin dividers inset from the leading edge. Explanations live in hover tooltips.
/// Permissions only appear while one still needs the person; once all are allowed, the
/// group goes away.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.groupGap) {
                Text("Settings")
                    .font(PlayType.rounded(24, .bold))
                    .foregroundStyle(Paper.ink)
                    .accessibilityAddTraits(.isHeader)

                if needsAttention { attention }
                general
                nudges
                previews
                howItWorks
                setup
            }
            .padding(.horizontal, SettingsMetrics.pageSide)
            .padding(.top, SettingsMetrics.pageTop)
            .padding(.bottom, SettingsMetrics.pageBottom)
            .frame(maxWidth: SettingsMetrics.maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { model.refreshSystemState() }
    }

    // MARK: Permissions

    private var backgroundNeedsAttention: Bool {
        !model.backgroundBlockingAllowed || model.backgroundServiceOffline
    }

    private var needsAttention: Bool {
        backgroundNeedsAttention || model.browserAccessNeedsAttention || model.launchAtLoginNeedsApproval
    }

    /// Only the permissions that still need doing. Allowed ones aren't listed at all.
    private var attention: some View {
        SettingsGroup("Needs your attention") {
            if backgroundNeedsAttention {
                permissionRow(.backgroundBlocking, symbol: "bolt.horizontal.fill")
            }
            if model.browserAccessNeedsAttention {
                if backgroundNeedsAttention { GroupDivider() }
                permissionRow(.browserAccess, symbol: "safari.fill")
            }
            if model.launchAtLoginNeedsApproval {
                if backgroundNeedsAttention || model.browserAccessNeedsAttention { GroupDivider() }
                permissionRow(.openAtLogin, symbol: "power")
            }
        }
    }

    private func permissionRow(_ permission: BlockingPermissionRow.Permission, symbol: String) -> some View {
        let feedback = BlockingPermissionRow.feedback(for: permission, model: model)
        return SettingsRow(
            BlockingPermissionRow.title(for: permission),
            detail: feedback.detail,
            icon: symbol
        ) {
            if let action = feedback.action {
                Button(action.title, action: action.perform)
                    .buttonStyle(.borderedProminent)
                    .tint(Paper.coral)
                    .controlSize(.small)
            }
        }
    }

    // MARK: Groups

    private var general: some View {
        @Bindable var model = model
        return SettingsGroup("General") {
            if !model.launchAtLoginNeedsApproval {
                SettingsRow("Open Shift at login", help: "Your blocks are ready the moment you sign in.") {
                    MiniSwitch(isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                }
                GroupDivider()
            }
            SettingsRow("Show Shift in the Dock", help: "Open the main window from the Dock as well as the menu bar.") {
                MiniSwitch(isOn: $model.showInDock)
            }
        }
    }

    private var nudges: some View {
        @Bindable var model = model
        return SettingsGroup("Nudges") {
            SettingsRow("Show nudges", help: "A quiet card when a window title looks like a feed, such as Shorts or Reels.") {
                MiniSwitch(isOn: $model.showNudges)
            }
            GroupDivider()
            SettingsRow("Sounds", help: "A soft chime when Shift pauses you, a deeper one from the third time in an hour, and a bright one when you turn back.") {
                MiniSwitch(isOn: $model.playNudgeSounds)
            }
        }
    }

    private var previews: some View {
        SettingsGroup("Previews") {
            SettingsRow("The pause", help: "10, then 20, then 30 seconds before the choices open, for reaches within an hour.") {
                HStack(spacing: 6) {
                    Button("First") { model.previewPause(visit: 1) }
                    Button("Second") { model.previewPause(visit: 2) }
                    Button("Third") { model.previewPause(visit: 3) }
                }
                .controlSize(.small)
            }
            GroupDivider()
            SettingsRow("Turning back", help: "What Shift does when you walk away.") {
                Button("Show") { model.previewReward() }
                    .controlSize(.small)
            }
            GroupDivider()
            SettingsRow("Drift hint", help: "The quiet card for mild drift. It never escalates.") {
                Button("Show") { model.previewHint() }
                    .controlSize(.small)
            }
        }
    }

    private var howItWorks: some View {
        SettingsGroup("How blocking works") {
            StepRow(number: 1, title: "It notices",
                    detail: "A site, a page or an app on an active block comes up.")
            GroupDivider()
            StepRow(number: 2, title: "You pause",
                    detail: "One breath first: 10 seconds, then 20, then 30 for the same thing within an hour.")
            GroupDivider()
            StepRow(number: 3, title: "You choose",
                    detail: "Close the tab or quit the app whenever you like. Shift cheers when you do.")
            GroupDivider()
            StepRow(number: 4, title: "Need it anyway?",
                    detail: "If the block allows breaks, say why and get 2 or 5 minutes after a \(BreakPlan.waitMinutes)-minute wait. The rest of the block stays on.")
        }
    }

    private var setup: some View {
        SettingsGroup("Setup") {
            SettingsRow("First-time setup", help: "Walk through choosing distractions, permissions and your first block again.") {
                Button("Open Setup…", action: model.presentOnboarding)
                    .controlSize(.small)
            }
            GroupDivider()
            SettingsRow(
                "Uninstall Shift",
                help: model.canQuitApp
                    ? "Quit Shift and select it in Finder for removal."
                    : "During a running block or lock, Shift puts itself back if it’s moved to the Trash."
            ) {
                Button("Prepare to Uninstall…", action: model.requestUninstall)
                    .controlSize(.small)
                    .disabled(!model.canQuitApp)
            }
        }
    }
}

// MARK: - Layout

/// The page's spacing, after System Settings: groups well apart, rows close together.
private enum SettingsMetrics {
    static let maxWidth: CGFloat = 680
    static let pageSide: CGFloat = 24
    static let pageTop: CGFloat = 20
    static let pageBottom: CGFloat = 28
    /// Between groups (and between the page title and the first group).
    static let groupGap: CGFloat = 22
    /// Between a group's title and its card.
    static let headerGap: CGFloat = 7
    /// Inside a row.
    static let rowSide: CGFloat = 12
    static let rowVertical: CGFloat = 9
    static let rowMinHeight: CGFloat = 38
    static let cardRadius: CGFloat = 10
}

// MARK: - Pieces

/// A titled group: a short heading above a rounded card of rows.
private struct SettingsGroup<Content: View>: View {
    let title: String
    let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.headerGap) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Paper.ink)
                .padding(.leading, 2)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                content()
            }
            .background {
                RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous)
                    .fill(Paper.card)
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous)
                    .strokeBorder(Paper.hairline, lineWidth: 1)
            }
        }
    }
}

/// One row: a title on the left, its control on the right. The optional detail line is
/// only for things that need doing; anything else explanatory goes in `help`, on hover.
private struct SettingsRow<Trailing: View>: View {
    let title: String
    let detail: String?
    let help: String?
    let icon: String?
    let trailing: () -> Trailing

    init(
        _ title: String,
        detail: String? = nil,
        help: String? = nil,
        icon: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.detail = detail
        self.help = help
        self.icon = icon
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let icon {
                SidebarIconTile(systemName: icon, background: Color(nsColor: .systemOrange), size: 22)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Paper.ink)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .help(help ?? "")
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, SettingsMetrics.rowSide)
        .padding(.vertical, SettingsMetrics.rowVertical)
        .frame(minHeight: SettingsMetrics.rowMinHeight)
    }
}

/// A numbered step in "How blocking works".
private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Paper.coralText)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Paper.coralSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Paper.ink)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingsMetrics.rowSide)
        .padding(.vertical, SettingsMetrics.rowVertical)
        .frame(minHeight: SettingsMetrics.rowMinHeight)
    }
}

/// A hairline between rows, inset from the leading edge like the system's.
private struct GroupDivider: View {
    var body: some View {
        Rectangle()
            .fill(Paper.hairline)
            .frame(height: 1)
            .padding(.leading, SettingsMetrics.rowSide)
    }
}

/// The system switch at the size System Settings uses.
private struct MiniSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
    }
}
