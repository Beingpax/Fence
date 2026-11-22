import SwiftUI

/// First-run setup, in the order PRD §12 specifies:
/// welcome → "what steals your time?" → permissions → a demo shield → ready.
///
/// Design intent: one decision per screen, plain language throughout, and no hostname or
/// bundle ID ever shown to the user. The flow can be re-run later from Settings.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    let onFinish: () -> Void

    @State private var step: Step = .welcome
    @State private var selected: Set<String> = []
    @State private var customEntry = ""
    @State private var customList: [String] = []
    @State private var focusGoal = ""
    @State private var blockName = "Distractions"
    @State private var lockChoice = LockMethod.none
    @State private var hasSeenDemo = false

    enum Step: Int, CaseIterable {
        case welcome, distractions, permissions, demo, ready

        var title: String {
            switch self {
            case .welcome: "A blocker that understands the page"
            case .distractions: "What steals your time?"
            case .permissions: "One permission to grant"
            case .demo: "This is what a block feels like"
            case .ready: "You're set"
            }
        }

        var subtitle: String {
            switch self {
            case .welcome: "Shift judges what's on screen against the goal you set, and everything it reads stays on this Mac."
            case .distractions: "Pick the ones you recognise. You can change any of this later."
            case .permissions: "Accessibility lets Shift see which window is in front and what page it's on."
            case .demo: "Try it once now, so the first real block isn't a surprise. Nothing will be closed."
            case .ready: "Start your first session whenever you're ready."
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            Divider().padding(.horizontal, Theme.Space.wide)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Theme.Space.wide)
            footer
        }
        .background {
            VisualEffect(surface: .window, blending: .behindWindow).ignoresSafeArea()
        }
        .onAppear(perform: seedFromExistingRules)
    }

    // MARK: Chrome

    private var heading: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            Text(step.title)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(step.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.wide)
        // Clears the traffic lights: the window is full-size-content with a hidden title.
        .padding(.top, 38)
        .padding(.bottom, Theme.Space.base)
    }

    private var footer: some View {
        HStack(spacing: Theme.Space.snug) {
            StepDots(count: Step.allCases.count, current: step.rawValue)

            Spacer()

            if step != .welcome {
                Button("Back", action: goBack)
                    .buttonStyle(.shiftSoft)
                    .keyboardShortcut(.cancelAction)
            }

            Button(primaryTitle, action: goForward)
                .buttonStyle(.shiftProminent)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(.horizontal, Theme.Space.wide)
        .padding(.vertical, Theme.Space.base)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get started"
        case .distractions: selected.isEmpty && customList.isEmpty ? "Skip for now" : "Use these rules"
        case .permissions: model.accessibilityGranted ? "Continue" : "Skip for now"
        case .demo: hasSeenDemo ? "Continue" : "Show me"
        case .ready: "Create this block"
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: WelcomeStep()
        case .distractions: distractionsStep
        case .permissions: permissionsStep
        case .demo: demoStep
        case .ready: readyStep
        }
    }

    private var distractionsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.base) {
                GlassEffectContainer(spacing: Theme.Space.snug) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Space.snug)],
                        alignment: .leading,
                        spacing: Theme.Space.snug
                    ) {
                        ForEach(DistractionPreset.all) { preset in
                            PresetChip(
                                preset: preset,
                                isSelected: selected.contains(preset.id)
                            ) {
                                toggle(preset)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Space.tight) {
                    SectionLabel(text: "Anything else?")
                    HStack(spacing: Theme.Space.tight) {
                        ShiftTextField(
                            prompt: "example.com, or example.com/feed",
                            text: $customEntry,
                            symbol: "plus",
                            onSubmit: addCustom
                        )
                        Button("Add", action: addCustom)
                            .buttonStyle(.shiftSoft)
                            .disabled(customEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if !customList.isEmpty {
                        WrappingTags(tags: customList) { tag in
                            customList.removeAll { $0 == tag }
                        }
                    }
                    Text("Adding a slash blocks only that part of a site, so the rest of it keeps working.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.base) {
            PermissionCard(
                title: "Accessibility",
                detail: "Reads the frontmost window's title and the current page address. This is how Shift knows where you are.",
                state: model.accessibilityGranted ? .granted : .needed,
                actionTitle: "Grant…",
                action: { model.requestAccessibilityPermission() }
            )

            PermissionCard(
                title: "Screen Recording",
                detail: model.screenRecordingGranted
                    ? "Granted. Shift can read text from a snapshot of the active window for goal-based blocks."
                    : "Optional. Lets Shift read visible text when an app provides too little through Accessibility.",
                state: model.screenRecordingGranted ? .granted : .later,
                actionTitle: "Grant…",
                action: { model.requestScreenRecordingPermission() }
            )

            Label(
                "Nothing Shift reads is written to disk, and nothing leaves this Mac.",
                systemImage: "lock.shield"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        // Permission changes happen in System Settings, so poll while this step is visible.
        .task {
            while !Task.isCancelled {
                model.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var demoStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.base) {
            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                Label("The shield covers every display and every Space.", systemImage: "rectangle.on.rectangle")
                Label("In a browser it closes the tab. In an app it quits the app.", systemImage: "xmark.circle")
                Label("Friction grows with each strike, so the second slip costs more.", systemImage: "chart.line.uptrend.xyaxis")
            }
            .font(.callout)
            .labelStyle(.titleAndIcon)

            Button {
                model.previewShield(strike: 1)
                hasSeenDemo = true
            } label: {
                Label("Preview the shield", systemImage: "play.fill")
            }
            .buttonStyle(.shiftSoft)
            .controlSize(.large)

            if hasSeenDemo {
                Text("That was strike 1. You can preview strikes 2 and 3 any time from the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .calmTransition(.opacity)
            }
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.base) {
            VStack(alignment: .leading, spacing: Theme.Space.tight) {
                SectionLabel(text: "Name this block")
                ShiftTextField(prompt: "e.g. Distractions", text: $blockName, symbol: "shield.lefthalf.filled")
                Text("A block is a named set of sites and apps with its own schedule and lock. You can add more later, and keep them on different terms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Theme.Space.tight) {
                SectionLabel(text: "Focus goal")
                ShiftTextField(prompt: "Optional, e.g. Finish the thesis chapter", text: $focusGoal)
                    .accessibilityLabel("Focus goal")
            }

            VStack(alignment: .leading, spacing: Theme.Space.tight) {
                SectionLabel(text: "How hard should it be to switch off?")
                LockMethodPicker(selection: $lockChoice)
                Text(lockChoice.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label("It starts switched off. Turn it on from the menu bar when you want it.", systemImage: "power")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func seedFromExistingRules() {
        guard selected.isEmpty, let first = model.store.blocks.first else { return }
        selected = Set(first.list.matchingPresets.map(\.id))
    }

    private func toggle(_ preset: DistractionPreset) {
        if selected.contains(preset.id) {
            selected.remove(preset.id)
        } else {
            selected.insert(preset.id)
        }
    }

    private func addCustom() {
        let entry = customEntry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !entry.isEmpty, !customList.contains(entry) else { return }
        customList.append(entry)
        customEntry = ""
    }

    private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.18)) { step = previous }
    }

    private func goForward() {
        switch step {
        case .distractions:
            applyRules()
        case .demo:
            if !hasSeenDemo {
                model.previewShield(strike: 1)
                hasSeenDemo = true
                return
            }
        case .ready:
            finish()
            return
        default:
            break
        }

        guard let next = Step(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) { step = next }
    }

    private func applyRules() {
        // Nothing to do here any more: the list is built when the block is created.
    }

    private func finish() {
        model.completeOnboarding()

        let presets = DistractionPreset.all.filter { selected.contains($0.id) }
        let list = BlockList.from(presets: presets, custom: customList)

        let goal = focusGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        if !list.isEmpty || !goal.isEmpty {
            var block = Block(name: blockName.trimmingCharacters(in: .whitespaces).isEmpty ? "Distractions" : blockName)
            block.list = list
            block.goal = goal
            block.schedule = .always
            block.lock.method = lockChoice
            model.store.add(block)
            model.log("Created “\(block.name)”", symbol: "plus.circle")
        }

        onFinish()
        model.presentMainWindow()
    }
}

// MARK: - Pieces

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.base) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .top, spacing: Theme.Space.snug) {
                    Image(systemName: point.symbol)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Space.hair) {
                        Text(point.title).font(.headline)
                        Text(point.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var points: [(symbol: String, title: String, detail: String)] {
        [
            ("scope", "It judges intent, not domains",
             "YouTube can be a lecture or a Shorts hole. Shift decides against the goal you set, so the useful half of a site keeps working."),
            ("lock.laptopcomputer", "Everything stays on this Mac",
             "No account, no screenshots uploaded, no model to download. The AI that reads the page already ships with macOS."),
            ("hand.raised.fill", "As strict as you ask for",
             "Repeated blocks raise the shield level. A lock controls when you can turn a block off."),
        ]
    }
}

private struct PresetChip: View {
    let preset: DistractionPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.tight) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : preset.symbol)
                    .font(.callout)
                Text(preset.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(isSelected ? AnyButtonStyle(.glassProminent) : AnyButtonStyle(.glass))
        .controlSize(.large)
        .help(preset.effect)
        .accessibilityLabel(preset.title)
        .accessibilityValue(isSelected ? "selected" : "not selected")
        .accessibilityHint(preset.effect)
    }
}

/// Lets a conditional pick between two button styles without the branches fighting
/// over SwiftUI's generic `ButtonStyle` type.
struct AnyButtonStyle: PrimitiveButtonStyle {
    private let apply: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        apply = { configuration in
            AnyView(Button(configuration).buttonStyle(style))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        apply(configuration)
    }
}

private struct WrappingTags: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 120), spacing: Theme.Space.tight)],
            alignment: .leading,
            spacing: Theme.Space.tight
        ) {
            ForEach(tags, id: \.self) { tag in
                Button {
                    onRemove(tag)
                } label: {
                    HStack(spacing: Theme.Space.hair) {
                        Text(tag).font(.caption).lineLimit(1)
                        Image(systemName: "xmark.circle.fill").font(.caption2)
                    }
                }
                .buttonStyle(.borderless)
                .help("Remove \(tag)")
                .accessibilityLabel("Remove \(tag)")
            }
        }
    }
}

private struct PermissionCard: View {
    enum State {
        case granted, needed, later
    }

    let title: String
    let detail: String
    let state: State
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.snug) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Space.hair) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Space.tight)

            if let actionTitle, let action, state != .granted {
                Button(actionTitle, action: action)
                    .buttonStyle(.shiftSoft)
            }
        }
        .glassSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(stateDescription)")
    }

    private var symbol: String {
        switch state {
        case .granted: "checkmark.circle.fill"
        case .needed: "exclamationmark.circle.fill"
        case .later: "clock"
        }
    }

    private var color: Color {
        switch state {
        case .granted: .green
        case .needed: .orange
        case .later: .secondary
        }
    }

    private var stateDescription: String {
        switch state {
        case .granted: "granted"
        case .needed: "not granted"
        case .later: "needed later"
        }
    }
}

private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: Theme.Space.tight) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: current)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}
