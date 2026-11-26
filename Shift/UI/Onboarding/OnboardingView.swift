import SwiftUI

/// First-run setup, in the order PRD §12 specifies:
/// welcome → "what steals your time?" → permissions → a demo pause → ready.
///
/// Design intent: one decision per screen, plain language throughout, and no hostname or
/// bundle ID ever shown to the user. The flow can be re-run later from Settings.
///
/// Every part here is drawn by hand rather than taken from the stock controls: warm paper,
/// coral and mint, soft rounded type, and things that squish when pressed. Marigold is the
/// mascot's alone.
/// The mascot peeks over the welcome card and waves over the last one.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onFinish: () -> Void

    @State private var step: Step = .welcome
    @State private var movingForward = true
    @State private var selected: Set<String> = []
    @State private var didSeedRules = false
    @State private var catalog = InstalledApps.shared
    @State private var excludedApps: Set<String> = []
    @State private var customEntry = ""
    @State private var customList: [String] = []
    @State private var showsInvalidWebsite = false
    @State private var blockName = "Distractions"
    @State private var lockChoice = LockMethod.none
    @State private var lockDuration: TimeInterval = 60 * 60
    @State private var lockUntil = TimeOfDay(hour: 17, minute: 0)
    @State private var lockLength = BlockLock.challengeLengths[0]
    @State private var hasSeenDemo = false
    @State private var mascotStart = Date()

    enum Step: Int, CaseIterable {
        case welcome, distractions, permissions, demo, ready

        var eyebrow: String {
            switch self {
            case .welcome: "Welcome"
            case .distractions: "Your distractions"
            case .permissions: "Permissions"
            case .demo: "Preview"
            case .ready: "Last step"
            }
        }

        var eyebrowSymbol: String {
            switch self {
            case .welcome: "hand.wave.fill"
            case .distractions: "square.grid.2x2.fill"
            case .permissions: "hand.raised.fill"
            case .demo: "sparkles"
            case .ready: "flag.checkered"
            }
        }

        var title: String {
            switch self {
            case .welcome: "Make room for focus"
            case .distractions: "What steals your time?"
            case .permissions: "Let Shift do its job"
            case .demo: "Here’s what a pause feels like"
            case .ready: "Make it yours"
            }
        }

        var subtitle: String {
            switch self {
            case .welcome: "Shift gently stops you before a distraction pays out, and cheers when you turn back."
            case .distractions: "Tap the ones you recognise. You can change any of this later."
            case .permissions: "Two quick switches in System Settings. Nothing Shift reads ever leaves this Mac."
            case .demo: "Try it once now, so the first real one isn’t a surprise. Nothing will be closed."
            case .ready: "Name your first block and choose how firm it should be."
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Paper.background.ignoresSafeArea()
            DotGrid().ignoresSafeArea()

            ZStack {
                currentPage
                    .id(step)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            footer
        }
        .onAppear {
            seedFromExistingRules()
            catalog.loadIfNeeded()
        }
    }

    // MARK: Chrome

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let distance: CGFloat = 56
        return .asymmetric(
            insertion: .offset(x: movingForward ? distance : -distance).combined(with: .opacity),
            removal: .offset(x: movingForward ? -distance : distance).combined(with: .opacity)
        )
    }

    private var stepAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.86)
    }

    /// Floating buttons, not a bar. They sit over the content; a short fade into the paper
    /// keeps text from running visibly underneath them.
    private var footer: some View {
        HStack(spacing: Theme.Space.snug) {
            ProgressPath(count: Step.allCases.count, current: step.rawValue)

            Spacer()

            if step != .welcome {
                Button(action: goBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("Back")
                    }
                }
                .buttonStyle(FloatingButtonStyle(isPrimary: false))
                .keyboardShortcut(.cancelAction)
            }

            Button(action: goForward) {
                HStack(spacing: 8) {
                    Text(primaryTitle)
                    Image(systemName: step == .ready ? "checkmark" : "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .buttonStyle(FloatingButtonStyle(isPrimary: true))
            .keyboardShortcut(.defaultAction)
            .disabled((step == .permissions && !model.backgroundBlockingAllowed) || (step == .ready && isFindingApps))
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 26)
        .padding(.top, 44)
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [Paper.background.opacity(0), Paper.background.opacity(0.94), Paper.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Let’s go"
        case .distractions: selected.isEmpty && customList.isEmpty ? "Skip for now" : "Use these"
        case .permissions: model.backgroundBlockingAllowed && model.browserAccessNeedsAttention ? "Skip for now" : "Continue"
        case .demo: hasSeenDemo ? "Continue" : "Show me"
        case .ready: "Create this block"
        }
    }

    // MARK: Pages

    @ViewBuilder
    private var currentPage: some View {
        switch step {
        case .welcome: welcomePage
        case .distractions: distractionsPage
        case .permissions: permissionsPage
        case .demo: demoPage
        case .ready: readyPage
        }
    }

    /// A scrolling page with the step's header on top.
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                StepHeader(step: step)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 48)
            // Clears the traffic lights: the window is full-size-content with a hidden title.
            .padding(.top, 48)
            // Room for the floating buttons, so the last row can scroll clear of them.
            .padding(.bottom, 112)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.never)
    }

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            MascotCard(mood: .calm, start: mascotStart, animates: !reduceMotion) {
                VStack(spacing: 10) {
                    Text(Step.welcome.title)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(Paper.ink)
                        .multilineTextAlignment(.center)
                    Text(Step.welcome.subtitle)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 400)
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 26)
            }
            .frame(maxWidth: 560)

            HStack(alignment: .top, spacing: 12) {
                PromiseCard(symbol: "scope", swatch: .coral, title: "Block what pulls you",
                            detail: "Whole sites, parts of sites like Shorts, or apps.")
                PromiseCard(symbol: "lock.laptopcomputer", swatch: .coral, title: "Stays on this Mac",
                            detail: "Shift reads the current app and address. Nothing leaves.")
                PromiseCard(symbol: "heart.fill", swatch: .coral, title: "Kind, not cruel",
                            detail: "A pause and a better idea, never a punishment.")
            }
            .frame(maxWidth: 660)
            .padding(.top, 20)

            Spacer(minLength: 112)
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var distractionsPage: some View {
        page {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(DistractionPreset.all) { preset in
                    PresetTile(preset: preset, isSelected: selected.contains(preset.id)) {
                        toggle(preset)
                    }
                }
            }

            addSiteCard
        }
    }

    private var addSiteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SetupLabel(symbol: "plus.circle.fill", text: "Something else?")

            HStack(spacing: 10) {
                PaperField(prompt: "example.com/feed or *concerts*", text: $customEntry, onSubmit: addCustom)
                Button(action: addCustom) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Paper.onCoral)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Paper.coral))
                }
                .buttonStyle(SquishButtonStyle())
                .disabled(isCustomEntryEmpty)
                .opacity(isCustomEntryEmpty ? 0.3 : 1)
                .help("Add")
                .accessibilityLabel("Add website")
            }
            .onChange(of: customEntry) { _, _ in showsInvalidWebsite = false }

            if !customList.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(customList, id: \.self) { tag in
                        TagPill(text: tag) {
                            withAnimation(stepAnimation) { customList.removeAll { $0 == tag } }
                        }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
            }

            Text(showsInvalidWebsite
                 ? "Enter a website, word or pattern such as *concerts*."
                 : "example.com/feed pauses just that section. *concerts* closes tabs with “concerts” in the address.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(showsInvalidWebsite ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .paperCard()
    }

    private var isCustomEntryEmpty: Bool {
        customEntry.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var permissionsPage: some View {
        page {
            VStack(spacing: 12) {
                permissionCard(.backgroundBlocking, symbol: "bolt.horizontal.fill")
                permissionCard(.browserAccess, symbol: "safari.fill")
            }

            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Paper.ink.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Paper.tile))
                Text("Nothing Shift reads is written to disk, and nothing leaves this Mac.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        // Permission changes happen in System Settings, so poll while this step is visible.
        // A closed window keeps this task alive, so skip the system queries until it's back.
        .task {
            while !Task.isCancelled {
                if model.isOnboardingVisible { model.refreshSystemState() }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func permissionCard(_ permission: BlockingPermissionRow.Permission, symbol: String) -> some View {
        let feedback = BlockingPermissionRow.feedback(for: permission, model: model)
        return PermissionCard(
            symbol: symbol,
            title: BlockingPermissionRow.title(for: permission),
            detail: feedback.detail,
            action: feedback.action
        )
    }

    private var demoPage: some View {
        page {
            PausePreview(animates: !reduceMotion, hasPlayed: hasSeenDemo) {
                model.previewPause()
                withAnimation(stepAnimation) { hasSeenDemo = true }
            }

            HStack(alignment: .center, spacing: 8) {
                JourneyCard(number: 1, symbol: "wind", title: "Breathe",
                            detail: "A short pause, before the page has loaded.")
                JourneyArrow()
                JourneyCard(number: 2, symbol: "bubble.left.fill", title: "Name it",
                            detail: "One honest question about the pull.")
                JourneyArrow()
                JourneyCard(number: 3, symbol: "sparkles", title: "Walk away",
                            detail: "Shift cheers. That’s the new habit forming.")
            }
            // Equal heights: each card stretches to the tallest one in the row.
            .fixedSize(horizontal: false, vertical: true)

            Note(symbol: "hourglass", text: hasSeenDemo
                 ? "That’s the last resort. Come back within the hour and each pause gets a little longer."
                 : "Come back within the hour and each pause gets a little longer.")
        }
    }

    private var readyPage: some View {
        page {
            MascotCard(mood: .happy, start: mascotStart, animates: !reduceMotion) {
                VStack(alignment: .leading, spacing: 10) {
                    SetupLabel(symbol: "shield.lefthalf.filled", text: "Name your first block")
                    BigNameField(prompt: "Distractions", text: $blockName)
                    Text("A block is a set of sites and apps with its own schedule and lock. You can add more later.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            suggestedAppReview

            VStack(alignment: .leading, spacing: 12) {
                SetupLabel(symbol: "lock.fill", text: "How firm should it be?")
                HStack(spacing: 10) {
                    ForEach(LockMethod.allCases) { method in
                        LockTile(method: method, isSelected: lockChoice == method) {
                            withAnimation(stepAnimation) { lockChoice = method }
                        }
                    }
                }
                LockSettingsCard(
                    method: lockChoice,
                    duration: $lockDuration,
                    until: $lockUntil,
                    length: $lockLength
                )
                .id(lockChoice)
                .transition(.opacity)
            }

            if model.launchAtLoginNeedsApproval {
                permissionCard(.openAtLogin, symbol: "power")
            } else {
                SwitchRow(
                    symbol: "power",
                    title: "Open Shift at login",
                    detail: "So your blocks are ready the moment you are.",
                    isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
            }

            Note(symbol: "moon.zzz.fill",
                 text: "It starts switched off. Turn it on from the menu bar whenever you want it.")
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
            LoadingDots(label: "Finding matching apps", animates: !reduceMotion)
        } else if !suggestedApps.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SetupLabel(symbol: "app.badge.fill", text: "Apps on this Mac to include")
                FlowLayout(spacing: 8) {
                    ForEach(suggestedApps) { app in
                        AppChip(
                            name: app.name,
                            icon: catalog.icon(for: app),
                            isIncluded: !excludedApps.contains(app.bundleID)
                        ) {
                            withAnimation(stepAnimation) {
                                if excludedApps.contains(app.bundleID) {
                                    excludedApps.remove(app.bundleID)
                                } else {
                                    excludedApps.insert(app.bundleID)
                                }
                            }
                        }
                    }
                }
            }
        } else if !suggestedAppIDs.isEmpty {
            Note(symbol: "app.dashed", text: "No matching apps found on this Mac.")
        }
    }

    // MARK: Actions

    private func seedFromExistingRules() {
        guard !didSeedRules else { return }
        didSeedRules = true
        if let first = model.store.blocks.first {
            selected.formUnion(first.list.matchingPresets.map(\.id))
        }
    }

    private func toggle(_ preset: DistractionPreset) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.62)) {
            if selected.contains(preset.id) {
                selected.remove(preset.id)
            } else {
                selected.insert(preset.id)
            }
        }
    }

    private func addCustom() {
        let entry = customEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rule = WebsiteRuleEntry(entry) else {
            showsInvalidWebsite = true
            return
        }
        withAnimation(stepAnimation) {
            if !customList.contains(where: { WebsiteRuleEntry($0) == rule }) {
                customList.append(entry)
            }
        }
        customEntry = ""
    }

    private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        movingForward = false
        withAnimation(stepAnimation) { step = previous }
    }

    private func goForward() {
        switch step {
        case .permissions:
            model.refreshBackgroundServiceStatus()
            guard model.backgroundBlockingAllowed else { return }
        case .demo:
            if !hasSeenDemo {
                model.previewPause()
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
        movingForward = true
        withAnimation(stepAnimation) { step = next }
    }

    private func finish() {
        guard !isFindingApps else { return }
        let name = blockName.trimmingCharacters(in: .whitespacesAndNewlines)
        var block = Block(name: name.isEmpty ? "Distractions" : name)
        let apps = suggestedApps.map(\.bundleID).filter { !excludedApps.contains($0) }
        block.list = BlockList.from(presets: selectedPresets, custom: customList, apps: apps)
        block.lock.method = lockChoice
        block.lock.duration = lockDuration
        block.lock.untilTime = lockUntil
        block.lock.stringLength = lockLength
        guard model.completeOnboarding(with: block) else {
            movingForward = false
            withAnimation(stepAnimation) { step = .permissions }
            return
        }

        onFinish()
        model.presentMainWindow()
    }
}

// MARK: - Headers and labels

private struct StepHeader: View {
    let step: OnboardingView.Step

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: step.eyebrowSymbol)
                    .font(.system(size: 10, weight: .bold))
                Text(step.eyebrow.uppercased())
                    .font(PlayType.rounded(11, .bold))
                    .tracking(1.1)
            }
            .foregroundStyle(Paper.coralText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Paper.coralSoft))

            Text(step.title)
                .font(PlayType.rounded(30, .bold))
                .foregroundStyle(Paper.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(step.subtitle)
                .font(PlayType.rounded(14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct SetupLabel: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Paper.ink.opacity(0.55))
            Text(text)
                .font(PlayType.rounded(15, .semibold))
                .foregroundStyle(Paper.ink)
        }
    }
}

