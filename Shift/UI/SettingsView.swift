import SwiftUI

/// Settings, as a pane in the main window rather than a separate window.
///
/// Everything Shift can be configured with now lives behind one sidebar, so there is only
/// ever one Shift window on screen. The three groups that used to be tabs are sections of
/// a single form, which reads better in a detail pane than nested tabs would.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            GeneralSettingsView()
            PermissionsSettingsView()
            IntelligenceSettingsView()
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear { model.refreshSystemState() }
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            Section {
                Toggle("Open Shift at login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .help("Registers Shift as a login item so it's running before you need it.")

                if LaunchAtLogin.requiresApproval {
                    LabeledContent("Needs approval") {
                        Button("Open Login Items…") { LaunchAtLogin.openLoginItemsSettings() }
                    }
                }

                Toggle("Show Shift in the Dock", isOn: $model.showInDock)
                    .help("Shift is a menu bar app and hides from the Dock by default.")
            } header: {
                Text("Startup")
            } footer: {
                Text("A blocker that isn't running blocks nothing. Shift lives in the menu bar, and hides from the Dock unless you ask for it.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show nudges", isOn: $model.showNudges)
                    .help("A small HUD for mild drift. It never covers the screen.")
                LabeledContent("Preview") {
                    Button("Show a nudge") { model.previewNudge() }
                }
            } header: {
                Text("Nudges")
            } footer: {
                Text("Nudges appear for uncertain or mild drift and fade on their own. Only confident blocks raise the shield.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Keep the watchdog running at all times", isOn: $model.keepWatchdogAlways)
                    .help("Otherwise the watchdog is installed only while a Locked session runs.")
                LabeledContent("Watchdog") {
                    Label(
                        model.watchdogInstalled ? "Installed" : "Not installed",
                        systemImage: model.watchdogInstalled ? "checkmark.circle.fill" : "circle.dashed"
                    )
                    .foregroundStyle(model.watchdogInstalled ? .green : .secondary)
                    .labelStyle(.titleAndIcon)
                }
            } header: {
                Text("Locked sessions")
            } footer: {
                Text("During a Locked session, Shift refuses to quit, a background watchdog relaunches it if it's killed, and the app is put back if it's moved to the Trash. An admin can still win with enough determination. Shift sells friction, not a prison.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Blocks") {
                    Button("Open Shift…") { model.presentMainWindow() }
                }
                LabeledContent("Setup") {
                    Button("Run setup again…") { model.presentOnboarding() }
                }
            } footer: {
                Text("Walks through the distraction picker, permissions and the demo shield again.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Permissions

private struct PermissionsSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            Section {
                permissionRow(
                    title: "Accessibility",
                    detail: "Reads the frontmost window's title and the page you're on. This is the one permission Shift needs to work.",
                    granted: model.accessibilityGranted,
                    actionTitle: "Open…",
                    action: PermissionsManager.openAccessibilitySettings
                )
                permissionRow(
                    title: "Automation (browsers)",
                    detail: "Closes a distracting tab when you act on a shield. Asked once per browser, the first time a tab actually needs closing.",
                    granted: nil,
                    actionTitle: "Open…",
                    action: PermissionsManager.openAutomationSettings
                )
                permissionRow(
                    title: "Screen Recording",
                    detail: "Only needed by blocks that use on-screen words. Everything else works without it.",
                    granted: model.screenRecordingGranted,
                    actionTitle: model.screenRecordingGranted ? nil : "Grant…",
                    action: model.screenRecordingGranted ? nil : { model.requestScreenRecordingPermission() }
                )
            } header: {
                Text("Permissions")
            } footer: {
                Text("Everything Shift reads stays on this Mac. Nothing is written to disk and nothing is uploaded.")
                    .foregroundStyle(.secondary)
            }

            if !model.accessibilityGranted {
                Section {
                    Label(
                        "If Shift already looks enabled in System Settings, remove it from the Accessibility list with the minus button, then add it again. macOS ties the permission to the app's signature, so a rebuilt or replaced copy needs a fresh grant.",
                        systemImage: "lightbulb"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Granted it but still not working?")
                }
            }
        }
        .onAppear { model.refreshPermissions() }
        .task {
            while !Task.isCancelled {
                model.refreshPermissions()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func permissionRow(
        title: String,
        detail: String,
        granted: Bool?,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.snug) {
            VStack(alignment: .leading, spacing: Theme.Space.hair) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.tight)
            if let granted {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(granted ? .green : .orange)
                    .accessibilityLabel(granted ? "Granted" : "Not granted")
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .padding(.vertical, Theme.Space.hair)
    }
}

// MARK: - Intelligence

private struct IntelligenceSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            Section {
                tierRow(
                    "Rules",
                    detail: "Window titles, addresses and path-aware rules, across every active block. Instant, and needs nothing installed.",
                    status: "Active",
                    isActive: true
                )
                tierRow(
                    "On-screen text",
                    detail: "Reads the frontmost window with screen capture and text recognition, so blocks can match words the address never mentions.",
                    status: model.screenRecordingGranted ? "Active" : "Needs permission",
                    isActive: model.screenRecordingGranted
                )
                tierRow(
                    "Page text",
                    detail: "Reads the page straight from the accessibility tree, which is exact and costs nothing.",
                    status: "Next",
                    isActive: false
                )
                tierRow(
                    "On-device model",
                    detail: "Judges the page against your goal using the model already built into macOS.",
                    status: "M2",
                    isActive: false
                )
                tierRow(
                    "Vision model",
                    detail: "For screens that are mostly video or images, where there's no text to read.",
                    status: "M4",
                    isActive: false
                )
            } header: {
                Text("Detection tiers")
            } footer: {
                Text("Shift works cheapest-first: rules settle most cases without waking anything larger. There is no model to download and no account, because the on-device model ships with macOS.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tierRow(_ title: String, detail: String, status: String, isActive: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.snug) {
            VStack(alignment: .leading, spacing: Theme.Space.hair) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.tight)
            Text(status)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, Theme.Space.tight)
                .padding(.vertical, Theme.Space.hair)
                .background(
                    (isActive ? Color.green : Color.secondary).opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(isActive ? .green : .secondary)
        }
        .padding(.vertical, Theme.Space.hair)
    }
}
