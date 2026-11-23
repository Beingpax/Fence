import SwiftUI

/// Settings, as a pane in the main window rather than a separate window.
///
/// Built from the same `Panel` and control pieces as everything else, so it reads as part
/// of the app instead of a system settings window that wandered in.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.base) {
                PageHeader("Settings")
                startup
                nudges
                previews
                detection
                about
            }
            .mainPageInsets()
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { model.refreshSystemState() }
    }

    // MARK: Sections

    private var startup: some View {
        @Bindable var model = model
        return Panel("Startup", icon: "power") {
            PanelRow(
                title: "Open Shift at login",
                detail: "Show the Shift menu bar at sign-in. Enabled blocks also start the background service at login."
            ) {
                ShiftSwitch(
                    isOn: .constant(model.launchAtLoginEnabled),
                    action: { model.setLaunchAtLogin($0) }
                )
            }

            if LaunchAtLogin.requiresApproval {
                PanelRow(title: "Needs approval in System Settings") {
                    Button("Open") { LaunchAtLogin.openLoginItemsSettings() }
                        .buttonStyle(.shiftSoft)
                }
            }

            PanelRow(
                title: "Show Shift in the Dock",
                detail: "Open the main window from the Dock as well as the menu bar."
            ) {
                ShiftSwitch(isOn: $model.showInDock)
            }
        }
    }

    private var nudges: some View {
        @Bindable var model = model
        return Panel(
            "Nudges",
            subtitle: "A quiet card when a window title looks like a feed, such as Shorts or Reels.",
            icon: "arrow.turn.up.left"
        ) {
            PanelRow(title: "Show nudges") {
                ShiftSwitch(isOn: $model.showNudges)
            }
            PanelRow(title: "Sounds", detail: "A soft chime when Shift pauses you, a deeper one from the third time in an hour, and a bright one when you turn back.") {
                ShiftSwitch(isOn: $model.playNudgeSounds)
            }
        }
    }

    private var previews: some View {
        Panel(
            "Previews",
            subtitle: "See each moment as it happens, without visiting a blocked site.",
            icon: "eye"
        ) {
            PanelRow(title: "The pause", detail: "Reaches within an hour: 10, then 20, then 30 seconds before the choices open.") {
                HStack(spacing: Theme.Space.tight) {
                    Button("First") { model.previewPause(visit: 1) }
                        .buttonStyle(.shiftSoft)
                    Button("Second") { model.previewPause(visit: 2) }
                        .buttonStyle(.shiftSoft)
                    Button("Third") { model.previewPause(visit: 3) }
                        .buttonStyle(.shiftSoft)
                }
            }
            PanelRow(title: "Turning back", detail: "What Flop does when you walk away.") {
                Button("Show") { model.previewReward() }
                    .buttonStyle(.shiftSoft)
            }
            PanelRow(title: "Drift hint", detail: "The quiet card, for mild drift. Never escalates.") {
                Button("Show") { model.previewHint() }
                    .buttonStyle(.shiftSoft)
            }
        }
    }

    private var detection: some View {
        Panel("How blocking works", icon: "scope") {
            Text("When a site, page, or app matches an active block, Shift shows what was blocked. The pause gives you time to breathe before asking what brought you there. You can close the blocked tab or quit the blocked app at any time. If breaks are enabled, choose “I need it,” enter a reason, and pick 2 or 5 minutes of access. Your access time starts after a \(BreakPlan.waitMinutes)-minute wait. The rest of the block stays on. For the same rule within an hour, choices appear after 10 seconds the first time, 20 the second time, and 30 thereafter.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var about: some View {
        Panel("Setup", icon: "sparkle") {
            PanelRow(title: "Run first-time setup again") {
                Button("Open setup") { model.presentOnboarding() }
                    .buttonStyle(.shiftSoft)
            }
            PanelRow(
                title: "Uninstall Shift",
                detail: model.canQuitApp ? "Quit Shift and select it in Finder for removal." : "During a running block or lock, Shift tries to put the app back if moved to the Trash."
            ) {
                Button("Prepare to uninstall…") { model.requestUninstall() }
                    .buttonStyle(.shiftSoft)
                    .disabled(!model.canQuitApp)
            }
        }
    }
}
