import SwiftUI

/// First-run setup, in the order PRD §12 specifies:
/// welcome → "what steals your time?" → permissions → a demo shield → ready.
///
/// Design intent: one decision per screen, plain language throughout, and no hostname or
/// bundle ID ever shown to the user. The flow can be re-run later from Settings.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onFinish: () -> Void

    @State private var step: Step = .welcome
    @State private var selected: Set<String> = []
    @State private var catalog = InstalledApps.shared
    @State private var excludedApps: Set<String> = []
    @State private var customEntry = ""
    @State private var customList: [String] = []
    @State private var showsInvalidWebsite = false
    @State private var blockName = "Distractions"
    @State private var lockChoice = LockMethod.none
    @State private var hasSeenDemo = false

    enum Step: Int, CaseIterable {
        case welcome, distractions, permissions, demo, ready

        var title: String {
            switch self {
            case .welcome: "Make room for focus"
            case .distractions: "What steals your time?"
            case .permissions: "One permission to grant"
            case .demo: "This is what a block feels like"
            case .ready: "You're set"
            }
        }

        var subtitle: String {
            switch self {
            case .welcome: "Choose which apps, sites, and parts of sites to block. Everything Shift reads stays on this Mac."
            case .distractions: "Pick the ones you recognise. You can change any of this later."
            case .permissions: "Accessibility lets Shift see which window is in front and what page it's on."
            case .demo: "Try it once now, so the first real block isn't a surprise. Nothing will be closed."
            case .ready: "Start your first session whenever you're ready."
            }
        }

        var appearance: (symbol: String, tint: BlockTint) {
            switch self {
            case .welcome: ("shield.lefthalf.filled", .indigo)
            case .distractions: ("square.grid.2x2.fill", .blue)
            case .permissions: ("hand.raised.fill", .teal)
            case .demo: ("bolt.shield.fill", .orange)
            case .ready: ("checkmark", .purple)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, Theme.Space.wide)
                    .padding(.vertical, Theme.Space.base)
            }
            .scrollBounceBehavior(.basedOnSize)
            .id(step)
            Hairline()
            footer
        }
        .background {
            Theme.detailBackground.ignoresSafeArea()
        }
        .onAppear {
            seedFromExistingRules()
            catalog.loadIfNeeded()
        }
    }

    // MARK: Chrome

    private var heading: some View {
        HStack(alignment: .top, spacing: Theme.Space.base) {
            BlockBadge(symbol: step.appearance.symbol, tint: step.appearance.tint, size: 50)
            PageHeader(step.title, subtitle: step.subtitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.wide)
        // Clears the traffic lights: the window is full-size-content with a hidden title.
        .padding(.top, 38)
        .padding(.bottom, Theme.Space.base)
    }

    private var footer: some View {
        HStack(spacing: Theme.Space.snug) {
            StepDots(count: Step.allCases.count, current: step.rawValue, tint: step.appearance.tint.color)

            Spacer()

            if step != .welcome {
                Button("Back", action: goBack)
                    .buttonStyle(.shiftSoft)
                    .keyboardShortcut(.cancelAction)
            }

            Button(primaryTitle, action: goForward)
                .buttonStyle(.shiftProminent(step.appearance.tint.color))
                .keyboardShortcut(.defaultAction)
                .disabled(step == .ready && isFindingApps)
        }
        .controlSize(.large)
        .padding(.horizontal, Theme.Space.wide)
        .padding(.vertical, Theme.Space.base)
        .background(Theme.workspaceBackground)
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
        VStack(alignment: .leading, spacing: Theme.Space.base) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 176), spacing: Theme.Space.snug)],
                alignment: .leading,
                spacing: Theme.Space.snug
            ) {
                ForEach(DistractionPreset.all) { preset in
                    PresetChip(preset: preset, isSelected: selected.contains(preset.id)) {
                        toggle(preset)
                    }
                }
            }

            Panel("Add another website", icon: "globe") {
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
                .onChange(of: customEntry) { _, _ in showsInvalidWebsite = false }
                if !customList.isEmpty {
                    WrappingTags(tags: customList) { tag in
                        customList.removeAll { $0 == tag }
                    }
                }
                Text(showsInvalidWebsite ? "Enter a website like example.com." :
                    "Add a path like /feed to block only that part of a site.")
                    .font(.caption)
                    .foregroundStyle(showsInvalidWebsite ? Color.orange : Color.secondary)
            }
        }
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
                Label("The shield can quit the entire browser or app.", systemImage: "power")
                Label("You get \(NudgeLadder.stepCount) nudges first. Close the tab and nothing happens.", systemImage: "hand.wave")
            }
            .font(.callout)
            .labelStyle(.titleAndIcon)

            Button {
                model.previewShield()
                hasSeenDemo = true
            } label: {
                Label("Preview the shield", systemImage: "play.fill")
            }
            .buttonStyle(.shiftSoft)
            .controlSize(.large)

            if hasSeenDemo {
                Text("That is the last resort. Preview the nudges that come first from Settings → Previews.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .calmTransition(.opacity)
            }
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.base) {
            Panel("Name this block", icon: "shield.lefthalf.filled", tint: .indigo) {
                ShiftTextField(prompt: "e.g. Distractions", text: $blockName, symbol: "shield.lefthalf.filled")
                Text("A block is a named set of sites and apps with its own schedule and lock. You can add more later, and keep them on different terms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            suggestedAppReview

            Panel("Lock", subtitle: "Choose how hard it is to switch this block off.", icon: "lock", tint: .purple) {
                LockMethodPicker(selection: $lockChoice)
            }

            Label("It starts switched off. Turn it on from the menu bar when you want it.", systemImage: "power")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var selectedPresets: [DistractionPreset] {
        DistractionPreset.all.filter { selected.contains($0.id) }
    }

    private var suggestedAppIDs: Set<String> { Set(selectedPresets.flatMap(\.apps)) }
    private var isFindingApps: Bool { !suggestedAppIDs.isEmpty && catalog.isLoading }

    private var suggestedApps: [InstalledApp] {
        let candidates = suggestedAppIDs
        return catalog.apps.filter { candidates.contains($0.bundleID) }
    }

    @ViewBuilder
    private var suggestedAppReview: some View {
        if isFindingApps {
            ProgressView("Finding matching apps…")
        } else if !suggestedApps.isEmpty {
            Panel("Matching apps on this Mac", icon: "app.badge", tint: .teal) {
                ForEach(suggestedApps) { app in
                    Toggle(isOn: Binding(
                        get: { !excludedApps.contains(app.bundleID) },
                        set: { include in
                            if include {
                                excludedApps.remove(app.bundleID)
                            } else {
                                excludedApps.insert(app.bundleID)
                            }
                        }
                    )) {
                        Label {
                            Text(app.name)
                        } icon: {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 18, height: 18)
                            } else {
                                Image(systemName: "app")
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        } else if !suggestedAppIDs.isEmpty {
            Text("No matching apps found on this Mac.")
                .font(.caption)
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
        guard let address = WebsiteAddress(entry: customEntry) else {
            showsInvalidWebsite = true
            return
        }
        if !customList.contains(where: { WebsiteAddress(entry: $0) == address }) {
            customList.append(address.entry)
        }
        customEntry = ""
    }

    private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { step = previous }
    }

    private func goForward() {
        switch step {
        case .demo:
            if !hasSeenDemo {
                model.previewShield()
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
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { step = next }
    }

    private func finish() {
        guard !isFindingApps else { return }
        let name = blockName.trimmingCharacters(in: .whitespacesAndNewlines)
        var block = Block(name: name.isEmpty ? "Distractions" : name)
        let apps = suggestedApps.map(\.bundleID).filter { !excludedApps.contains($0) }
        block.list = BlockList.from(presets: selectedPresets, custom: customList, apps: apps)
        block.lock.method = lockChoice
        model.store.add(block)
        model.log("Created “\(block.name)”", symbol: "plus.circle")
        model.completeOnboarding()

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
                    BlockBadge(symbol: point.symbol, tint: point.tint, size: 34)
                    VStack(alignment: .leading, spacing: Theme.Space.hair) {
                        Text(point.title).font(.headline)
                        Text(point.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(tint: point.tint.color)
            }
        }
    }

    private var points: [(symbol: String, tint: BlockTint, title: String, detail: String)] {
        [
            ("scope", .indigo, "Block what distracts you",
             "Block a whole website, a section like YouTube Shorts, or an app."),
            ("lock.laptopcomputer", .teal, "Everything stays on this Mac",
             "Shift checks the current app and web address on your Mac."),
            ("hand.raised.fill", .orange, "Choose how strict to be",
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
                BlockBadge(symbol: preset.symbol, tint: isSelected ? .blue : .graphite, size: 28)
                Text(preset.title)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .contentShape(Rectangle())
            .glassSurface(padding: Theme.Space.snug, tint: isSelected ? .blue : nil, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .help(preset.effect)
        .accessibilityLabel(preset.title)
        .accessibilityValue(isSelected ? "selected" : "not selected")
        .accessibilityHint(preset.effect)
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
        case granted, needed
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
        .glassSurface(tint: color)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(stateDescription)")
    }

    private var symbol: String {
        switch state {
        case .granted: "checkmark.circle.fill"
        case .needed: "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .granted: .green
        case .needed: .orange
        }
    }

    private var stateDescription: String {
        switch state {
        case .granted: "granted"
        case .needed: "not granted"
        }
    }
}

private struct StepDots: View {
    let count: Int
    let current: Int
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Space.tight) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? tint : Color.secondary.opacity(0.25))
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: current)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}