private struct Note: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
            Text(text)
                .font(PlayType.rounded(13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Progress

/// Pebbles on a string: done ones are filled coral, the current one is a larger coral pebble.
private struct ProgressPath: View {
    let count: Int
    let current: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                if index > 0 {
                    Capsule()
                        .fill(index <= current ? Paper.coral : Color.primary.opacity(0.14))
                        .frame(width: 14, height: 2)
                }
                pebble(index)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.7), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }

    private func pebble(_ index: Int) -> some View {
        let isCurrent = index == current
        let isDone = index < current
        let size: CGFloat = isCurrent ? 14 : 9
        return ZStack {
            Circle().fill(isCurrent || isDone ? Paper.coral : Color.clear)
            Circle().strokeBorder(isCurrent || isDone ? Paper.coral : Color.primary.opacity(0.22), lineWidth: 1.5)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Surfaces

private struct PromiseCard: View {
    let symbol: String
    let swatch: Swatch
    let title: String
    let detail: String

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(swatch.glyph)
                .frame(width: 34, height: 34)
                .background(Circle().fill(swatch.fill))
            Text(title)
                .font(PlayType.rounded(14, .bold))
                .foregroundStyle(Paper.ink)
            Text(detail)
                .font(PlayType.rounded(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .paperCard()
        .offset(y: isHovering ? -3 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Distractions

private struct PresetTile: View {
    let preset: DistractionPreset
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    /// A chosen tile keeps its white card and gains a coral edge, icon and check, so the
    /// grid never turns into a wall of colour.
    private var foreground: Color { Paper.ink }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: preset.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? Paper.onCoral : Paper.ink.opacity(0.75))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(isSelected ? Paper.coral : Paper.tile))
                    Spacer(minLength: 0)
                    CheckStamp(isOn: isSelected)
                }
                Text(preset.title)
                    .font(PlayType.rounded(13, .semibold))
                    .foregroundStyle(foreground)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Paper.card)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Paper.coral : Paper.hairline, lineWidth: isSelected ? 2 : 1)
            }
            .shadow(color: .black.opacity(isHovering ? 0.08 : 0.03), radius: isHovering ? 12 : 6, y: isHovering ? 6 : 3)
            .offset(y: isHovering ? -2 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(SquishButtonStyle())
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .help(preset.effect)
        .accessibilityLabel(preset.title)
        .accessibilityValue(isSelected ? "selected" : "not selected")
        .accessibilityHint(preset.effect)
    }
}

/// A round check that pops in when a tile is chosen.
private struct CheckStamp: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1.5)
                .opacity(isOn ? 0 : 1)
            Circle()
                .fill(Paper.coral)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Paper.onCoral)
                }
                .scaleEffect(isOn ? 1 : 0.3)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

