import AppKit
import SwiftUI

/// First-run setup: welcome → the lists to block → permissions → a guided tour → the
/// first block.
///
/// Design intent: one decision per screen, plain language throughout, and no hostname or
/// bundle ID ever shown to the user. The flow can be re-run later from Settings.
///
/// Every part here is drawn by hand rather than taken from the stock controls: warm paper,
/// coral and mint, soft rounded type, and things that squish when pressed. Marigold is the
/// mascot's alone.
/// The mascot peeks over the welcome card and waves over the last one.
///
/// Redesigned on 26 Nov 2026 at the user's request: the lists replace the grid of single
/// apps (no chat apps, no Spotify), Open at login joins the permissions and all three are
/// required, and the static pause preview became a guided tour with cards of its own.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onFinish: () -> Void

    @State private var step: Step = .welcome
    @State private var movingForward = true
    @State private var chosenLists: Set<PreMadeList> = []
    @State private var didSeedRules = false
    @State private var catalog = InstalledApps.shared
    @State private var excludedApps: Set<String> = []
    @State private var customEntry = ""
    @State private var customList: [String] = []
    @State private var showsInvalidWebsite = false
    @State private var blockName = "Distractions"
    @State private var lockChoice = LockMethod.restart
    @State private var lockDuration: TimeInterval = 60 * 60
    @State private var lockUntil = TimeOfDay(hour: 17, minute: 0)
    @State private var lockLength = BlockLock.challengeLengths[0]
    /// The tour has the whole window.
    @State private var touring = false
    @State private var tourDone = false
    @State private var mascotStart = Date()

    enum Step: Int, CaseIterable {
        case welcome, distractions, permissions, tour, ready

        var eyebrow: String {
            switch self {
            case .welcome: "Welcome"
            case .distractions: "Your distractions"
            case .permissions: "Permissions"
            case .tour: "Tour"
            case .ready: "Last step"
            }
        }

        var eyebrowSymbol: String {
            switch self {
            case .welcome: "hand.wave.fill"
            case .distractions: "square.grid.2x2.fill"
            case .permissions: "hand.raised.fill"
            case .tour: "sparkles"
            case .ready: "flag.checkered"
            }
        }

        var title: String {
            switch self {
            case .welcome: "Make room for focus"
            case .distractions: "What steals your time?"
            case .permissions: "Let Fence do its job"
            case .tour: "See how Fence works"
            case .ready: "Make it yours"
            }
        }

        var subtitle: String {
            switch self {
            case .welcome: "Fence gently stops you before a distraction pays out, and cheers when you turn back."
            case .distractions: "Pick the lists to block. Each one covers the sites and the Mac apps."
            case .permissions: "A few switches in System Settings. Nothing Fence sees ever leaves this Mac."
            case .tour: "Meet \(Mascot.name), who looks out for you. One minute, one step at a time, so the real thing never takes you by surprise."
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

            if !touring {
                footer
            }

            if touring {
                OnboardingTour(
                    onFinish: {
                        tourDone = true
                        withAnimation(.easeInOut(duration: 0.35)) { touring = false }
                        goForward()
                    },
                    onExit: {
                        withAnimation(.easeInOut(duration: 0.35)) { touring = false }
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }
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
            .disabled((step == .permissions && !permissionsComplete) || (step == .ready && isFindingApps))
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
        case .distractions: chosenLists.isEmpty && customList.isEmpty ? "Skip for now" : "Use these"
        case .permissions: "Continue"
        case .tour: tourDone ? "Continue" : "Skip the tour"
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
        case .tour: tourPage
        case .ready: readyPage
        }
    }

    /// A scrolling page with the step's header on top.
    /// `width` makes the page one centred column, header included, so nothing hugs the left
    /// with empty space beside it.
    private func page<Content: View>(width: CGFloat? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        centered(width: width) {
            VStack(alignment: .leading, spacing: 24) {
                StepHeader(step: step)
                content()
            }
        }
    }

    /// Every page's frame, the welcome included, so they all sit in the same place: one
    /// column centred across the window and down it, only as tall as it needs to be, and
    /// scrolling if the window is ever shorter than the page.
    private func centered<Content: View>(
        width: CGFloat?,
        alignment: Alignment = .leading,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        // Built here, outside the GeometryReader's escaping closure, which can't call a
        // non-escaping one.
        let pageContent = content()
        return GeometryReader { proxy in
            ScrollView {
                pageContent
                    // Only the height the content needs. Without this, the centring frame
                    // below offers the whole window's height and anything with a Spacer (the
                    // list tiles) stretches to fill it.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: width ?? .infinity, alignment: alignment)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 48)
                    // Clears the traffic lights: the window is full-size-content with a hidden title.
                    .padding(.top, 48)
                    // Room for the floating buttons, so the last row can scroll clear of them.
                    .padding(.bottom, 112)
                    // The window fills the screen, so a page that fits sits in the middle of it
                    // rather than along the top.
                    .frame(minHeight: proxy.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
        }
    }

    private var welcomePage: some View {
        centered(width: 660, alignment: .center) {
            VStack(spacing: 20) {
                MascotCard(mood: .hello, start: mascotStart, animates: !reduceMotion) {
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
                                detail: "Fence reads the current app and address. Nothing leaves.")
                    PromiseCard(symbol: "heart.fill", swatch: .coral, title: "Kind, not cruel",
                                detail: "A pause and a better idea, never a punishment.")
                }
            }
        }
    }

    // MARK: Distractions

    private var distractionsPage: some View {
        page(width: 640) {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    listTile(.socialMedia)
                    listTile(.news)
                }
                GridRow {
                    listTile(.email)
                    listTile(.adult)
                }
            }

            addSiteCard
        }
    }

    private func listTile(_ list: PreMadeList) -> some View {
        ListTile(list: list, isSelected: chosenLists.contains(list)) { toggle(list) }
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

    // MARK: Permissions

    private var permissionsPage: some View {
        page(width: 640) {
            VStack(spacing: 12) {
                permissionStep(.browserAccess, number: 1, symbol: "safari.fill", title: "Browser access")
                permissionStep(.backgroundBlocking, number: 2, symbol: "bolt.horizontal.fill",
                               title: BlockingPermissionRow.title(for: .backgroundBlocking))
                loginStep
            }

            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Paper.ink.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Paper.tile))
                Text("Fence reads only the app in front and its address. Nothing is recorded, and nothing leaves this Mac.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    /// All three are needed before setup moves on (26 Nov 2026, the user's call): nothing
    /// here is optional.
    private var permissionsComplete: Bool {
        [BlockingPermissionRow.Permission.browserAccess, .backgroundBlocking]
            .allSatisfy { BlockingPermissionRow.feedback(for: $0, model: model).action == nil }
            && model.launchAtLoginEnabled
    }

    private func permissionStep(
        _ permission: BlockingPermissionRow.Permission,
        number: Int,
        symbol: String,
        title: String
    ) -> some View {
        // While something still needs doing, the wording is Settings' own, so the two never
        // disagree. Once it's allowed, one short line says what it gives.
        let feedback = BlockingPermissionRow.feedback(for: permission, model: model)
        let allowed = permission == .browserAccess
            ? "Allowed. Fence can see the address and close a blocked tab."
            : "Allowed. Your blocks keep working even if Fence is force quit."
        return PermissionStep(
            number: number, symbol: symbol, title: title,
            detail: feedback.action == nil ? allowed : feedback.detail,
            isDone: feedback.action == nil
        ) {
            if let action = feedback.action {
                Button(action.title, action: action.perform)
                    .buttonStyle(PillButtonStyle())
                    .fixedSize()
            }
        }
    }

    private var loginStep: some View {
        let needsApproval = model.launchAtLoginNeedsApproval
        let isOn = model.launchAtLoginEnabled
        let detail = needsApproval
            ? BlockingPermissionRow.feedback(for: .openAtLogin, model: model).detail
            : (isOn ? "On. Your blocks are ready the moment you sign in." : "Starts Fence when you sign in, so your blocks are always ready.")
        return PermissionStep(
            number: 3, symbol: "power", title: BlockingPermissionRow.title(for: .openAtLogin),
            detail: detail, isDone: isOn
        ) {
            if needsApproval {
                Button("Open Login Items", action: LaunchAtLogin.openLoginItemsSettings)
                    .buttonStyle(PillButtonStyle())
                    .fixedSize()
            } else if !isOn {
                Button("Turn on") { model.setLaunchAtLogin(true) }
                    .buttonStyle(PillButtonStyle())
                    .fixedSize()
            }
        }
    }

    // MARK: Tour

    /// The tour's front door: what it is, a glimpse of it, and one big button. The tour
    /// itself (`OnboardingTour`) takes over the whole window once started.
    private var tourPage: some View {
        page(width: 640) {
            TourScreen(stage: .headsUp, animates: !reduceMotion, start: mascotStart)
                .frame(height: 230)
                .overlay(alignment: .center) {
                    if tourDone {
                        HStack(spacing: 8) {
                            DoneCheck()
                            Text("Tour done")
                                .font(PlayType.rounded(15, .bold))
                                .foregroundStyle(Paper.onCoralSolid)
                        }
                        .padding(.leading, 8)
                        .padding(.trailing, 16)
                        .padding(.vertical, 8)
                        .background(Capsule(style: .continuous).fill(Paper.coralSolid))
                        .shadow(color: Paper.coralSolid.opacity(0.35), radius: 14, y: 6)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }

            HStack(spacing: 10) {
                TourPromise(symbol: "hand.raised.fill", text: "Meet \(Mascot.name)")
                TourPromise(symbol: "arrow.uturn.backward", text: "Turn back in time")
                TourPromise(symbol: "wind", text: "Take a pause")
            }

            HStack(spacing: 14) {
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) { touring = true }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: tourDone ? "arrow.counterclockwise" : "play.fill")
                            .font(.system(size: 13, weight: .black))
                        Text(tourDone ? "Take the tour again" : "Start the tour")
                    }
                }
                .buttonStyle(FloatingButtonStyle(isPrimary: true))

                Text("About a minute, right in this window. Nothing is blocked for real.")
                    .font(PlayType.rounded(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(stepAnimation, value: tourDone)
    }

    // MARK: Ready

    private var readyPage: some View {
        page(width: 680) {
            VStack(alignment: .leading, spacing: 10) {
                SetupLabel(symbol: "shield.lefthalf.filled", text: "Name your first block")
                BigNameField(prompt: "Distractions", text: $blockName)
                    // Room for the mascot's hands on the card's corner.
                    .padding(.trailing, 70)
                Text("A block is a set of sites and apps with its own schedule and lock. You can add more later.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCard(radius: 24)
            // The mascot peeks over the card's top-right corner, in the header's empty space,
            // so it takes no room of its own (26 Nov 2026, the user's call).
            .background(alignment: .topTrailing) {
                CornerMascot(layer: .body, start: mascotStart, animates: !reduceMotion)
            }
            .overlay(alignment: .topTrailing) {
                CornerMascot(layer: .hands, start: mascotStart, animates: !reduceMotion)
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

            Note(symbol: "moon.zzz.fill",
                 text: "It starts switched off. Turn it on from the menu bar whenever you want it.")
        }
    }

    /// The Mac apps the chosen lists block, among those installed here.
    private var suggestedAppIDs: Set<String> {
        Set(chosenLists.flatMap { PreMadeLists.shared.apps(in: $0) })
    }

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
                SetupLabel(symbol: "app.badge.fill", text: "Apps on this Mac it covers")
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
                        .help("Click to leave it out of the list")
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func seedFromExistingRules() {
        guard !didSeedRules else { return }
        didSeedRules = true
        if let first = model.store.blocks.first {
            let names = PreMadeList.migrate(first.list.categoryNames)
            chosenLists = Set(names.compactMap(PreMadeList.init(rawValue:)))
        }
    }

    private func toggle(_ list: PreMadeList) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.62)) {
            if chosenLists.contains(list) {
                chosenLists.remove(list)
            } else {
                chosenLists.insert(list)
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
            model.refreshSystemState()
            guard permissionsComplete else { return }
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
        block.list.categoryNames = Set(chosenLists.map(\.rawValue))
        block.list.addWebsiteRules(customList.compactMap(WebsiteRuleEntry.init))
        block.lock.method = lockChoice
        block.lock.duration = lockDuration
        block.lock.untilTime = lockUntil
        block.lock.stringLength = lockLength
        guard model.completeOnboarding(with: block) else {
            movingForward = false
            withAnimation(stepAnimation) { step = .permissions }
            return
        }

        // Leaving an app out edits the list itself, the same as the list editor does: a
        // list's apps belong to the list, not to one block.
        let lists = PreMadeLists.shared
        for bundleID in excludedApps where suggestedAppIDs.contains(bundleID) {
            for list in chosenLists where lists.apps(in: list).contains(bundleID) {
                lists.removeApp(bundleID, from: list)
            }
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

/// One pre-made list as a big tile. Chosen, it fills with solid coral and its check pops;
/// the examples underneath say what it covers without a single hostname.
private struct ListTile: View {
    let list: PreMadeList
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var examples: [String] {
        switch list {
        case .socialMedia: ["Instagram", "TikTok", "YouTube", "X", "Reddit", "Netflix"]
        case .news: ["CNN", "BBC", "New York Times", "Spiegel", "The Guardian"]
        case .email: ["Gmail", "Outlook", "Yahoo Mail", "Mail"]
        case .adult: ["Known 18+ sites", "Explicit words in addresses"]
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: "\(list.symbol).fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isSelected ? Paper.coralSolid : Paper.ink.opacity(0.75))
                        .symbolEffect(.bounce, value: isSelected)
                        .frame(width: 38, height: 38)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSelected ? Color.white : Paper.tile)
                        }
                    Spacer(minLength: 0)
                    TileCheck(isOn: isSelected)
                }

                Spacer(minLength: 10)

                Text(list.title)
                    .font(PlayType.rounded(18, .heavy))
                    .foregroundStyle(isSelected ? Paper.onCoralSolid : Paper.ink)

                FlowLayout(spacing: 5) {
                    ForEach(examples, id: \.self) { example in
                        Text(example)
                            .font(PlayType.rounded(10.5, .semibold))
                            .foregroundStyle(isSelected ? Paper.onCoralSolid : Paper.ink.opacity(0.65))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(isSelected ? Color.white.opacity(0.22) : Paper.tile)
                            }
                    }
                }
                .padding(.top, 7)
            }
            .padding(14)
            // Fills its grid row, so the two tiles side by side always match.
            .frame(maxWidth: .infinity, minHeight: 124, maxHeight: .infinity, alignment: .topLeading)
            .background(shape.fill(isSelected ? Paper.coralSolid : Paper.card))
            .overlay(shape.strokeBorder(Paper.hairline.opacity(isSelected ? 0 : 1), lineWidth: 1))
            .shadow(
                color: isSelected ? Paper.coralSolid.opacity(0.3) : .black.opacity(isHovering ? 0.08 : 0.04),
                radius: isSelected ? 16 : (isHovering ? 14 : 10),
                y: isSelected ? 8 : (isHovering ? 7 : 4)
            )
            .offset(y: isHovering ? -3 : 0)
            .contentShape(shape)
        }
        .buttonStyle(SquishButtonStyle())
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .animation(.spring(response: 0.32, dampingFraction: 0.68), value: isSelected)
        .help(list.help)
        .accessibilityLabel(list.title)
        .accessibilityValue(isSelected ? "selected" : "not selected")
        .accessibilityHint(list.help)
    }
}

/// A round check on a list tile: an empty ring, or a white disc with a coral tick that pops in.
private struct TileCheck: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1.5)
                .opacity(isOn ? 0 : 1)
            Circle()
                .fill(Color.white)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Paper.coralSolid)
                }
                .scaleEffect(isOn ? 1 : 0.3)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: 26, height: 26)
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

