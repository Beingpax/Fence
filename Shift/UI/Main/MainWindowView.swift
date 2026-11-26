import AppKit
import SwiftUI

/// Sections of the main window. Settings is one of these rather than a separate window:
/// a menu bar app with two windows is one window too many.
enum MainSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, blocks, journal, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .blocks: "Blocks"
        case .journal: "Journal"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2.fill"
        case .blocks: "shield.lefthalf.filled"
        case .journal: "book.closed.fill"
        case .settings: "gearshape.fill"
        }
    }

    /// Vivid, saturated colours: these sit on the icon tile, not behind the row, so they
    /// need to carry on their own.
    var tint: Color {
        switch self {
        case .dashboard: Color(nsColor: .systemOrange)
        case .blocks: Color(nsColor: .systemIndigo)
        case .journal: Color(nsColor: .systemTeal)
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
        .slidingPanel(isPresented: $isInspectorPresented, width: 440, onOutsideClick: {
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
        .frame(minWidth: Theme.mainWindowMinSize.width, minHeight: Theme.mainWindowMinSize.height)
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
        case .journal:
            JournalView()
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

// MARK: - Typing-code unlock

/// Switching off a block locked with a typing code. Redesigned on 26 Nov 2026, when the user
/// found the old one (a grid of letter tiles above a separate field) too busy: now the code
/// is one card of text in groups of four, and you type straight into it. Typed characters
/// fade, the next one is underlined in coral, and a wrong one turns red as soon as it's
/// typed, so there's nothing to decode after pressing Unlock. A bar fills as you go and
/// turns mint once the code is right; Unlock only works then.
struct RandomStringUnlockView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let block: Block

    @State private var challenge = ""
    @State private var typed = ""
    @State private var failed = false
    @State private var isFocused = false
    @State private var focusRequest = 0

    private var firstMismatch: Int? {
        zip(challenge, typed).enumerated().first { $0.element.0 != $0.element.1 }?.offset
    }

    private var isComplete: Bool {
        !challenge.isEmpty && typed.count == challenge.count && firstMismatch == nil
    }

    private var progress: Double {
        challenge.isEmpty ? 0 : Double(typed.count) / Double(challenge.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TYPING CODE")
                    .font(PlayType.rounded(11, .bold))
                    .tracking(1)
                    .foregroundStyle(Paper.coralText)
                Text("Unlock \(block.name)")
                    .font(PlayType.rounded(22, .bold))
                    .foregroundStyle(Paper.ink)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(alignment: .leading, spacing: 10) {
                codeCard
                progressRow
            }

            HStack(spacing: 10) {
                Button("Keep it on") { dismiss() }
                    .buttonStyle(.shiftSoft)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: attempt) {
                    Label("Unlock", systemImage: "lock.open")
                }
                .buttonStyle(.shiftProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isComplete)
            }
        }
        .padding(28)
        .frame(width: 460)
        .background {
            Paper.background.ignoresSafeArea()
        }
        .onAppear {
            if let code = model.store.createUnlockChallenge(for: block.id) {
                challenge = code
            } else {
                dismiss()
            }
        }
    }

    // MARK: The code

    private var codeCard: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Text(codeText)
            .font(.system(size: 18, weight: .semibold, design: .monospaced))
            .tracking(1)
            .lineSpacing(9)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(shape.fill(Paper.card))
            .overlay {
                shape
                    .strokeBorder(isFocused ? Paper.coral : Paper.hairline, lineWidth: isFocused ? 1.5 : 1)
                    .allowsHitTesting(false)
            }
            .textSelection(.disabled)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(challenge).speechSpellsOutCharacters())
            // The key catcher covers the whole card: click anywhere on it to type.
            .overlay {
                ChallengeKeyInput(
                    focusRequest: focusRequest,
                    value: typed,
                    onFocusChange: { isFocused = $0 },
                    onEdit: editEntry
                )
            }
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    /// The code in groups of four. Done characters fade, the next one is underlined,
    /// wrong ones go red.
    private var codeText: AttributedString {
        let entered = Array(typed)
        var text = AttributedString()
        for (index, character) in challenge.enumerated() {
            if index > 0, index.isMultiple(of: 4) {
                text += AttributedString(" ")
            }
            var piece = AttributedString(String(character))
            if index < entered.count {
                if entered[index] == character {
                    piece.swiftUI.foregroundColor = Paper.ink.opacity(0.22)
                } else {
                    piece.swiftUI.foregroundColor = .red
                    piece.swiftUI.backgroundColor = .red.opacity(0.14)
                }
            } else if index == entered.count, isFocused {
                piece.swiftUI.foregroundColor = Paper.coralText
                piece.swiftUI.underlineStyle = Text.LineStyle(pattern: .solid, color: Paper.coral)
            } else {
                piece.swiftUI.foregroundColor = Paper.ink
            }
            text += piece
        }
        return text
    }

    // MARK: Progress

    private var progressRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Paper.tile)
                        Capsule()
                            .fill(isComplete ? Paper.mint : Paper.coral)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 5)
                .animation(.snappy(duration: 0.2), value: typed.count)
                .accessibilityHidden(true)

                Text("\(typed.count) / \(challenge.count)")
                    .font(PlayType.rounded(11, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            if let line = statusLine {
                Label(line.text, systemImage: line.symbol)
                    .font(PlayType.rounded(12, .medium))
                    .foregroundStyle(line.isProblem ? Color.red : Color.secondary)
                    .transition(.opacity)
            }
        }
    }

    private var statusLine: (text: String, symbol: String, isProblem: Bool)? {
        if failed {
            return ("This block can’t be unlocked right now.", "exclamationmark.circle", true)
        }
        if let wrong = firstMismatch {
            return ("Character \(wrong + 1) doesn’t match. Backspace to fix it.", "delete.left", true)
        }
        if !isFocused, typed.count < challenge.count {
            return ("Click the code to keep typing.", "cursorarrow.click", false)
        }
        return nil
    }

    // MARK: Typing

    private func editEntry(_ edit: ChallengeKeyInput.Edit) {
        switch edit {
        case .append(let character):
            guard typed.count < challenge.count else { return }
            typed.append(character)
        case .backspace:
            guard !typed.isEmpty else { return }
            typed.removeLast()
        }
        failed = false
    }

    private func attempt() {
        guard isComplete else { return }
        if model.store.unlockWithString(typed, for: block.id) {
            model.log("\(block.name) unlocked", symbol: "lock.open")
            dismiss()
        } else {
            withAnimation(.easeOut(duration: 0.2)) { failed = true }
            focusRequest += 1
        }
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