/// A rounded text field on paper, outlined in ink while it has focus.
private struct PaperField: View {
    let prompt: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt))
            .textFieldStyle(.plain)
            .font(PlayType.rounded(14))
            .foregroundStyle(Paper.ink)
            .focused($isFocused)
            .onSubmit(onSubmit)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Capsule(style: .continuous).fill(Paper.background))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(isFocused ? Paper.coral : Paper.hairline, lineWidth: isFocused ? 1.5 : 1)
            }
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

private struct TagPill: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 6) {
                Text(text)
                    .font(PlayType.rounded(12, .semibold))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .black))
                    .opacity(0.6)
            }
            .foregroundStyle(Paper.onCoral)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(Paper.coral))
        }
        .buttonStyle(SquishButtonStyle())
        .help("Remove \(text)")
        .accessibilityLabel("Remove \(text)")
    }
}

/// Lays children out left to right and wraps onto new rows, like words in a paragraph.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Permissions

private struct PermissionCard: View {
    let symbol: String
    let title: String
    let detail: String
    let action: (title: String, perform: () -> Void)?

    private var isDone: Bool { action == nil }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: isDone ? "checkmark" : symbol)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(isDone ? Paper.onMint : Paper.ink.opacity(0.75))
                .frame(width: 50, height: 50)
                .background {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(isDone ? Paper.mint : Paper.tile)
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(PlayType.rounded(15, .bold))
                    .foregroundStyle(Paper.ink)
                Text(detail)
                    .font(PlayType.rounded(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(PillButtonStyle())
                    .fixedSize()
            }
        }
        .padding(18)
        .paperCard(radius: 22)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Paper.mint.opacity(isDone ? 0.6 : 0), lineWidth: 1.5)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isDone)
    }
}