/// One permission: a numbered tile, its name, one line about it, and the one control that
/// sorts it out. Once it's allowed the whole card fills with coral and a white check takes
/// the control's place (26 Nov 2026, the user's call: a colour change, not a green border
/// and a green tick).
private struct PermissionStep<Accessory: View>: View {
    let number: Int
    let symbol: String
    let title: String
    let detail: String
    let isDone: Bool
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(isDone ? Paper.coralSolid : Paper.ink.opacity(0.75))
                .frame(width: 52, height: 52)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isDone ? Color.white : Paper.tile)
                }
                .overlay(alignment: .topLeading) {
                    Text("\(number)")
                        .font(PlayType.rounded(11, .heavy))
                        .foregroundStyle(Paper.onCoralSolid)
                        .frame(width: 21, height: 21)
                        .background(Circle().fill(Paper.coralSolid))
                        .overlay(Circle().strokeBorder(Paper.card, lineWidth: 2))
                        .offset(x: -6, y: -6)
                        .scaleEffect(isDone ? 0.2 : 1)
                        .opacity(isDone ? 0 : 1)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(PlayType.rounded(17, .bold))
                    .foregroundStyle(isDone ? Paper.onCoralSolid : Paper.ink)
                Text(detail)
                    .font(PlayType.rounded(12.5))
                    .foregroundStyle(isDone ? Paper.onCoralSolid.opacity(0.85) : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if isDone {
                DoneCheck()
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            } else {
                accessory()
            }
        }
        .padding(18)
        .background(shape.fill(isDone ? Paper.coralSolid : Paper.card))
        .overlay(shape.strokeBorder(Paper.hairline.opacity(isDone ? 0 : 1), lineWidth: 1))
        .shadow(color: isDone ? Paper.coralSolid.opacity(0.25) : .black.opacity(0.04), radius: isDone ? 14 : 10, y: isDone ? 6 : 4)
        .animation(.spring(response: 0.4, dampingFraction: 0.72), value: isDone)
        .accessibilityElement(children: .contain)
        .accessibilityValue(isDone ? "done" : "needs doing")
    }
}

