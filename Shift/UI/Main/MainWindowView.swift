import AppKit
import SwiftUI

/// Sections of the main window. Settings is one of these rather than a separate window:
/// a menu bar app with two windows is one window too many.
enum MainSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, blocks, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .blocks: "Blocks"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2.fill"
        case .blocks: "shield.lefthalf.filled"
        case .settings: "gearshape.fill"
        }
    }

    /// Vivid, saturated colours: these sit on the icon tile, not behind the row, so they
    /// need to carry on their own.
    var tint: Color {
        switch self {
        case .dashboard: Color(nsColor: .systemOrange)
        case .blocks: Color(nsColor: .systemIndigo)
        case .settings: Color(nsColor: .systemGray)
        }
    }
}

/// The main window.
///
/// Layout follows IINA: a translucent sidebar on the left, content in the middle, and an
/// inspector that slides in from the trailing edge for editing. Nothing is modal, so the
/// list stays visible and selected while a block is being changed.
struct MainWindowView: View {
    @Environment(AppModel.self) private var model

    @State private var selectedBlockID: Block.ID?
    @State private var isInspectorPresented = false
    @State private var inspectorDismissalRequest = 0

    var body: some View {
        @Bindable var model = model

        HStack(spacing: 0) {
            Sidebar()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Theme.detailBackground.ignoresSafeArea(.container, edges: .top)
                }
        }
        .slidingPanel(isPresented: $isInspectorPresented, width: 420, onOutsideClick: {
            inspectorDismissalRequest += 1
        }) {
            inspector
        }
        .onChange(of: isInspectorPresented) { _, presented in
            if !presented {
                selectedBlockID = nil
                model.newBlock = nil
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .background {
            Theme.workspaceBackground.ignoresSafeArea(.container, edges: .top)
        }
        // Content runs to the very top of the window, under the hidden title bar.
        // Without this the sidebar and the panel both stop short of the traffic lights.
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: model.newBlock?.id, initial: true) { _, id in
            guard id != nil else { return }
            selectedBlockID = nil
            isInspectorPresented = true
        }
        .sheet(item: $model.unlockTarget) { block in
            RandomStringUnlockView(block: block)
        }
    }

    private func selectBlock(_ block: Block) {
        model.newBlock = nil
        selectedBlockID = block.id
        isInspectorPresented = true
    }