// MARK: - Demo

/// A small window onto the pause: a night sky that twinkles, the question, and three of
/// the feelings it offers. Pressing play shows the real one.
private struct PausePreview: View {
    let animates: Bool
    let hasPlayed: Bool
    let onPlay: () -> Void

    private static let night = Color(red: 0.11, green: 0.10, blue: 0.09)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Self.night)
            StarField(animates: animates)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            // The night sky is close to the dark-mode paper, so an edge keeps it a card.
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)

            VStack(spacing: 14) {
                Text("What’s pulling you here?")
                    .font(PlayType.rounded(17, .semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    MiniChip(symbol: "cloud.fill", text: "I’m bored")
                    MiniChip(symbol: "mountain.2.fill", text: "This is hard")
                    MiniChip(symbol: "battery.25", text: "I’m drained")
                }
                Button(action: onPlay) {
                    HStack(spacing: 7) {
                        Image(systemName: hasPlayed ? "arrow.counterclockwise" : "play.fill")
                            .font(.system(size: 11, weight: .black))
                        Text(hasPlayed ? "Watch it again" : "Preview the pause")
                    }
                    .font(PlayType.rounded(13, .bold))
                    .foregroundStyle(Color(red: 0.1, green: 0.11, blue: 0.11))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule(style: .continuous).fill(Color.white))
                }
                .buttonStyle(SquishButtonStyle())
                .padding(.top, 4)
            }
            .padding(20)
        }
        .frame(height: 210)
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }
}

