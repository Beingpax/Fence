import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            RulesSettingsView()
                .tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }
            PermissionsSettingsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            ModelsSettingsView()
                .tabItem { Label("AI Models", systemImage: "cpu") }
        }
        .frame(width: 520, height: 440)
        .onAppear { NSApp.activate() }
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
    }

    private func listEditor(_ items: Binding<[String]>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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

// MARK: - Permissions

private struct PermissionsSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                permissionRow(
                    title: "Accessibility",
                    detail: "Reads window titles so Shift knows what you're looking at.",
                    granted: model.accessibilityGranted,
                    action: PermissionsManager.openAccessibilitySettings
                )
                permissionRow(
                    title: "Automation (browsers)",
                    detail: "Reads the current tab's address and closes distracting tabs. Asked once per browser.",
                    granted: nil,
                    action: PermissionsManager.openAutomationSettings
                )
                permissionRow(
                    title: "Screen Recording",
                    detail: "Coming with the AI tier: reads on-screen text locally. Nothing is saved or uploaded.",
                    granted: nil,
                    action: nil
                )
            } footer: {
                Text("Everything Shift sees stays on this Mac.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshPermissions() }
    }

    private func permissionRow(title: String, detail: String, granted: Bool?, action: (() -> Void)?) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let granted {
                Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(granted ? .green : .red)
            }
            if let action {
                Button("Open…", action: action)
            }
        }
    }
}

// MARK: - Models

private struct ModelsSettingsView: View {
    var body: some View {
        Form {
            Section {
                modelRow("Rules engine", detail: "Built in. Works with no download.", status: "Active")
                modelRow("Intent classifier", detail: "~300 MB · judges your screen against your goal", status: "Coming in M2")
                modelRow("Vision model", detail: "~1 GB · for video and image-heavy screens", status: "Coming in M4")
            } footer: {
                Text("Models download once, run entirely on Apple Silicon, and never send data anywhere.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func modelRow(_ title: String, detail: String, status: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(status)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