/// A white disc with a bold coral tick, the same check the list tiles use, a size up.
private struct DoneCheck: View {
    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Paper.coralSolid)
            }
            .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Tour

/// One thing the tour shows, as a small chip.
private struct TourPromise: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Paper.coralSolid)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Paper.coralSoft))
            Text(text)
                .font(PlayType.rounded(13, .bold))
                .foregroundStyle(Paper.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .paperCard(radius: 18)
    }
}

/// The mascot at the last page's name card, small, peeking over the top-right corner: the
/// body drawn behind the card (the card hides its lower half) and the hands in front.
private struct CornerMascot: View {
    let layer: MascotView.Layer
    let start: Date
    let animates: Bool

    private static let scale: CGFloat = 0.62
    @State private var risen = false

    var body: some View {
        MascotView(mood: .happy, layer: layer, animates: animates, start: start, pointScale: Self.scale)
            .offset(x: -18, y: -MascotView.cardEdgeOffset(pointScale: Self.scale) + (risen ? 0 : 36))
            .opacity(layer == .hands && !risen ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(animates ? .spring(response: 0.6, dampingFraction: 0.68).delay(0.25) : nil) { risen = true }
            }
    }
}

/// A small Mac screen acting out one stop: the heads-up in the corner with its ten seconds
/// draining, the cheer once the tab is closed, or the pause's night sky. A coral note on top
/// names the moment.
private struct TourScreen: View {
    enum Stage: Equatable { case headsUp, pause, cheer }

