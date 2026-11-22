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

        Settings {
            SettingsView()
                .environment(model)
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
            if active > 0 {
                Text("\(active)").monospacedDigit()
            }
        }
        .accessibilityLabel(
            active == 0
                ? "Shift: nothing blocked"
                : "Shift: \(active) block\(active == 1 ? "" : "s") active"
        )
    }

    private func symbol(activeCount: Int) -> String {
        if model.store.hasLockedBlock { return "lock.fill" }
        return activeCount > 0 ? "shield.lefthalf.filled" : "shield"
    }
}
