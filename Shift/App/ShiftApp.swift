import SwiftUI

struct ShiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
        // Settings is a section of the main window, not a second window. Cmd+, still
        // works and opens the window there.
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    model.presentMainWindow(section: .settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// The status item itself.
///
/// HIG: menu bar extras stay narrow and monochrome. The icon carries the state, and the
/// count of active blocks is the one number worth a glance without opening anything.
private struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let active = model.store.activeBlocks.count
        HStack(spacing: 3) {
            Image(systemName: symbol(activeCount: active))
                .symbolRenderingMode(.monochrome)
            if active > 0 {
                Text("\(active)").monospacedDigit()
            }
        }
        .accessibilityLabel(statusLabel(activeCount: active))
    }

    private func statusLabel(activeCount: Int) -> String {
        if activeCount > 0 {
            return "Shift, \(activeCount) block\(activeCount == 1 ? "" : "s") active"
        }
        return model.store.hasLockedBlock ? "Shift, lock active" : "Shift, idle"
    }

    private func symbol(activeCount: Int) -> String {
        if model.store.hasLockedBlock { return "lock.circle.fill" }
        return activeCount > 0 ? "viewfinder.circle.fill" : "scope"
    }
}