private struct MiniChip: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(text).font(PlayType.rounded(11, .semibold))
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(.white.opacity(0.1)))
        .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 1))
    }
}

private struct StarField: View {
    let animates: Bool

    private struct Star: Sendable {
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
        let phase: Double
        let speed: Double
    }

    /// Generated once from a fixed seed, so the sky is the same every time.
    private static let stars: [Star] = {
        var seed: UInt64 = 0x5EED_CAFE
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
        return (0..<80).map { _ in
            Star(
                x: CGFloat(next()),
                y: CGFloat(next()),
                radius: CGFloat(0.5 + next() * 1.3),
                phase: next() * 6.28,
                speed: 0.6 + next() * 1.4
            )
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !animates)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for star in Self.stars {
                    let twinkle: Double = animates ? 0.45 + 0.55 * (0.5 + 0.5 * sin(t * star.speed + star.phase)) : 0.8
                    let rect = CGRect(
                        x: star.x * size.width - star.radius,
                        y: star.y * size.height - star.radius,
                        width: star.radius * 2,
                        height: star.radius * 2
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(Color(red: 1, green: 0.95, blue: 0.86).opacity(twinkle))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct JourneyCard: View {
    let number: Int
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(number)")
                    .font(PlayType.rounded(12, .heavy))
                    .foregroundStyle(Paper.onCoral)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Paper.coral))
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Paper.ink.opacity(0.5))
            }
            Text(title)
                .font(PlayType.rounded(14, .bold))
                .foregroundStyle(Paper.ink)
            Text(detail)
                .font(PlayType.rounded(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .paperCard(radius: 18)
    }
}

private struct JourneyArrow: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.tertiary)
            .frame(width: 14)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

