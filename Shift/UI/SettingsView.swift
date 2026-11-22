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
                lockedBlocks
                permissions
                detection
                about
            }
            .padding(Theme.Space.loose)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { model.refreshSystemState() }
        .task {
            while !Task.isCancelled {
                model.refreshPermissions()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: Sections

    private var startup: some View {
        @Bindable var model = model
        return Panel("Startup", icon: "power") {
            PanelRow(
                title: "Open Shift at login",
                detail: "A blocker that isn't running blocks nothing."
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
                detail: "Off by default. Shift lives in the menu bar."
            ) {
                ShiftSwitch(isOn: $model.showInDock)
            }
        }
    }

    private var nudges: some View {
        @Bindable var model = model
        return Panel(
            "Nudges",
            subtitle: "A small HUD for mild drift. It never covers the screen, and only confident blocks raise the shield.",
            icon: "arrow.turn.up.left"
        ) {
            PanelRow(title: "Show nudges") {
                ShiftSwitch(isOn: $model.showNudges)
            }
        }
    }

    private var previews: some View {
        Panel(
            "Previews",
            subtitle: "Feel each level of friction without waiting to be interrupted. Nothing is closed.",
            icon: "eye"
        ) {
            PanelRow(title: "Nudge", detail: "The quiet HUD, for mild drift.") {
                Button("Show") { model.previewNudge() }
                    .buttonStyle(.shiftSoft)
            }
            PanelRow(title: "Shield", detail: "Friction grows with each strike.") {
                HStack(spacing: Theme.Space.tight) {
                    ForEach(1...3, id: \.self) { strike in
                        Button("\(strike)") { model.previewShield(strike: strike) }
                            .buttonStyle(.shiftSoft)
                            .accessibilityLabel("Preview shield, strike \(strike)")
                    }
                }
            }
        }
    }

    private var lockedBlocks: some View {
        @Bindable var model = model
        return Panel(
            "Locked blocks",
            subtitle: "While a lock is engaged, Shift refuses to quit, a watchdog relaunches it if it's killed, and the app is put back if it's moved to the Trash. An admin can still win. Shift sells friction, not a prison.",
            icon: "lock.shield"
        ) {
            PanelRow(
                title: "Keep the watchdog running always",
                detail: "Otherwise it's installed only while a lock is engaged."
            ) {
                ShiftSwitch(isOn: $model.keepWatchdogAlways)
            }
            PanelRow(title: "Watchdog") {
                Label(
                    model.watchdogInstalled ? "Installed" : "Not installed",
                    systemImage: model.watchdogInstalled ? "checkmark.circle.fill" : "circle.dashed"
                )
                .font(.caption)
                .foregroundStyle(model.watchdogInstalled ? .green : .secondary)
                .labelStyle(.titleAndIcon)
            }
        }
    }

    private var permissions: some View {
        Panel(
            "Permissions",
            subtitle: "Everything Shift reads stays on this Mac. Nothing is written to disk and nothing is uploaded.",
            icon: "hand.raised"
        ) {
            PermissionLine(
                title: "Accessibility",
                detail: "Reads the frontmost window and the page you're on. The one permission Shift needs.",
                granted: model.accessibilityGranted,
                action: { model.requestAccessibilityPermission() }
            )
            PermissionLine(
                title: "Automation",
                detail: "Closes a distracting tab when you act on a shield. Asked once per browser.",
                granted: nil,
                action: { PermissionsManager.openAutomationSettings() }
            )
            PermissionLine(
                title: "Screen Recording",
                detail: "Not used yet. The intent tier will read on-screen text with it.",
                granted: model.screenRecordingGranted,
                action: { model.requestScreenRecordingPermission() }
            )

            if !model.accessibilityGranted {
                Text("If Shift already looks enabled in System Settings, remove it from the list with the minus button and add it again. macOS ties the permission to the app's signature, so a rebuilt copy needs a fresh grant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private var detection: some View {
        Panel(
            "Detection",
            subtitle: "Shift works cheapest-first. Rules settle nearly everything without waking anything larger.",
            icon: "sparkles"
        ) {
            TierLine(
                title: "Rules",
                detail: "Window titles, addresses and path-aware matching across every active block.",
                status: "Active",
                isActive: true
            )
            TierLine(
                title: "Page text",
                detail: "Reads the page from the accessibility tree. Exact, and costs nothing.",
                status: "Next",
                isActive: false
            )
            TierLine(
                title: "On-device model",
                detail: "Judges a page against a block's goal, using the model built into macOS.",
                status: "Planned",
                isActive: false
            )
        }
    }

    private var about: some View {
        Panel("Setup", icon: "sparkle") {
            PanelRow(title: "Run first-time setup again") {
                Button("Open setup") { model.presentOnboarding() }
                    .buttonStyle(.shiftSoft)
            }
        }
    }
}

// MARK: - Rows

private struct PermissionLine: View {
    let title: String
    let detail: String
    let granted: Bool?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.snug) {
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Space.tight)

            if granted != true {
                Button(granted == nil ? "Open" : "Grant", action: action)
                    .buttonStyle(.shiftSoft)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch granted {
        case true: "checkmark.circle.fill"
        case false: "exclamationmark.circle.fill"
        default: "minus.circle"
        }
    }

    private var color: Color {
        switch granted {
        case true: .green
        case false: .orange
        default: .secondary
        }
    }
}

private struct TierLine: View {
    let title: String
    let detail: String
    let status: String
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.snug) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.tight)
            StatusTag(text: status, tint: isActive ? .green : .secondary)
        }
        .padding(.vertical, 3)
    }
}
