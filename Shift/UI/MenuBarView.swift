import SwiftUI

/// The menu bar popover: see what's on, flip a block, get to the window.
///
/// Deliberately not a second copy of the app. Anything that needs more than a switch
/// lives in the main window.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.base) {
            header

            Divider()

            if model.store.blocks.isEmpty {
                emptyState
            } else {
                blockList
            }

            if model.isWatching {
                Divider()
                LiveContextView()
            }

            Divider()

            footer
        }
        .padding(Theme.Space.base)
        .frame(width: Theme.menuWidth)
        .background {
            VisualEffect(surface: .window, blending: .behindWindow).ignoresSafeArea()
        }
        .onAppear {
            model.refreshPermissions()
            model.refreshSystemState()
        }
        .task {
            while !Task.isCancelled {
                model.refreshPermissions()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Shift")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(model.isWatching ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                Text(model.isWatching ? "Watching" : "Idle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            Text("No blocks yet")
                .font(.callout.weight(.medium))
            Text("Create one in the main window.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Shift") { model.presentMainWindow() }
                .buttonStyle(.shiftProminent)
                .frame(maxWidth: .infinity)
        }
    }

    private var blockList: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            SectionLabel(text: "Blocks")
            ForEach(model.store.blocks) { block in
                MenuBlockRow(block: block)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Space.tight) {
            Button("Open Shift") { model.presentMainWindow() }
                .buttonStyle(.plain)
                .font(.callout.weight(.medium))
                .foregroundStyle(.tint)

            Spacer()

            Menu {
                ForEach(1...3, id: \.self) { strike in
                    Button("Shield · strike \(strike)") { model.previewShield(strike: strike) }
                }
                Button("Nudge") { model.previewNudge() }
            } label: {
                Image(systemName: "eye")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Preview")

            Button {
                model.presentMainWindow(section: .settings)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Settings")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .disabled(!model.canQuitApp)
            .help(model.canQuitApp ? "Quit Shift" : "A locked block is running: Shift can't be quit")
            .accessibilityLabel("Quit Shift")
        }
        .font(.callout)
    }
}

/// A compact block row with the switch, matching what the main window shows.
private struct MenuBlockRow: View {
    @Environment(AppModel.self) private var model
    let block: Block

    @State private var refused = false

    var body: some View {
        HStack(spacing: Theme.Space.snug) {
            BlockBadge(symbol: block.symbol, tint: block.tint, size: 24, isActive: block.isActive())

            VStack(alignment: .leading, spacing: 0) {
                Text(block.name)
                    .font(.callout)
                    .lineLimit(1)
                Text(statusLine)
                    .font(.caption2)
                    .foregroundStyle(block.lock.isLocked() ? .orange : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.tight)

            ShiftSwitch(
                isOn: .constant(block.isEnabled),
                tint: block.tint.color,
                isLocked: block.lock.isLocked(),
                action: { toggle(to: $0) }
            )
            .scaleEffect(0.82)
            .accessibilityLabel("\(block.name) enabled")
        }
        .help(refused ? block.lock.statusText() : block.contentsSummary)
    }

    private var statusLine: String {
        if block.lock.isLocked() { return block.lock.statusText() }
        if block.isActive() { return "Active · \(block.contentsSummary)" }
        return block.scheduleSummary
    }

    private func toggle(to enabled: Bool) {
        switch model.store.setEnabled(enabled, for: block.id) {
        case .changed:
            refused = false
        case .refusedLocked, .needsRandomString:
            // Unlocking needs the main window, where there's room to explain it.
            refused = true
            model.presentMainWindow()
        }
    }
}

// MARK: - What Shift sees

private struct LiveContextView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            SectionLabel(text: "What Shift sees")

            if let context = model.lastContext {
                FieldRow(label: "App", value: context.appName)
                if let title = context.windowTitle {
                    FieldRow(label: "Window", value: title)
                }
                if let page = context.hostAndPath {
                    FieldRow(label: "Page", value: page)
                }
                if let verdict = model.lastVerdict {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.tight) {
                        VerdictPill(kind: verdict.kind)
                        Text(verdict.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("Waiting for the first reading…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !model.accessibilityGranted {
                Button {
                    model.requestAccessibilityPermission()
                } label: {
                    Label("Grant Accessibility so Shift can see where you are", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.orange)
            }
        }
    }
}