// MARK: - Ready

/// The block's name, typed big, on a line that darkens while it has focus.
private struct BigNameField: View {
    let prompt: String
    @Binding var text: String

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("", text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .font(PlayType.rounded(26, .bold))
                .foregroundStyle(Paper.ink)
                .focused($isFocused)
            Capsule()
                .fill(isFocused ? Paper.coral : Paper.hairline)
                .frame(height: isFocused ? 3 : 2)
        }
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}

private struct AppChip: View {
    let name: String
    let icon: NSImage
    let isIncluded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .opacity(isIncluded ? 1 : 0.5)
                Text(name)
                    .font(PlayType.rounded(13, .semibold))
                Image(systemName: isIncluded ? "checkmark" : "plus")
                    .font(.system(size: 9, weight: .black))
            }
            .foregroundStyle(isIncluded ? Paper.onCoral : Paper.ink.opacity(0.6))
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.vertical, 7)
            .background(Capsule(style: .continuous).fill(isIncluded ? Paper.coral : Paper.card))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(isIncluded ? Paper.coral : Paper.hairline, lineWidth: isIncluded ? 1.5 : 1)
            }
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel(name)
        .accessibilityValue(isIncluded ? "included" : "not included")
    }
}

private struct LockTile: View {
    let method: LockMethod
    let isSelected: Bool
    let action: () -> Void

    private var shortTitle: String {
        switch method {
        case .none: "No lock"
        case .duration: "For a while"
        case .untilTime: "Until a time"
        case .randomString: "Typing challenge"
        case .restart: "Until restart"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: method.symbol)
                    .font(.system(size: 17, weight: .semibold))
                Text(shortTitle)
                    .font(PlayType.rounded(12, .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isSelected ? Paper.coral : Paper.ink.opacity(0.75))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 82)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Paper.card)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Paper.coral : Paper.hairline, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel(method.title)
        .accessibilityValue(isSelected ? "selected" : "not selected")
        .accessibilityHint(method.detail)
    }
}

/// What the chosen lock does, and the one or two settings it needs, right under the tiles.
private struct LockSettingsCard: View {
    let method: LockMethod
    @Binding var duration: TimeInterval
    @Binding var until: TimeOfDay
    @Binding var length: Int

    private static let durations: [ChoiceOption<TimeInterval>] = [
        ChoiceOption(value: 30 * 60, title: "30 min"),
        ChoiceOption(value: 60 * 60, title: "1 hour"),
        ChoiceOption(value: 2 * 60 * 60, title: "2 hours"),
        ChoiceOption(value: 4 * 60 * 60, title: "4 hours"),
        ChoiceOption(value: 8 * 60 * 60, title: "8 hours"),
        ChoiceOption(value: 24 * 60 * 60, title: "1 day"),
    ]

