import SwiftUI

/// The menu bar popover: see what's on, flip a block, get to the window.
///
/// Deliberately not a second copy of the app. Anything needing more than a switch lives
/// in the main window, and the popover is built from the same pieces as everything else
/// so it doesn't read as a system menu that wandered in.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            header

            Hairline()

            if model.store.blocks.isEmpty {
                emptyState
            } else {
                blockList
            }

            if model.isWatching, model.lastContext != nil {
                Hairline()
                LiveContextView()
            }

            if !model.accessibilityGranted {
                permissionWarning
            }

            Hairline()

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

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Space.tight) {
            BlockBadge(symbol: "shield.lefthalf.filled", tint: .indigo, size: 26)
            Text("Shift")
                .font(.system(.title3, design: .rounded).weight(.bold))
            Spacer()
            StatusPill(isActive: model.isWatching)
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Content

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            Text("No blocks yet")
                .font(.callout.weight(.semibold))
            Text("Start from a ready-made block, then make it yours.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                model.presentMainWindow(section: .blocks)
            } label: {
                Label("Browse blocks", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.shiftProminent)
        }
        .padding(.vertical, Theme.Space.hair)
    }

    private var blockList: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(model.store.blocks) { block in
                MenuBlockRow(block: block)
            }
        }
    }

    private var permissionWarning: some View {
        Button {
            model.requestAccessibilityPermission()
        } label: {
            HStack(alignment: .top, spacing: Theme.Space.tight) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Accessibility is off")
                        .font(.caption.weight(.semibold))
                    Text("Website rules and accessible page text need this permission.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Space.tight)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            Button {
                model.presentMainWindow()
            } label: {
                Label("Open Shift", systemImage: "macwindow")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.shiftSoft)
            .controlSize(.small)

            Spacer()

            IconButton(symbol: "gearshape.fill", help: "Settings") {
                model.presentMainWindow(section: .settings)
            }

            IconButton(
                symbol: "power",
                help: model.canQuitApp ? "Quit Shift" : "A locked block is running: Shift can't be quit",
                tint: model.canQuitApp ? nil : .orange,
                isDisabled: !model.canQuitApp
            ) {
                NSApp.terminate(nil)
            }
        }
    }
}

// MARK: - Block row

/// A compact block row with the switch, matching what the main window shows.
private struct MenuBlockRow: View {
    @Environment(AppModel.self) private var model
    let block: Block

    @State private var isHovering = false

    private var isActive: Bool { block.isActive() }

    var body: some View {
        HStack(spacing: Theme.Space.snug) {
            BlockBadge(symbol: block.symbol, tint: block.tint, size: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(block.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(statusLine)
                    .font(.caption2)
                    .foregroundStyle(block.isLocked() ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.tight)

            ShiftSwitch(
                isOn: .constant(block.isEnabled),
                isLocked: block.isLocked(),
                action: { toggle(to: $0) }
            )
            .scaleEffect(0.8)
            .frame(width: 42)
            .disabled(block.canStartTimedRun)
        }
        .padding(.horizontal, Theme.Space.tight)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.05) : .clear)
        }
        .overlay(alignment: .leading) {
            // A quiet mark that this block is the reason Shift is watching.
            if isActive {
                Capsule()
                    .fill(block.tint.color)
                    .frame(width: 2.5, height: 18)
                    .offset(x: -5)
            }
        }
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture { model.presentMainWindow(section: .blocks) }
        .contextMenu {
            TimedBlockActions(block: block)
            Button("Open Blocks") { model.presentMainWindow(section: .blocks) }
        }
    }

    private var statusLine: String {
        if block.isLocked() { return block.lockStatus() }
        if isActive { return "Active · \(block.contentsSummary)" }
        return block.scheduleSummary
    }

    private func toggle(to enabled: Bool) {
        switch model.store.setEnabled(enabled, for: block.id) {
        case .changed:
            break
        case .needsRandomString:
            model.requestBlockUnlock(id: block.id)
        case .refusedLocked, .needsTimedStart:
            model.presentMainWindow(section: .blocks)
        }
    }
}

private struct TimedBlockActions: View {
    @Environment(AppModel.self) private var model
    let block: Block

    var body: some View {
        if block.canStartTimedRun {
            ForEach([25, 50, 90], id: \.self) { minutes in
                Button("Start for \(minutes) minutes") {
                    if model.store.startManualRun(id: block.id, minutes: minutes) {
                        model.log("Started \(block.name) for \(minutes) minutes", symbol: "timer")
                    }
                }
            }
        }
    }
}

// MARK: - What Shift sees

private struct LiveContextView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            Text("What Shift sees")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            if let context = model.lastContext {
                HStack(spacing: Theme.Space.tight) {
                    if let verdict = model.lastVerdict {
                        VerdictPill(kind: verdict.kind)
                    }
                    Text(context.displayLocation)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }

                if let verdict = model.lastVerdict {
                    Text("\(verdict.source.rawValue) · \(verdict.reason)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Theme.Space.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
    }
}