    let stage: Stage
    let animates: Bool
    let start: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let night = Color(red: 0.11, green: 0.10, blue: 0.09)
    static let site = "instagram.com"

    private var note: (symbol: String, text: String) {
        switch stage {
        case .headsUp: (symbol: "hand.wave.fill", text: "\(Mascot.name) taps you on the shoulder")
        case .cheer: (symbol: "sparkles", text: "\(Mascot.name) cheers you on")
        case .pause: (symbol: "wind", text: "A moment to choose")
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(stage == .pause ? Self.night : Paper.tile)
            if stage == .pause {
                StarField(animates: animates)
            } else {
                DotGrid()
            }

            VStack(alignment: .leading, spacing: 10) {
                coachNote
                ZStack(alignment: .bottomTrailing) {
                    if stage == .pause {
                        pausePanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        MiniBrowser(showsPage: stage != .cheer)
                            .padding(.trailing, 120)
                    }

                    if stage == .headsUp {
                        MiniNudge(
                            mood: .annoyed,
                            headline: "\(Self.site) is on your Distractions list.",
                            detail: "Close the tab, or I’ll step in.",
                            drains: true,
                            animates: animates,
                            start: start
                        )
                    } else if stage == .cheer {
                        MiniNudge(
                            mood: .cheer,
                            headline: "Nicely done.",
                            detail: "That’s the habit forming.",
                            drains: false,
                            animates: animates,
                            start: start
                        )
                        .overlay(alignment: .topLeading) { Sparkles(animates: animates) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(14)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(stage == .pause ? Color.white.opacity(0.12) : Paper.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note.text)
    }

    private var coachNote: some View {
        HStack(spacing: 6) {
            Image(systemName: note.symbol)
                .font(.system(size: 11, weight: .bold))
            Text(note.text)
                .font(PlayType.rounded(12, .bold))
        }
        .foregroundStyle(Paper.onCoralSolid)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(Paper.coralSolid))
        .shadow(color: Paper.coralSolid.opacity(0.3), radius: 6, y: 3)
    }

    private var pausePanel: some View {
        VStack(spacing: 12) {
            Text("What’s pulling you here?")
                .font(PlayType.rounded(15, .semibold))
                .foregroundStyle(.white)
            HStack(spacing: 6) {
                ForEach([UrgeReason.bored, .stuck, .tired]) { reason in
                    MiniChip(symbol: reason.symbol, text: reason.title)
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        }
    }
}

/// A browser window in miniature: three dots, the address, and a page sketched in grey
/// bars. Closed, it shows an empty Start Page.
private struct MiniBrowser: View {
    let showsPage: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color.primary.opacity(0.16)).frame(width: 7, height: 7)
                }
                HStack(spacing: 5) {
                    Image(systemName: showsPage ? "lock.fill" : "magnifyingglass")
                        .font(.system(size: 7, weight: .bold))
                    Text(showsPage ? TourScreen.site : "Start Page")
                        .font(PlayType.rounded(10, .semibold))
                }
                .foregroundStyle(Paper.ink.opacity(showsPage ? 0.75 : 0.4))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Capsule(style: .continuous).fill(Paper.background))
                .padding(.leading, 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Rectangle().fill(Paper.hairline).frame(height: 1)

            VStack(alignment: .leading, spacing: 7) {
                if showsPage {
                    Capsule().fill(Paper.ink.opacity(0.16)).frame(width: 110, height: 10)
                    ForEach([0.92, 0.8, 0.86, 0.55], id: \.self) { fraction in
                        GeometryReader { proxy in
                            Capsule().fill(Paper.ink.opacity(0.07))
                                .frame(width: proxy.size.width * fraction, height: 6)
                        }
                        .frame(height: 6)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(shape.fill(Paper.card))
        .overlay(shape.strokeBorder(Paper.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

/// The nudge card in miniature, with the mascot peeking over its top edge as on the real
/// one. A heads-up's bar drains over its ten seconds, then starts again.
private struct MiniNudge: View {
    let mood: MascotMood
    let headline: String
    let detail: String
    let drains: Bool
    let animates: Bool
    let start: Date

    @State private var drained = false
    private static let scale: CGFloat = 0.36

    var body: some View {
        let edge = MascotView.cardEdgeOffset(pointScale: Self.scale)
        ZStack(alignment: .top) {
            MascotView(mood: mood, layer: .body, animates: animates, start: start, pointScale: Self.scale)
                .frame(width: MascotView.size(pointScale: Self.scale).width, height: edge, alignment: .top)
                .clipped()

            card.padding(.top, edge)

            MascotView(mood: mood, layer: .hands, animates: animates, start: start, pointScale: Self.scale)
        }
        .frame(width: 186)
        .allowsHitTesting(false)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline)
                .font(PlayType.rounded(11, .bold))
                .foregroundStyle(Paper.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(PlayType.rounded(10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if drains {
                Capsule()
                    .fill(Paper.ink.opacity(0.08))
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        // Empties from the right, anchored at its leading edge, like the pause's.
                        Capsule()
                            .fill(Paper.coralSolid)
                            .scaleEffect(x: drained ? 0.001 : 1, anchor: .leading)
                    }
                    .padding(.top, 4)
                    .onAppear {
                        withAnimation(.linear(duration: 10)) { drained = true }
                    }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Paper.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Paper.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
    }
}

/// A few coral sparkles that burst out once beside the cheer card.
private struct Sparkles: View {
    let animates: Bool
    @State private var burst = false

    private static let points: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (-14, 18, 13), (6, -4, 9), (-22, 46, 8), (176, 20, 11), (190, 52, 8),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.points.indices, id: \.self) { index in
                let point = Self.points[index]
                Image(systemName: "sparkle")
                    .font(.system(size: point.size, weight: .bold))
                    .foregroundStyle(Paper.coralSolid)
                    .offset(x: point.x, y: point.y)
                    .scaleEffect(burst ? 1 : 0.1)
                    .opacity(burst ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(animates ? .spring(response: 0.45, dampingFraction: 0.5).delay(0.25) : nil) { burst = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
    @Environment(\.windowIsVisible) private var windowIsVisible

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
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !animates || !windowIsVisible)) { timeline in
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

private struct LoadingDots: View {
    let label: String
    let animates: Bool
    @Environment(\.windowIsVisible) private var windowIsVisible

    var body: some View {
        // 60 fps is plenty for three bouncing dots; uncapped, ProMotion ran it at 120.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !animates || !windowIsVisible)) { timeline in
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