    private static let lengths: [ChoiceOption<Int>] = BlockLock.challengeLengths.map {
        ChoiceOption(value: $0, title: "\($0)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(method.detail)
                .font(PlayType.rounded(13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch method {
            case .duration:
                ChoiceRow(label: "Stay locked for", options: Self.durations, selection: $duration)
            case .untilTime:
                TimeChooser(time: $until)
            case .randomString:
                ChoiceRow(label: "Characters to type", options: Self.lengths, selection: $length)
            case .none, .restart:
                EmptyView()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(radius: 20)
    }
}

private struct ChoiceOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
}

private struct ChoiceRow<Value: Hashable>: View {
    let label: String
    let options: [ChoiceOption<Value>]
    @Binding var selection: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SmallCaps(text: label)
            FlowLayout(spacing: 8) {
                ForEach(options) { option in
                    ChoiceChip(title: option.title, isSelected: selection == option.value) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selection = option.value }
                    }
                }
            }
        }
    }
}

/// A capsule choice. Chosen ones fill with coral.
private struct ChoiceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PlayType.rounded(13, .semibold))
                .foregroundStyle(isSelected ? Paper.onCoral : Paper.ink.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule(style: .continuous).fill(isSelected ? Paper.coral : Paper.background))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? Paper.coral : Paper.hairline, lineWidth: isSelected ? 1.5 : 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityValue(isSelected ? "selected" : "not selected")
    }
}

/// A time, shown big, nudged a quarter hour at a time, with a few common picks below it.
private struct TimeChooser: View {
    @Binding var time: TimeOfDay

    private static let picks = [
        TimeOfDay(hour: 12, minute: 0),
        TimeOfDay(hour: 17, minute: 0),
        TimeOfDay(hour: 18, minute: 0),
        TimeOfDay(hour: 21, minute: 0),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SmallCaps(text: "Locked until")

            HStack(spacing: 14) {
                RoundIconButton(symbol: "minus", label: "Fifteen minutes earlier") { shift(by: -15) }
                Text(Self.label(for: time))
                    .font(PlayType.rounded(30, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Paper.ink)
                    .contentTransition(.numericText())
                    .frame(minWidth: 150)
                RoundIconButton(symbol: "plus", label: "Fifteen minutes later") { shift(by: 15) }
            }

            HStack(spacing: 8) {
                ForEach(Self.picks, id: \.minutes) { pick in
                    ChoiceChip(title: Self.label(for: pick), isSelected: time == pick) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { time = pick }
                    }
                }
            }
        }
    }

    private func shift(by minutes: Int) {
        let day = 24 * 60
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            time = TimeOfDay(minutes: ((time.minutes + minutes) % day + day) % day)
        }
    }

    /// Formats a time of day in the person's own clock style (12- or 24-hour).
    static func label(for time: TimeOfDay) -> String {
        let date = Calendar.current.date(
            bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()
        ) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct RoundIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Paper.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Paper.background))
                .overlay(Circle().strokeBorder(Paper.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(SquishButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct SwitchRow: View {
    let symbol: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Paper.ink.opacity(0.75))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Paper.tile))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PlayType.rounded(14, .bold))
                    .foregroundStyle(Paper.ink)
                Text(detail)
                    .font(PlayType.rounded(12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            PaperSwitch(isOn: $isOn)
                .accessibilityLabel(title)
        }
        .padding(16)
        .paperCard(radius: 20)
    }
}

private struct LoadingDots: View {
    let label: String
    let animates: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !animates)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Paper.coral)
                            .frame(width: 8, height: 8)
                            .offset(y: bounce(at: t, index: index))
                    }
                }
                Text(label)
                    .font(PlayType.rounded(13))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private func bounce(at time: TimeInterval, index: Int) -> CGFloat {
        guard animates else { return 0 }
        return CGFloat(-5 * max(0, sin(time * 6 - Double(index) * 0.8)))
    }
}
