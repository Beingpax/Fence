import ServiceManagement
import SwiftUI

struct BlockingPermissionRow: View {
    enum Permission {
        case browserAccess, backgroundBlocking, openAtLogin
    }

    @Environment(AppModel.self) private var model
    private let permission: Permission
    private let inPanel: Bool

    init(_ permission: Permission, inPanel: Bool = false) {
        self.permission = permission
        self.inPanel = inPanel
    }

    var body: some View {
        let feedback = Self.feedback(for: permission, model: model)
        let tint: Color = feedback.action == nil ? Paper.mint : .orange
        let content = row(detail: feedback.detail, action: feedback.action, tint: tint)
        if inPanel {
            content.padding(.vertical, 2)
        } else {
            content.glassSurface(padding: Theme.Space.snug, tint: tint)
        }
    }

    private func row(detail: String, action: (title: String, perform: () -> Void)?, tint: Color) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.snug) {
            Image(systemName: action == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(for: permission)).font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.tight)
            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(.shiftSoft)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Shared with onboarding, which draws the same status in its own design.
    static func title(for permission: Permission) -> String {
        switch permission {
        case .browserAccess: PermissionsManager.BrowserAccessPane.current.rawValue
        case .backgroundBlocking: "Background blocking"
        case .openAtLogin: "Open Shift at login"
        }
    }

    /// What to say about a permission, and the one action that fixes it (nil when it's fine).
    /// Shared with onboarding, which draws the same status in its own design.
    static func feedback(
        for permission: Permission,
        model: AppModel
    ) -> (detail: String, action: (title: String, perform: () -> Void)?) {
        switch permission {
        case .browserAccess:
            if !model.browserAccessNeedsAttention {
                return ("Shift can request browser addresses and send the Close Tab shortcut. Browser-specific limits set by macOS still apply.", nil)
            }
            let pane = PermissionsManager.BrowserAccessPane.current
            let detail = model.accessibilityGranted
                ? "Shift can check browser addresses. Automatic tab closing needs keyboard control. "
                : "Shift uses browser access to read addresses and close blocked tabs. "
            return (detail + pane.setupInstructions, ("Open Settings", model.requestBrowserAccess))
        case .backgroundBlocking:
            switch model.backgroundServiceStatus {
            case .enabled where model.backgroundServiceOffline:
                // Login Items can't help here: the switch there is already on. Shift reloads
                // the helper on its own every two minutes; the button does it now.
                return ("Allowed, but the helper isn’t running. Shift is bringing it back; keep Shift open until then.",
                        ("Restart helper", model.restartBackgroundHelper))
            case .enabled:
                return ("Allowed. Keeps your blocks active if you Force Quit Shift.", nil)
            case .requiresApproval:
                return ("Turn on Shift under App Background Activity to keep your blocks active after Force Quit.",
                        ("Open Login Items", model.enableBackgroundBlocking))
            case .notRegistered where !model.backgroundRegistrationFailed,
                 .notFound where !model.backgroundRegistrationFailed:
                return ("Enable this to keep your blocks active if you Force Quit Shift.",
                        ("Enable background blocking", model.enableBackgroundBlocking))
            default:
                return ("The background helper couldn’t start. Try again to set it up.",
                        ("Try again", model.enableBackgroundBlocking))
            }
        case .openAtLogin:
            return ("Allow Shift under Open at Login to start it when you sign in.",
                    ("Open Login Items", LaunchAtLogin.openLoginItemsSettings))
        }
    }
}
