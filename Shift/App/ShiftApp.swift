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
/// HIG: menu bar extras stay narrow and monochrome so they sit correctly next to the
/// system's own items. The icon carries the state, and a running session adds the minutes
/// left, which is the one number worth a glance without opening anything.
private struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        if let session = model.session {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(spacing: 3) {
                    Image(systemName: symbol(for: session))
                    Text(minutesLeft(of: session, at: context.date))
                        .monospacedDigit()
                }
                .accessibilityLabel("Shift: \(minutesLeft(of: session, at: context.date)) minutes left")
            }
        } else {
            Image(systemName: "scope")
                .accessibilityLabel("Shift: no session running")
        }
    }

    private func symbol(for session: FocusSession) -> String {
        session.strictness == .locked ? "lock.fill" : "scope"
    }

    private func minutesLeft(of session: FocusSession, at date: Date) -> String {
        let minutes = Int((session.remaining(at: date) / 60).rounded(.up))
        return "\(max(minutes, 0))m"
    }
}
