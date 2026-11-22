import SwiftUI

@main
struct ShiftApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            Image(systemName: model.session == nil ? "scope" : "lock.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
