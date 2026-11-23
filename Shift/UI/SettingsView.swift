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
        return Panel("Startup", icon: "power", tint: .indigo) {
            PanelRow(
                title: "Open Shift at login",
                detail: "Start Shift when you sign in to your Mac."
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
            subtitle: "A small reminder when activity drifts from your focus goal.",
            icon: "arrow.turn.up.left",
            tint: .teal
        ) {
            PanelRow(title: "Show nudges") {
                ShiftSwitch(isOn: $model.showNudges)
            }
            PanelRow(title: "Sounds", detail: "A soft chime when Shift pauses you, a bright one when you turn back, and a calm tone if the screen is covered.") {
                ShiftSwitch(isOn: $model.playNudgeSounds)
            }
        }
    }

    private var previews: some View {
        Panel(
            "Previews",
            subtitle: "See each moment as it happens, without visiting a blocked site.",
            icon: "eye",
            tint: .orange
        ) {
            PanelRow(title: "The pause", detail: "First reach: one breath. Second in an hour: three.") {
                HStack(spacing: Theme.Space.tight) {
                    Button("First") { model.previewPause(visit: 1) }
                        .buttonStyle(.shiftSoft)
                    Button("Second") { model.previewPause(visit: 2) }
                        .buttonStyle(.shiftSoft)
                }
            }
            PanelRow(title: "Turning back", detail: "What Flop does when you walk away.") {
                Button("Show") { model.previewReward() }
                    .buttonStyle(.shiftSoft)
            }
            PanelRow(title: "Full-screen block", detail: "The third reach in an hour.") {
                Button("Show") { model.previewShield() }
                    .buttonStyle(.shiftSoft)
            }
            PanelRow(title: "Drift hint", detail: "The quiet card, for mild drift. Never escalates.") {
                Button("Show") { model.previewHint() }
                    .buttonStyle(.shiftSoft)
            }
        }
    }

    private var detection: some View {
        Panel("How blocking works", icon: "scope", tint: .purple) {
            Text("Shift checks the current app and browser address against your enabled blocks. A rule can match a whole website, a path like YouTube Shorts, or an app. The moment a match appears, usually before the page has loaded, Shift covers that window with a pause: one breath, then a question about what you were really after, and something better to do instead. A second reach within the hour gets a longer pause. The third covers the screen.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PanelRow(
                title: "Screen Recording",
                detail: "Optional. Helps Shift read the frontmost window for focus reminders when Accessibility text is limited."
            ) {
                if model.screenRecordingGranted {
                    Text("Granted").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Grant…") { model.requestScreenRecordingPermission() }
                        .buttonStyle(.shiftSoft)
                }
            }
        }
    }

    private var about: some View {
        Panel("Setup", icon: "sparkle", tint: .blue) {
            PanelRow(title: "Run first-time setup again") {
                Button("Open setup") { model.presentOnboarding() }
                    .buttonStyle(.shiftSoft)
            }
        }
    }
}
