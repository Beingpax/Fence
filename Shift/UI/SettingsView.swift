import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            RulesSettingsView()
                .tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }
            PermissionsSettingsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            IntelligenceSettingsView()
                .tabItem { Label("Intelligence", systemImage: "sparkles") }
        }
        .frame(width: Theme.settingsSize.width, height: Theme.settingsSize.height)
        .onAppear { NSApp.activate() }
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
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
            } header: {
                Text("Startup")
            } footer: {
                Text("A blocker that isn't running blocks nothing. Shift has no Dock icon; it lives in the menu bar.")
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
                LabeledContent("Setup") {
                    Button("Run setup again…") { model.presentOnboarding() }
                }
            } footer: {
                Text("Walks through the distraction picker, permissions and the demo shield again.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshSystemState() }
    }
}

// MARK: - Rules

private struct RulesSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Blocked sites") {
                listEditor($model.rules.blockedHosts, hint: "One per line, e.g. instagram.com")
            }
            Section("Blocked parts of sites") {
                listEditor($model.rules.blockedPaths, hint: "e.g. youtube.com/shorts keeps the rest of YouTube")
            }
            Section("Blocked apps (bundle IDs)") {
                listEditor($model.rules.blockedApps, hint: "e.g. com.hnc.Discord")
            }
            Section {
                Button("Restore defaults") { model.rules = .default }
                    .disabled(model.session != nil)
            } footer: {
                Text("Rules can't be changed back to defaults during a session.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .disabled(model.session?.strictness == .locked)
        .overlay {
            if model.session?.strictness == .locked {
                LockedOverlay()
            }
        }
    }

    private func listEditor(_ items: Binding<[String]>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.hair + 2) {
            TextEditor(text: Binding(
                get: { items.wrappedValue.joined(separator: "\n") },
                set: { text in
                    items.wrappedValue = text
                        .split(whereSeparator: \.isNewline)
                        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                        .filter { !$0.isEmpty }
                }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 70)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Shown over the rules while a Locked session runs, so the reason is obvious
/// rather than the controls just being mysteriously dead.
private struct LockedOverlay: View {
    var body: some View {
        VStack(spacing: Theme.Space.snug) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
            Text("Rules are frozen during a Locked session.")
                .font(.headline)
            Text("You chose this. It ends when the timer does.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(Theme.Space.loose)
        .glassCard(radius: Theme.Radius.panel)
        .padding(Theme.Space.wide)
    }
}

// MARK: - Permissions

private struct PermissionsSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
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
                    detail: "Optional, and only used by the on-screen text reader arriving in M2. Shift works fully without it.",
                    granted: nil,
                    actionTitle: nil,
                    action: nil
                )
            } header: {
                Text("Permissions")
            } footer: {
                Text("Everything Shift reads stays on this Mac. Nothing is written to disk and nothing is uploaded.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
    var body: some View {
        Form {
            Section {
                tierRow(
                    "Rules",
                    detail: "Window titles, addresses and path-aware rules. Instant, and works with nothing installed.",
                    status: "Active",
                    isActive: true
                )
                tierRow(
                    "Page text",
                    detail: "Reads the page through the accessibility tree, with on-screen text recognition as the fallback.",
                    status: "M2",
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
        .formStyle(.grouped)
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