    @ViewBuilder
    private var detail: some View {
        switch model.mainSection {
        case .dashboard:
            DashboardView(
                onAddBlock: model.presentNewBlock,
                onSelect: selectBlock
            )
        case .blocks:
            BlocksView(
                onSelect: selectBlock,
                onAddBlock: model.presentNewBlock
            )
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let block = model.newBlock ?? selectedBlockID.flatMap({ model.store.block(id: $0) }) {
            BlockInspector(block: block, isNew: model.newBlock != nil, dismissalRequest: inspectorDismissalRequest) {
                isInspectorPresented = false
            }
            .id(block.id)
        } else {
            ContentUnavailableView(
                "Nothing selected",
                systemImage: "sidebar.right",
                description: Text("Pick a block to edit it here.")
            )
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Environment(AppModel.self) private var model

    private let navigationSections = MainSection.allCases.filter { $0 != .settings }

    var body: some View {
        AppSidebar {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: SidebarLayout.rowSpacing) {
                    ForEach(navigationSections) { section in
                        SidebarRow(
                            title: section.title,
                            systemImage: section.symbol,
                            iconColor: section.tint,
                            isSelected: model.mainSection == section
                        ) {
                            model.mainSection = section
                        }
                    }
                }
                .padding(.horizontal, SidebarLayout.horizontalInset)
                .padding(.top, SidebarLayout.topInset)

                Spacer(minLength: 16)

                SidebarRow(
                    title: MainSection.settings.title,
                    systemImage: MainSection.settings.symbol,
                    iconColor: MainSection.settings.tint,
                    isSelected: model.mainSection == .settings
                ) {
                    model.mainSection = .settings
                }
                .padding(.horizontal, SidebarLayout.horizontalInset)
                .padding(.bottom, SidebarLayout.bottomInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Blocks

struct BlocksView: View {
    @Environment(AppModel.self) private var model
    let onSelect: (Block) -> Void
    let onAddBlock: () -> Void

    private var subtitle: String {
        let active = model.store.activeBlocks.count
        let total = model.store.blocks.count
        if active == 0 { return "\(total) block\(total == 1 ? "" : "s"), none active" }
        return "\(active) of \(total) active right now"
    }

    var body: some View {
        Group {
            if model.store.blocks.isEmpty {
                VStack(spacing: Theme.Space.base) {
                    PageHeader("Blocks")
                    EmptyBlocksView(onAddBlock: onAddBlock)
                }
                .mainPageInsets()
            } else {
                list
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Space.snug) {
                PageHeader("Blocks", subtitle: subtitle) {
                    Button(action: onAddBlock) {
                        Label("New block", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.shiftProminent)
                }
                .padding(.bottom, Theme.Space.tight)

                ForEach(model.store.blocks) { block in
                    BlockCard(
                        block: block,
                        onSelect: { onSelect(block) }
                    )
                }

                Button(action: onAddBlock) {
                    Label("Add a block", systemImage: "plus")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Space.base)
                        // The whole dashed card is the button, not just its label.
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .strokeBorder(
                                    Color.primary.opacity(0.14),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                                )
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, Theme.Space.tight)
            }
            .mainPageInsets()
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// One block as a card: badge, name, what and when, lock state, and the switch.
struct BlockCard: View {
    @Environment(AppModel.self) private var model
    let block: Block
    let onSelect: () -> Void

    @State private var showingLockedNotice = false

    private var isActive: Bool { block.isActive() }
    private var isLocked: Bool { block.isLocked() }

    var body: some View {
        HStack(spacing: Theme.Space.base) {
            BlockBadge(symbol: block.symbol, tint: block.tint, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Theme.Space.tight) {
                    Text(block.name)
                        .font(.system(.headline, design: .rounded))
                    if isActive {
                        StatusTag(text: "Active", tint: .green)
                    }
                    if block.breaks.isOnBreak() {
                        StatusTag(text: "On a break", tint: .orange)
                    }
                }

                Text(block.contentsSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: Theme.Space.tight) {
                    Label(block.scheduleSummary, systemImage: scheduleSymbol)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if isLocked, !block.requiresUnlockChallenge() {
                        Label(block.lockStatus(), systemImage: "lock.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
                .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: Theme.Space.snug)

            ShiftSwitch(
                isOn: .constant(block.isEnabled),
                isLocked: isLocked,
                action: { toggle(to: $0) }
            )
            .accessibilityLabel("\(block.name) enabled")
            .disabled(block.canStartTimedRun)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .glassSurface()
        .contextMenu {
            Button("Edit", action: onSelect)
            Divider()
            Button("Delete", role: .destructive) {
                if !model.store.delete(id: block.id) { showingLockedNotice = true }
            }
            .disabled(isLocked)
        }
        .alert("“\(block.name)” is locked", isPresented: $showingLockedNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(block.lockStatus())
        }
    }

    private var scheduleSymbol: String {
        switch block.schedule {
        case .always: "infinity"
        case .scheduled: "calendar"
        case .manual: "play.circle"
        }
    }

    private func toggle(to enabled: Bool) {
        switch model.store.setEnabled(enabled, for: block.id) {
        case .changed:
            model.log("\(block.name) \(enabled ? "on" : "off")", symbol: enabled ? "shield.fill" : "shield.slash")
        case .refusedLocked:
            showingLockedNotice = true
        case .needsRandomString:
            model.requestBlockUnlock(id: block.id)
        case .needsTimedStart:
            break
        }
    }
}

struct StatusTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }
}

// MARK: - Empty state

private struct EmptyBlocksView: View {
    let onAddBlock: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.base) {
            BlockBadge(symbol: "shield.lefthalf.filled", tint: .indigo, size: 60)
                .shadow(color: .indigo.opacity(0.25), radius: 16, y: 6)

            VStack(spacing: Theme.Space.tight) {
                Text("Create your first block")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text("Choose which sites and apps to block.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button(action: onAddBlock) {
                Label("Add a block", systemImage: "plus")
            }
            .buttonStyle(.shiftProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Random string unlock

struct RandomStringUnlockView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let block: Block

    private enum Feedback {
        case mismatch(Int)
        case incomplete
        case extra
        case unavailable
    }

    @State private var challenge = ""
    @State private var typed = ""
    @State private var result: Feedback?
    @State private var isEntryFocused = false
    @State private var entryFocusRequest = 0

    private var tint: Color { block.tint.color }
    private var revealedMismatch: Int? {
        if case let .mismatch(index) = result { return index }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.loose) {
            HStack(spacing: Theme.Space.base) {
                BlockBadge(symbol: block.symbol, tint: block.tint, size: 50)

                VStack(alignment: .leading, spacing: Theme.Space.hair) {
                    Text("Unlock \(block.name)")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Type the code exactly as shown. Use Backspace to erase from the end.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                codeTiles

                codeEntry

                feedback
                    .font(.caption)
            }

            HStack {
                Button("Keep blocking") { dismiss() }
                    .buttonStyle(.shiftSoft)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: attempt) {
                    Label("Unlock", systemImage: "lock.open")
                }
                .buttonStyle(.shiftProminent(tint))
                .keyboardShortcut(.defaultAction)
                .disabled(challenge.isEmpty)
            }
        }
        .padding(Theme.Space.wide)
        .frame(width: 488)
        .background {
            VisualEffect(surface: .window, blending: .behindWindow).ignoresSafeArea()
        }
        .onAppear {
            if let code = model.store.createUnlockChallenge(for: block.id) {
                challenge = code
            } else {
                dismiss()
            }
        }
    }

    private var codeEntry: some View {
        let border: Color = result != nil ? .red : (isEntryFocused ? tint : Color.primary.opacity(0.12))

        return HStack(spacing: Theme.Space.snug) {
            Image(systemName: "keyboard")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            HStack(spacing: 3) {
                if typed.isEmpty {
                    Text("Type the code here")
                        .foregroundStyle(.secondary)
                } else {
                    Text(verbatim: typed.replacingOccurrences(of: " ", with: "␣"))
                        .truncationMode(.head)
                }

                if isEntryFocused {
                    Capsule()
                        .fill(tint)
                        .frame(width: 2, height: 15)
                }
            }
            .font(.system(.body, design: .monospaced))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
        }
        .padding(Theme.Space.snug)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .strokeBorder(border, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay {
            ChallengeKeyInput(
                focusRequest: entryFocusRequest,
                value: typed,
                onFocusChange: { isEntryFocused = $0 },
                onEdit: editEntry
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var codeTiles: some View {
        let characters = Array(challenge)
        let enteredCount = typed.count
        let mismatch = revealedMismatch
        let columns = 16
        let tileHeight: CGFloat = 28
        let gap: CGFloat = 4
        let rows = min(8, max(1, (characters.count + columns - 1) / columns))

        return ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(22), spacing: gap), count: columns),
                alignment: .leading,
                spacing: gap
            ) {
                ForEach(characters.indices, id: \.self) { index in
                    let isEntered = index < enteredCount
                    let isWrong = index == mismatch
                    let tileColor: Color = isWrong ? .red : .green
                    let outline: Color = isWrong ? .red : (index == enteredCount ? tint : .clear)
                    Text(String(characters[index]))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .frame(width: 22, height: tileHeight)
                        .background {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isEntered ? tileColor.opacity(0.18) : Color.primary.opacity(0.06))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(outline, lineWidth: 1)
                        }
                        .overlay(alignment: .bottom) {
                            if isEntered {
                                Capsule()
                                    .fill(tileColor)
                                    .frame(width: 10, height: 2)
                                    .padding(.bottom, 2)
                            }
                        }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .textSelection(.disabled)
        .frame(height: CGFloat(rows) * tileHeight + CGFloat(rows - 1) * gap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(challenge).speechSpellsOutCharacters())
    }

    @ViewBuilder
    private var feedback: some View {
        switch result {
        case .unavailable:
            Label("This block can’t be unlocked right now.", systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
        case .extra:
            Label("Remove the extra characters.", systemImage: "exclamationmark.circle")
        case .mismatch(let index):
            Label("Backspace through character \(index + 1), then retype from there.", systemImage: "exclamationmark.circle")
        case .incomplete:
            let remaining = challenge.count - typed.count
            Label("Finish typing the code. \(remaining) left.", systemImage: "exclamationmark.circle")
        case nil:
            Text("\(typed.count) of \(challenge.count) characters entered")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func editEntry(_ edit: ChallengeKeyInput.Edit) {
        switch edit {
        case .append(let character):
            typed.append(character)
        case .backspace:
            guard !typed.isEmpty else { return }
            typed.removeLast()
        }

        // Keep the submitted error visible until that character has been erased.
        if let revealedMismatch, revealedMismatch < typed.count { return }
        result = nil
    }

    private func attempt() {
        guard !challenge.isEmpty else { return }
        let matched = zip(challenge, typed).prefix { $0.0 == $0.1 }.count
        if matched < min(challenge.count, typed.count) {
            result = .mismatch(matched)
        } else if typed.count < challenge.count {
            result = .incomplete
        } else if typed.count > challenge.count {
            result = .extra
        } else if model.store.unlockWithString(typed, for: block.id) {
            model.log("\(block.name) unlocked", symbol: "lock.open")
            dismiss()
            return
        } else {
            result = .unavailable
        }
        entryFocusRequest += 1
    }
}

/// Receives native keyboard events without exposing a selectable text buffer.
private struct ChallengeKeyInput: NSViewRepresentable {
    enum Edit {
        case append(Character)
        case backspace
    }

    let focusRequest: Int
    let value: String
    let onFocusChange: (Bool) -> Void
    let onEdit: (Edit) -> Void

    func makeNSView(context: Context) -> InputView {
        let view = InputView(frame: .zero)
        view.focusRequest = focusRequest
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.textField)
        view.setAccessibilityLabel("Challenge code input")
        view.setAccessibilityHelp("Type at the end. Press Backspace to erase one character.")
        return view
    }

    func updateNSView(_ view: InputView, context: Context) {
        view.onFocusChange = onFocusChange
        view.onEdit = onEdit
        view.setAccessibilityValue(value)
        if view.focusRequest != focusRequest {
            view.focusRequest = focusRequest
            view.requestFocus()
        }
    }

    final class InputView: NSView {
        var focusRequest = 0
        var onFocusChange: ((Bool) -> Void)?
        var onEdit: ((Edit) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        func requestFocus() {
            Task { @MainActor [weak self] in
                guard let self, let window else { return }
                window.makeFirstResponder(self)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { requestFocus() }
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
        }

        override func becomeFirstResponder() -> Bool {
            onFocusChange?(true)
            return true
        }

        override func resignFirstResponder() -> Bool {
            onFocusChange?(false)
            return true
        }

        override func keyDown(with event: NSEvent) {
            let modifiers = event.modifierFlags
            guard modifiers.intersection([.command, .control]).isEmpty else {
                super.keyDown(with: event)
                return
            }

            guard let characters = event.characters else { return }
            if characters == "\t" || characters == "\u{19}" {
                if modifiers.contains(.shift) {
                    window?.selectPreviousKeyView(self)
                } else {
                    window?.selectNextKeyView(self)
                }
            } else if characters == "\u{7F}" || characters == "\u{08}" {
                onEdit?(.backspace)
            } else if characters.unicodeScalars.count == 1,
                      let scalar = characters.unicodeScalars.first,
                      (0x20...0x7E).contains(scalar.value) {
                let character = Character(scalar)
                onEdit?(.append(character))
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
