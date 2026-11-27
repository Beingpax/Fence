import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Creates and edits a block, in the panel that slides in from the trailing edge.
///
/// Redesigned on 26 Nov 2026 at the user's request ("too bad"): one clear column in the
/// order people think about a block. Who it is (a big badge and name), what it blocks
/// (websites, then apps), when it's on, and how hard it is to switch off.
///
/// How it's built:
/// - **Glass for controls, paper for content.** The panel is Liquid Glass; the sections on it
///   are frosted white cards, so glass never sits on glass. Only the floating controls (close,
///   Cancel, Save) are glass, the way macOS 26 floats its own toolbar buttons.
/// - **Sorbet rules.** Coral marks selection and the one primary action; the block's own
///   colour appears only on its badge. Section icons are coral, everything else neutral.
/// - **Choices are visible, not hidden in menus.** Schedule and lock are rows of tiles you can
///   read at a glance; each one's settings appear right under it.
/// - **Quick to fill.** The name field is focused for a new block, Return adds a site, popular
///   sites are one click away, and the colour and icon live behind the badge.
struct BlockInspector: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft: Block
    @State private var original: Block
    @State private var isShowingAppPicker = false
    @State private var isShowingAppearance = false
    @State private var editingList: PreMadeList?
    @State private var isShowingSchedule = false
    /// The schedule before the sheet opened, so Cancel can put it back.
    @State private var scheduleBeforeSheet: BlockSchedule?
    @State private var isImportingSites = false
    @State private var importNote: String?
    @State private var isShowingWebsiteHelp = false
    /// Whether the add field blocks what's typed or lets it through.
    @State private var addMode: AddMode = .block
    @State private var isShowingSaveError = false
    @State private var isShowingDiscardConfirmation = false
    @FocusState private var isNameFocused: Bool

    private let isNew: Bool
    private let dismissalRequest: Int
    private let onClose: () -> Void

    init(block: Block, isNew: Bool, dismissalRequest: Int, onClose: @escaping () -> Void) {
        _draft = State(initialValue: block)
        _original = State(initialValue: block)
        self.isNew = isNew
        self.dismissalRequest = dismissalRequest
        self.onClose = onClose
    }

    private var savedBlock: Block? { model.store.block(id: draft.id) }
    private var isLocked: Bool { savedBlock?.isLocked() == true }
    private var canRequestUnlock: Bool {
        guard let savedBlock else { return false }
        return savedBlock.requiresUnlockChallenge() && !savedBlock.lock.isLocked()
    }
    private var hasChanges: Bool { draft != original }
    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { (isNew || hasChanges) && !trimmedName.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EditorMetrics.section) {
                header
                if isLocked { lockedBanner }
                websitesSection
                appsSection
                whenSection
                lockSection
            }
            .padding(.horizontal, EditorMetrics.page)
            .padding(.top, 22)
            // Room for the floating buttons, so the last card can scroll clear of them.
            .padding(.bottom, 86)
        }
        .scrollBounceBehavior(.basedOnSize)
        .overlay(alignment: .topTrailing) { closeButton }
        .overlay(alignment: .bottom) { footer }
        .onAppear {
            // Pre-made list rows count the apps they'd block on this Mac.
            InstalledApps.shared.loadIfNeeded()
            if isNew { Task { @MainActor in isNameFocused = true } }
        }
        .onChange(of: isLocked) { _, locked in
            if locked {
                preserveLockedRules()
                addMode = .block
            }
        }
        .onChange(of: dismissalRequest) { _, _ in
            requestClose()
        }
        .sheet(isPresented: $isShowingAppPicker) {
            AppPickerView(selected: $draft.list.apps, canRemove: !isLocked)
        }
        .sheet(item: $editingList) { list in
            PreMadeListEditor(list: list, canLoosen: !isHeldByLock(list))
        }
        .sheet(isPresented: $isShowingSchedule) {
            ScheduleSheet(
                initial: currentWindows,
                onCancel: {
                    if let before = scheduleBeforeSheet { draft.schedule = before }
                    scheduleBeforeSheet = nil
                    isShowingSchedule = false
                },
                onDone: { windows in
                    draft.schedule = .scheduled(windows)
                    scheduleBeforeSheet = nil
                    isShowingSchedule = false
                }
            )
        }
        .alert("Couldn’t save block", isPresented: $isShowingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The block changed while you were editing. Review the draft and try again.")
        }
        .confirmationDialog("Discard unsaved changes?", isPresented: $isShowingDiscardConfirmation) {
            Button("Discard changes", role: .destructive, action: onClose)
            Button("Keep editing", role: .cancel) {}
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                isShowingAppearance.toggle()
            } label: {
                BlockBadge(symbol: draft.symbol, tint: draft.tint, size: 60)
                    .shadow(color: draft.tint.color.opacity(0.35), radius: 10, y: 5)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Paper.ink.opacity(0.75))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Paper.card))
                            .overlay(Circle().strokeBorder(Paper.hairline, lineWidth: 1))
                            .offset(x: 5, y: 5)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(SquishButtonStyle())
            .help("Change the colour and icon")
            .accessibilityLabel("Colour and icon")
            .popover(isPresented: $isShowingAppearance, arrowEdge: .bottom) {
                AppearancePicker(tint: $draft.tint, symbol: $draft.symbol)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow.uppercased())
                    .font(PlayType.rounded(11, .bold))
                    .tracking(0.9)
                    .foregroundStyle(Paper.coralText)
                    .lineLimit(1)
                    .contentTransition(.numericText())

                TextField("Block name", text: $draft.name, prompt: Text("Name this block"))
                    .textFieldStyle(.plain)
                    .font(PlayType.rounded(24, .bold))
                    .foregroundStyle(Paper.ink)
                    .focused($isNameFocused)
                    .onSubmit { isNameFocused = false }
            }
        }
        // Clear of the floating close button.
        .padding(.trailing, 40)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: eyebrow)
    }

    private var eyebrow: String {
        if isNew && draft.list.isEmpty { return "New block" }
        return draft.contentsSummary
    }

    private var closeButton: some View {
        Button(action: requestClose) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Paper.ink.opacity(0.7))
                .frame(width: 30, height: 30)
                .glassEffect(.regular.interactive(), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close")
        .accessibilityLabel("Close editor")
        .padding(.top, 16)
        .padding(.trailing, 16)
    }

    // MARK: Locked

    @ViewBuilder private var lockedBanner: some View {
        if let savedBlock {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Paper.onCoral)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Paper.coral))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(savedBlock.lockStatus())
                        .font(PlayType.rounded(14, .semibold))
                        .foregroundStyle(Paper.ink)
                    Text("You can add to it, but not loosen it.")
                        .font(PlayType.rounded(12))
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if canRequestUnlock {
                    Button {
                        model.requestBlockUnlock(id: draft.id)
                    } label: {
                        Label("Unlock", systemImage: "lock.open")
                    }
                    .buttonStyle(PillButtonStyle())
                    .fixedSize()
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .editorCard()
        }
    }

    // MARK: Websites

    /// One field adds everything, with a Block / Allow switch beside it, and a line under it
    /// saying what the entry will do before it's added (26 Nov 2026, the user asked for a
    /// cleaner way than a separate "Always allow" field behind a disclosure). Then the
    /// pre-made lists, then what this block blocks and what it always lets through, as two
    /// groups of chips. Import and help sit in the section's title row.
    private var websitesSection: some View {
        EditorSection(title: "Websites", symbol: "globe") {
            HStack(spacing: 0) {
                IconButton(symbol: "square.and.arrow.down", help: "Import sites from a .txt or .json file") {
                    isImportingSites = true
                }
                IconButton(symbol: "questionmark.circle", help: "What to type") {
                    isShowingWebsiteHelp.toggle()
                }
                .popover(isPresented: $isShowingWebsiteHelp, arrowEdge: .trailing) {
                    WebsiteHelp()
                }
            }
        } content: {
            RuleInput(
                // The toggle says Block or Allow, so the prompt needn't.
                prompt: addMode == .block ? "A site or word, like youtube.com" : "A page, like youtube.com/watch",
                symbol: addMode == .block ? "plus" : "checkmark",
                showsAddButton: false,
                describe: describeEntry,
                onAdd: addEntry
            ) {
                AddModeToggle(mode: $addMode, canAllow: !isLocked)
            }

            if let importNote {
                Text(importNote)
                    .font(PlayType.rounded(11.5))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 50)
                    .padding(.trailing, 14)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }

            InsetDivider(leading: 14)
            preMadeLists

            if !websiteItems.isEmpty || !exceptionItems.isEmpty {
                InsetDivider(leading: 14)
                VStack(alignment: .leading, spacing: 14) {
                    if !websiteItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SmallCaps(text: "Blocked")
                            ChipCloud(items: websiteItems, canRemove: !isLocked)
                        }
                    }
                    if !exceptionItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SmallCaps(text: "Always allowed")
                                .help("These open even when a site or list here would block them")
                            // Taking an exception away only makes the block stricter.
                            ChipCloud(items: exceptionItems, canRemove: true)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .fileImporter(isPresented: $isImportingSites, allowedContentTypes: ListImport.types) { result in
            importSites(result)
        }
    }

    private var preMadeLists: some View {
        VStack(alignment: .leading, spacing: 8) {
            SmallCaps(text: "Common distractions")
            WrapLayout(spacing: 6) {
                ForEach(PreMadeList.allCases) { list in
                    ListPill(
                        list: list,
                        isOn: draft.list.categoryNames.contains(list.rawValue),
                        isFrozen: isLocked && savedBlock?.list.categoryNames.contains(list.rawValue) == true,
                        onToggle: { toggle(list) },
                        onOpen: { editingList = list }
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func toggle(_ list: PreMadeList) {
        animate {
            if draft.list.categoryNames.contains(list.rawValue) {
                draft.list.categoryNames.remove(list.rawValue)
            } else {
                draft.list.categoryNames.insert(list.rawValue)
            }
        }
    }

    /// A list that a locked block includes may grow but never shrink, in every block that
    /// uses it, since the edit is to the list itself.
    private func isHeldByLock(_ list: PreMadeList) -> Bool {
        model.store.blocks.contains { $0.isLocked() && $0.list.categoryNames.contains(list.rawValue) }
    }

    private var websiteItems: [EntryItem] {
        var items: [EntryItem] = []
        for host in draft.list.hosts {
            items.append(EntryItem(id: "h:" + host, title: host, detail: "The whole site", symbol: "globe") {
                draft.list.hosts.removeAll { $0 == host }
            })
        }
        for path in draft.list.paths {
            items.append(EntryItem(id: "p:" + path, title: path, detail: "Only this part", symbol: "link") {
                draft.list.paths.removeAll { $0 == path }
            })
        }
        for rule in draft.list.textRules {
            items.append(EntryItem(
                id: "t:\(rule.scope.rawValue):\(rule.text)",
                title: rule.text,
                detail: rule.scope == .urlPattern ? "Any address that fits" : "Any address with this in it",
                symbol: rule.scope == .urlPattern ? "asterisk" : "textformat"
            ) {
                draft.list.textRules.removeAll { $0 == rule }
            })
        }
        return items
    }

    private var exceptionItems: [EntryItem] {
        draft.list.websiteExceptions.map { exception in
            EntryItem(
                id: "e:" + exception.entry,
                title: exception.entry,
                detail: "Always allowed",
                symbol: "checkmark",
                isOutlined: true
            ) {
                draft.list.websiteExceptions.removeAll { $0.entry == exception.entry }
            }
        }
    }

    /// What the typed entry will do, shown under the field before it's added.
    private func describeEntry(_ text: String) -> String? {
        let entries = Self.entries(in: text)
        guard !entries.isEmpty else { return nil }
        if entries.count > 1 {
            return addMode == .block ? "\(entries.count) to block, all at once" : "\(entries.count) to allow, all at once"
        }
        guard let rule = WebsiteRuleEntry(entries[0]) else { return "That isn’t a site or a word Fence can look for" }
        switch addMode {
        case .block:
            if draft.list.contains(rule) { return "Already blocked" }
            switch rule {
            case .address(let address):
                return address.isDomainOnly ? "The whole site, every page" : "Only this part of \(address.host)"
            case .text(let word):
                return word.scope == .urlPattern
                    ? "Any address that fits this pattern"
                    : "Any address with “\(word.text)” in it, searches too"
            }
        case .allow:
            if draft.list.websiteExceptions.contains(where: { $0.rule == rule }) { return "Already allowed" }
            switch rule {
            case .address(let address):
                return address.isDomainOnly
                    ? "Opens even when a list here blocks it"
                    : "Opens even with \(address.host) blocked"
            case .text(let word):
                return "Any address with “\(word.text)” in it opens"
            }
        }
    }

    /// Several entries can go in at once, separated by commas, or by spaces when each piece
    /// is a site. "live scores" stays one phrase.
    private static func entries(in text: String) -> [String] {
        text.split(whereSeparator: { ",;\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .flatMap { part -> [String] in
                let words = part.split(whereSeparator: \.isWhitespace).map(String.init)
                let allSites = words.allSatisfy { word in
                    if case .address = WebsiteRuleEntry(word) { true } else { false }
                }
                return words.count > 1 && allSites ? words : [part]
            }
    }

    /// Blocks or allows what's typed. An entry is never both: blocking a page that was
    /// allowed takes the exception away, and allowing one that was blocked takes it off.
    private func addEntry(_ text: String) -> String? {
        let entries = Self.entries(in: text)
        var rules: [WebsiteRuleEntry] = []
        for entry in entries {
            guard let rule = WebsiteRuleEntry(entry) else {
                return entries.count == 1
                    ? "Type a site like youtube.com, a page like youtube.com/shorts, or a word like casino."
                    : "Couldn’t read “\(entry)”."
            }
            rules.append(rule)
        }
        switch addMode {
        case .block:
            if rules.count == 1, draft.list.contains(rules[0]) { return "That’s already blocked." }
            animate {
                draft.list.addWebsiteRules(rules)
                draft.list.websiteExceptions.removeAll { exception in rules.contains(exception.rule) }
            }
        case .allow:
            guard !isLocked else { return "Unlock this block to allow pages." }
            if rules.count == 1, draft.list.websiteExceptions.contains(where: { $0.rule == rules[0] }) {
                return "That’s already allowed."
            }
            animate {
                for entry in entries {
                    guard let exception = WebsiteException(entry),
                          !draft.list.websiteExceptions.contains(where: { $0.rule == exception.rule }) else { continue }
                    draft.list.websiteExceptions.append(exception)
                    draft.list.remove(exception.rule)
                }
            }
        }
        return nil
    }

    /// Sites, and apps from JSON. Adding only ever makes a block stricter, so this works
    /// while it's locked too.
    private func importSites(_ result: Result<URL, Error>) {
        do {
            let file = try ListImport.read(result.get())
            let rules = file.entries.compactMap(WebsiteRuleEntry.init)
            var list = draft.list
            var added = list.addWebsiteRules(rules)
            let newApps = file.apps.filter { !list.apps.contains($0) }
            list.apps += newApps
            added += newApps.count
            animate { draft.list = list }
            showImportNote(ListImport.note(added: added, skipped: file.entries.count - rules.count, truncated: file.truncated))
        } catch {
            showImportNote("Couldn’t read that file")
        }
    }

    private func showImportNote(_ note: String) {
        animate { importNote = note }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if importNote == note { animate { importNote = nil } }
        }
    }

    // MARK: Apps

    private var appsSection: some View {
        EditorSection(title: "Apps", symbol: "app.badge") {
            if !appItems.isEmpty {
                ChipCloud(items: appItems, canRemove: !isLocked)
                    .padding(12)
                InsetDivider(leading: 14)
            }

            Button {
                isShowingAppPicker = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Paper.onCoral)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Paper.coral))
                    Text(draft.list.apps.isEmpty ? "Choose apps to block" : "Choose apps")
                        .font(PlayType.rounded(13, .semibold))
                        .foregroundStyle(Paper.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: EditorMetrics.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var appItems: [EntryItem] {
        draft.list.apps.map { bundleID in
            EntryItem(
                id: "a:" + bundleID,
                title: InstalledApps.shared.name(for: bundleID) ?? bundleID,
                detail: "App",
                symbol: "app",
                image: InstalledApps.shared.icon(for: bundleID)
            ) {
                draft.list.apps.removeAll { $0 == bundleID }
            }
        }
    }

    // MARK: When

    /// A row of mode pills that wraps only when it runs out of room; what each choice means
    /// is in its tooltip. "On a schedule" opens a week calendar you drag across, in a
    /// sheet (`ScheduleSheet`, 26 Nov 2026); the card shows the result as plain lines.
    private var whenSection: some View {
        EditorSection(title: "When it’s on", symbol: "calendar", isFrozen: isLocked) {
            VStack(alignment: .leading, spacing: 0) {
                WrapLayout(spacing: 6) {
                    ForEach(ScheduleKind.allCases) { kind in
                        ModePill(symbol: kind.symbol, title: kind.title, isSelected: scheduleKind == kind) {
                            if kind == .scheduled {
                                openSchedule()
                            } else {
                                animate { setScheduleKind(kind) }
                            }
                        }
                        .help(kind.detail)
                    }
                }
                .padding(10)

                if case .scheduled(let windows) = draft.schedule {
                    InsetDivider(leading: 12)
                    scheduleSummary(windows)
                }
            }
            .disabled(isLocked)
            .opacity(isLocked ? 0.55 : 1)
        }
    }

    private enum ScheduleKind: CaseIterable, Identifiable {
        case always, scheduled, manual

        var id: Self { self }

        var title: String {
            switch self {
            case .always: "Always"
            case .scheduled: "On a schedule"
            case .manual: "When I start it"
            }
        }

        var symbol: String {
            switch self {
            case .always: "infinity"
            case .scheduled: "calendar.badge.clock"
            case .manual: "play.circle"
            }
        }

        var detail: String {
            switch self {
            case .always: "On whenever you switch it on"
            case .scheduled: "Turns itself on at set times, like weekdays 9 to 5"
            case .manual: "Start it for 25, 50 or 90 minutes from the Blocks page"
            }
        }
    }

    private var scheduleKind: ScheduleKind {
        switch draft.schedule {
        case .always: .always
        case .scheduled: .scheduled
        case .manual: .manual
        }
    }

    private func setScheduleKind(_ kind: ScheduleKind) {
        switch kind {
        case .always:
            draft.schedule = .always
        case .scheduled:
            if case .scheduled = draft.schedule { return }
            draft.schedule = .scheduled([ScheduleWindow()])
        case .manual:
            if case .manual = draft.schedule { return }
            draft.schedule = .manual(minutes: nil)
        }
    }

    private var currentWindows: [ScheduleWindow] {
        guard case .scheduled(let all) = draft.schedule else { return [] }
        return all
    }

    /// Opens the week calendar in a sheet. Choosing "On a schedule" starts from weekdays
    /// 9 to 5; Cancel puts back whatever was there before.
    private func openSchedule() {
        scheduleBeforeSheet = draft.schedule
        if case .scheduled = draft.schedule {} else {
            animate { draft.schedule = .scheduled([ScheduleWindow()]) }
        }
        isShowingSchedule = true
    }

    /// What the schedule is, in plain lines, with the way into the calendar beside it.
    private func scheduleSummary(_ windows: [ScheduleWindow]) -> some View {
        Button(action: openSchedule) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    if windows.isEmpty {
                        Text("No times yet")
                            .font(PlayType.rounded(12.5, .semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        // One line: today's window if one applies today, else the first.
                        let today = Weekday(rawValue: Calendar.current.component(.weekday, from: .now))
                        let shown = windows.first { today.map($0.days.contains) ?? false } ?? windows[0]
                        Text(shown.summary)
                            .font(PlayType.rounded(12.5, .semibold))
                            .foregroundStyle(Paper.ink)
                            .lineLimit(1)
                        if windows.count > 1 {
                            Text("and \(windows.count - 1) more")
                                .font(PlayType.rounded(11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 8)
                Label("Edit times", systemImage: "calendar")
                    .font(PlayType.rounded(12, .semibold))
                    .foregroundStyle(Paper.coralText)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule(style: .continuous).fill(Paper.coralSoft))
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open the week calendar")
    }

    // MARK: Lock

    /// One row that opens Fence's own lock picker (`LockPicker`), then the chosen method's
    /// settings on one line. No description lines in the card (26 Nov 2026, the user's call).
    private var lockSection: some View {
        EditorSection(title: "Lock", symbol: "lock", isFrozen: isLocked) {
            VStack(alignment: .leading, spacing: 0) {
                LockPicker(method: Binding(
                    get: { draft.lock.method },
                    set: { method in animate { draft.lock.method = method } }
                ))

                if hasLockSettings {
                    InsetDivider(leading: 12)
                    lockSettings
                        .padding(10)
                        .transition(.opacity)
                }
            }
            .disabled(isLocked)
            .opacity(isLocked ? 0.55 : 1)
        }
    }

    private var hasLockSettings: Bool {
        switch draft.lock.method {
        case .duration, .untilTime, .randomString: true
        case .none, .restart: false
        }
    }

    @ViewBuilder private var lockSettings: some View {
        switch draft.lock.method {
        case .duration:
            InlineChoices(label: "For", options: Self.durations, selection: $draft.lock.duration)
                .help("How long it stays locked once it’s switched on")
        case .untilTime:
            UntilTimeChooser(time: $draft.lock.untilTime)
        case .randomString:
            InlineChoices(
                label: "Characters",
                options: BlockLock.challengeLengths.map { ChoiceOption(value: $0, title: "\($0)") },
                selection: Binding(
                    get: { draft.lock.challengeLength },
                    set: { draft.lock.stringLength = $0 }
                )
            )
            .help("How many random characters must be typed to switch it off")
        case .none, .restart:
            EmptyView()
        }
    }

    private static let durations: [ChoiceOption<TimeInterval>] = [
        ChoiceOption(value: 30 * 60, title: "30 min"),
        ChoiceOption(value: 60 * 60, title: "1 hour"),
        ChoiceOption(value: 2 * 60 * 60, title: "2 hours"),
        ChoiceOption(value: 4 * 60 * 60, title: "4 hours"),
        ChoiceOption(value: 8 * 60 * 60, title: "8 hours"),
        ChoiceOption(value: 24 * 60 * 60, title: "1 day"),
    ]

    // MARK: Footer

    private var footer: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button(isNew || hasChanges ? "Cancel" : "Close", action: requestClose)
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)

                Button(action: save) {
                    Text(isNew ? "Create Block" : "Save")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.glassProminent)
                .tint(Paper.coral)
                .controlSize(.large)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!canSave)
                .help(trimmedName.isEmpty ? "Give the block a name first" : "Save (⌘S)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, EditorMetrics.page)
        .padding(.bottom, 18)
    }

    // MARK: Saving

    private func requestClose() {
        if hasChanges {
            isShowingDiscardConfirmation = true
        } else {
            onClose()
        }
    }

    private func save() {
        guard canSave else { return }
        var updated = draft
        updated.name = trimmedName
        if isNew {
            model.store.add(updated)
        } else if !model.store.update(updated) {
            preserveLockedRules()
            isShowingSaveError = true
            return
        }
        onClose()
    }

    /// A draft can already be open when the block is locked from the menu bar.
    /// Restore protected settings while keeping additions and cosmetic edits.
    private func preserveLockedRules() {
        guard let saved = model.store.block(id: draft.id), saved.isLocked() else { return }
        func adding(_ values: [String], to savedValues: [String]) -> [String] {
            var seen = Set(savedValues)
            return savedValues + values.filter { seen.insert($0).inserted }
        }

        var allowed = saved
        allowed.list.hosts = adding(draft.list.hosts, to: saved.list.hosts)
        allowed.list.paths = adding(draft.list.paths, to: saved.list.paths)
        allowed.list.apps = adding(draft.list.apps, to: saved.list.apps)
        allowed.list.textRules += draft.list.textRules.filter { !saved.list.textRules.contains($0) }
        allowed.list.categoryNames.formUnion(draft.list.categoryNames)
        // Preserve concurrent edits. Only removals from the original exceptions tighten a lock.
        let removedExceptions = Set(original.list.websiteExceptions.map(\.entry)).subtracting(draft.list.websiteExceptions.map(\.entry))
        allowed.list.websiteExceptions.removeAll { removedExceptions.contains($0.entry) }
        allowed.name = draft.name
        allowed.tint = draft.tint
        allowed.symbol = draft.symbol
        original = saved
        draft = allowed
    }

    private func animate(_ change: () -> Void) {
        if reduceMotion {
            change()
        } else {
            withAnimation(.snappy(duration: 0.28), change)
        }
    }

    static let symbols = [
        "shield.lefthalf.filled", "moon.stars.fill", "brain.head.profile", "book.closed.fill",
        "briefcase.fill", "gamecontroller.fill", "bubble.left.and.bubble.right.fill", "tv.fill",
        "play.rectangle.fill", "cart.fill", "newspaper.fill", "music.note",
        "camera.fill", "bolt.fill", "leaf.fill", "flame.fill", "sparkles", "hourglass",
    ]
}

// MARK: - Layout

private enum EditorMetrics {
    /// Panel edges.
    static let page: CGFloat = 20
    /// Between sections.
    static let section: CGFloat = 22
    /// Card corners.
    static let radius: CGFloat = 16
    /// A list row's height.
    static let row: CGFloat = 44
}

/// A frosted white card. Translucent so the glass panel's light comes through, opaque under
/// Reduce Transparency.
private struct EditorCard: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: EditorMetrics.radius, style: .continuous)
        content
            .background(shape.fill(reduceTransparency ? Paper.card : Paper.card.opacity(0.8)))
            .clipShape(shape)
            .overlay { shape.strokeBorder(Paper.hairline, lineWidth: 1) }
            .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
    }
}

private extension View {
    func editorCard() -> some View { modifier(EditorCard()) }
}

/// A coral icon and a title above a card, the way macOS titles a grouped form section.
private struct EditorSection<Accessory: View, Content: View>: View {
    let title: String
    let symbol: String
    var isFrozen = false
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Paper.coralText)
                    .accessibilityHidden(true)
                Text(title)
                    .font(PlayType.rounded(14, .bold))
                    .foregroundStyle(Paper.ink)
                    .accessibilityAddTraits(.isHeader)
                if isFrozen {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .help("Can’t change while the block is locked")
                        .accessibilityLabel("Locked")
                }
                Spacer(minLength: 0)
                accessory()
            }
            .frame(minHeight: 26)
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .editorCard()
        }
    }
}

extension EditorSection where Accessory == EmptyView {
    init(title: String, symbol: String, isFrozen: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, symbol: symbol, isFrozen: isFrozen, accessory: { EmptyView() }, content: content)
    }
}

/// A hairline between rows, inset to line up with the row text by default.
private struct InsetDivider: View {
    var leading: CGFloat = 50

    var body: some View {
        Rectangle()
            .fill(Paper.hairline)
            .frame(height: 1)
            .padding(.leading, leading)
    }
}

// MARK: - Chips

private struct EntryItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    var image: NSImage?
    /// Drawn in soft coral, for something the user added to a pre-made list.
    var isHighlighted = false
    /// Drawn as an outline, for a page that's let through rather than blocked.
    var isOutlined = false
    let remove: () -> Void
}

/// Sites and apps as chips, as many to a line as fit (26 Nov 2026, the user's call: rows
/// took too much room). What each one is shows in its tooltip.
private struct ChipCloud: View {
    let items: [EntryItem]
    let canRemove: Bool

    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(items) { item in
                EntryChip(item: item, canRemove: canRemove)
            }
        }
    }
}

/// One thing on a list: its icon, its name, and a small × to take it off.
private struct EntryChip: View {
    let item: EntryItem
    let canRemove: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private func remove() {
        if reduceMotion {
            item.remove()
        } else {
            withAnimation(.snappy(duration: 0.25)) { item.remove() }
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Group {
                if let image = item.image {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: item.symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Paper.ink.opacity(0.5))
                }
            }
            .accessibilityHidden(true)

            Text(item.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Paper.ink)
                .lineLimit(1)
                .truncationMode(.middle)

            if canRemove {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(isHovering ? Paper.onCoral : Paper.ink.opacity(0.55))
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(isHovering ? Paper.coral : Paper.ink.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Remove \(item.title)")
                .accessibilityLabel("Remove \(item.title)")
            }
        }
        .padding(.leading, item.image == nil ? 9 : 6)
        .padding(.trailing, canRemove ? 5 : 10)
        .padding(.vertical, 5)
        .background {
            if item.isOutlined {
                Capsule(style: .continuous).strokeBorder(Paper.ink.opacity(0.22), lineWidth: 1)
            } else {
                Capsule(style: .continuous).fill(item.isHighlighted ? Paper.coralSoft : Paper.tile)
            }
        }
        .contentShape(Capsule())
        .onHover { isHovering = $0 }
        .help("\(item.title) · \(item.detail)")
        .contextMenu {
            if canRemove {
                Button("Remove", role: .destructive, action: remove)
            }
        }
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}

/// A field that adds what's typed when you press Return or click Add. `describe` puts a
/// line under it saying what the entry will do; `accessory` sits at its trailing end.
private struct RuleInput<Accessory: View>: View {
    let prompt: String
    var symbol = "plus"
    var showsAddButton = true
    var describe: ((String) -> String?)?
    let onAdd: (String) -> String?
    let accessory: Accessory

    @State private var text = ""
    @State private var error: String?
    @FocusState private var isFocused: Bool

    init(
        prompt: String,
        symbol: String = "plus",
        showsAddButton: Bool = true,
        describe: ((String) -> String?)? = nil,
        onAdd: @escaping (String) -> String?,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.prompt = prompt
        self.symbol = symbol
        self.showsAddButton = showsAddButton
        self.describe = describe
        self.onAdd = onAdd
        self.accessory = accessory()
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hint: String? { trimmed.isEmpty ? nil : describe?(trimmed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // The same coral circle as "Choose apps" (26 Nov 2026, the user's call).
                // It adds what's typed, or puts the cursor in the field when it's empty.
                Button {
                    if trimmed.isEmpty { isFocused = true } else { submit() }
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Paper.onCoral)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Paper.coral))
                        .contentShape(Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(SquishButtonStyle())
                .help(trimmed.isEmpty ? prompt : "Add \(trimmed)")
                .accessibilityLabel("Add")

                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .onSubmit(submit)

                if showsAddButton && !trimmed.isEmpty {
                    Button("Add", action: submit)
                        .buttonStyle(PillButtonStyle())
                        .fixedSize()
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                accessory
            }
            .padding(.horizontal, 14)
            .frame(minHeight: EditorMetrics.row + 4)

            if let line = error ?? hint {
                Text(line)
                    .font(.system(size: 11.5))
                    .foregroundStyle(error == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Paper.coralText))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 50)
                    .padding(.trailing, 14)
                    .padding(.top, -4)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: trimmed.isEmpty)
        .animation(.snappy(duration: 0.2), value: error ?? hint)
        .onChange(of: text) { _, _ in error = nil }
    }

    private func submit() {
        let entry = trimmed
        guard !entry.isEmpty else { return }
        isFocused = true
        error = onAdd(entry)
        if error == nil { text = "" }
    }
}

extension RuleInput where Accessory == EmptyView {
    init(
        prompt: String,
        symbol: String = "plus",
        showsAddButton: Bool = true,
        describe: ((String) -> String?)? = nil,
        onAdd: @escaping (String) -> String?
    ) {
        self.init(prompt: prompt, symbol: symbol, showsAddButton: showsAddButton, describe: describe, onAdd: onAdd) {
            EmptyView()
        }
    }
}

/// What the Websites field does with what's typed.
private enum AddMode: Hashable { case block, allow }

/// Block or Allow, a small two-way switch at the end of the Websites field. Allowing
/// loosens a block, so it's off while the block is locked.
private struct AddModeToggle: View {
    @Binding var mode: AddMode
    let canAllow: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            segment(.block, "Block", help: "Block what you type")
            segment(.allow, "Allow", help: canAllow
                    ? "Always let what you type through, like one page of a blocked site"
                    : "Unlock this block to allow pages")
        }
        .padding(2)
        .background(Capsule(style: .continuous).fill(Paper.tile))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Block or allow")
    }

    private func segment(_ value: AddMode, _ title: String, help: String) -> some View {
        let isSelected = mode == value
        let isDisabled = value == .allow && !canAllow
        return Button {
            if reduceMotion {
                mode = value
            } else {
                withAnimation(.snappy(duration: 0.22)) { mode = value }
            }
        } label: {
            Text(title)
                .font(PlayType.rounded(11.5, .semibold))
                .foregroundStyle(isSelected ? Paper.ink : Paper.ink.opacity(isDisabled ? 0.3 : 0.6))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Paper.card)
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Choices

/// One mode in a row of them (when it's on): an icon and a short title, drawn exactly like
/// a pre-made list's `ListPill` (26 Nov 2026, the user's call): solid coral once chosen,
/// a soft tile otherwise, a coral wash on hover.
private struct ModePill: View {
    let symbol: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 13)
                Text(title)
                    .font(PlayType.rounded(12, .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Paper.onCoral : Paper.ink.opacity(0.8))
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Paper.coral : (isHovering ? Paper.coralSoft : Paper.tile))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(SquishButtonStyle())
        .onHover { isHovering = $0 }
        .animation(.snappy(duration: 0.2), value: isSelected)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Lock picker

private extension LockMethod {
    /// Short enough for the picker's row.
    var shortTitle: String {
        switch self {
        case .none: "No lock"
        case .duration: "For a while"
        case .untilTime: "Until a time"
        case .randomString: "Typing code"
        case .restart: "Until restart"
        }
    }

    /// One line, shown only inside the open picker, where it helps the choice.
    var pickerLine: String {
        switch self {
        case .none: "Switch it off whenever you like"
        case .duration: "Stays on for as long as you choose"
        case .untilTime: "Stays on until a time of day"
        case .randomString: "Type a random code to switch it off"
        case .restart: "Can’t be switched off until the Mac restarts"
        }
    }
}

/// The lock as one row that opens Fence's own picker, instead of every method laid out at
/// once (26 Nov 2026, the user's call). The row shows the chosen method; the picker lists
/// all five with a tile, a title and one short line each.
private struct LockPicker: View {
    @Binding var method: LockMethod

    @State private var isOpen = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 10) {
                LockTile(method: method, isSelected: method != .none)
                Text(method.shortTitle)
                    .font(PlayType.rounded(13, .semibold))
                    .foregroundStyle(Paper.ink)
                    .contentTransition(.opacity)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(isHovering || isOpen ? Paper.tile : Color.clear))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: EditorMetrics.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(spacing: 2) {
                ForEach(LockMethod.allCases) { option in
                    LockOptionRow(method: option, isSelected: option == method) {
                        method = option
                        isOpen = false
                    }
                }
            }
            .padding(6)
            .frame(width: 290)
        }
        .accessibilityLabel("Lock")
        .accessibilityValue(method.title)
        .accessibilityHint("Opens the lock choices")
    }
}

private struct LockOptionRow: View {
    let method: LockMethod
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                LockTile(method: method, isSelected: isSelected)
                VStack(alignment: .leading, spacing: 1) {
                    Text(method.shortTitle)
                        .font(PlayType.rounded(13, .semibold))
                        .foregroundStyle(Paper.ink)
                    Text(method.pickerLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Paper.coralText)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isHovering ? Paper.coralSoft : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(method.title)
        .accessibilityHint(method.pickerLine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The method's icon on a small rounded tile: coral when chosen, a soft tile otherwise.
private struct LockTile: View {
    let method: LockMethod
    let isSelected: Bool

    var body: some View {
        Image(systemName: method.symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isSelected ? Paper.onCoral : Paper.ink.opacity(0.7))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Paper.coral : Paper.tile)
            )
            .accessibilityHidden(true)
    }
}

private struct ChoiceOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
}

/// An optional short label, then capsule choices, on one line that wraps when it must.
private struct InlineChoices<Value: Hashable>: View {
    var label: String?
    let options: [ChoiceOption<Value>]
    @Binding var selection: Value

    var body: some View {
        WrapLayout(spacing: 6) {
            if let label {
                Text(label)
                    .font(PlayType.rounded(12, .medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .padding(.trailing, 2)
            }
            ForEach(options) { option in
                ChoicePill(title: option.title, isSelected: selection == option.value) {
                    withAnimation(.snappy(duration: 0.22)) { selection = option.value }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label ?? "")
    }
}

/// A capsule choice. The chosen one fills with coral.
private struct ChoicePill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PlayType.rounded(12, .semibold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Paper.onCoral : Paper.ink.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(isSelected ? Paper.coral : Paper.tile))
                .contentShape(Capsule())
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Lock time

/// The lock's end time, with a clear order (26 Nov 2026, the user's call; quick picks used
/// to sit in one row with the time and read as equals). First "Until", the time itself in a
/// stepper nudged a quarter hour at a time, and whether that's today or tomorrow. Under the
/// time, smaller and quieter, a few quick picks.
private struct UntilTimeChooser: View {
    @Binding var time: TimeOfDay

    private static let picks = [
        TimeOfDay(hour: 12, minute: 0),
        TimeOfDay(hour: 17, minute: 0),
        TimeOfDay(hour: 18, minute: 0),
        TimeOfDay(hour: 21, minute: 0),
    ]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Until")
                .font(PlayType.rounded(12, .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    stepper
                    Text(dayWord)
                        .font(PlayType.rounded(11.5, .semibold))
                        .foregroundStyle(.secondary)
                        .help("A time already past today means tomorrow.")
                }

                WrapLayout(spacing: 4) {
                    ForEach(Self.picks, id: \.minutes) { pick in
                        QuickPick(title: pick.formatted, isSelected: time == pick) {
                            withAnimation(.snappy(duration: 0.25)) { time = pick }
                        }
                    }
                }
            }
        }
    }

    /// The time on a soft capsule, with minus and plus inside it.
    private var stepper: some View {
        HStack(spacing: 2) {
            stepButton(symbol: "minus", label: "Fifteen minutes earlier", by: -15)
            Text(time.formatted)
                .font(PlayType.rounded(15, .bold))
                .monospacedDigit()
                .foregroundStyle(Paper.ink)
                .contentTransition(.numericText())
                .frame(minWidth: 72)
            stepButton(symbol: "plus", label: "Fifteen minutes later", by: 15)
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(Paper.tile))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Locked until \(time.formatted)")
    }

    /// Whether the lock would end today or tomorrow if it were switched on now.
    private var dayWord: String {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minutesNow = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        return time.minutes > minutesNow ? "today" : "tomorrow"
    }

    private func stepButton(symbol: String, label: String, by minutes: Int) -> some View {
        Button {
            let day = 24 * 60
            withAnimation(.snappy(duration: 0.25)) {
                time = TimeOfDay(minutes: ((time.minutes + minutes) % day + day) % day)
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Paper.ink.opacity(0.75))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Paper.card))
                .contentShape(Circle())
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel(label)
    }
}

/// A small, quiet shortcut under a main control: outlined text, coral once it's the value.
private struct QuickPick: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PlayType.rounded(11.5, .semibold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Paper.coralText : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule(style: .continuous).fill(isSelected ? Paper.coralSoft : Color.clear))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? Paper.coral.opacity(0.5) : Paper.hairline, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel("Until \(title)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Popovers

/// The block's colour and icon.
private struct AppearancePicker: View {
    @Binding var tint: BlockTint
    @Binding var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SmallCaps(text: "Colour")
            HStack(spacing: 8) {
                ForEach(BlockTint.allCases) { option in
                    let isSelected = tint == option
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { tint = option }
                    } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: 24, height: 24)
                            .overlay {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .heavy))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(3)
                            .overlay {
                                Circle().strokeBorder(isSelected ? option.color : .clear, lineWidth: 2)
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(SquishButtonStyle())
                    .help(option.title)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }

            SmallCaps(text: "Icon")
                .padding(.top, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 6), count: 6), spacing: 6) {
                ForEach(BlockInspector.symbols, id: \.self) { option in
                    let isSelected = symbol == option
                    Button {
                        symbol = option
                    } label: {
                        Image(systemName: option)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.white : Paper.ink.opacity(0.7))
                            .frame(width: 38, height: 38)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? AnyShapeStyle(tint.color) : AnyShapeStyle(Paper.tile))
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(SquishButtonStyle())
                    .accessibilityLabel(option)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Pre-made lists

/// One pre-made list as a pill inside the Websites card: click the name to put the list in
/// this block (solid coral once it's in), or the sliders beside it to see and edit it.
private struct ListPill: View {
    let list: PreMadeList
    let isOn: Bool
    /// In the saved block while it's locked: it can't be taken off.
    let isFrozen: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void

    @State private var lists = PreMadeLists.shared
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                guard !isFrozen else { return }
                onToggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isFrozen ? "lock.fill" : (isOn ? "checkmark" : list.symbol))
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 13)
                    Text(list.title)
                        .font(PlayType.rounded(12, .semibold))
                        .lineLimit(1)
                }
                .padding(.leading, 11)
                .padding(.trailing, 8)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isFrozen
                  ? "Can’t take this off while the block is locked"
                  : pillHelp)
            .accessibilityLabel(list.title)
            .accessibilityValue(isOn ? "blocked" : "not blocked")
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)

            Rectangle()
                .fill(isOn ? Paper.onCoral.opacity(0.35) : Paper.hairline)
                .frame(width: 1, height: 14)

            Button(action: onOpen) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("See and edit \(list.title)")
            .accessibilityLabel("Edit \(list.title)")
        }
        .foregroundStyle(isOn ? Paper.onCoral : Paper.ink.opacity(0.8))
        .background(
            Capsule(style: .continuous)
                .fill(isOn ? Paper.coral : (isHovering ? Paper.coralSoft : Paper.tile))
        )
        .contentShape(Capsule())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Edit \(list.title)…", action: onOpen)
        }
        .animation(.snappy(duration: 0.2), value: isOn)
    }

    private var pillHelp: String {
        let words = lists.wordCount(in: list)
        let wordNote = words > 0 ? " and \(words) word\(words == 1 ? "" : "s")" : ""
        return "\(list.help). \(lists.siteCount(in: list).formatted()) sites\(wordNote)."
    }
}

/// Everything on one pre-made list, as chips, with search. Edits apply to the list itself,
/// so every block using it, and are saved at once to `lists.json`.
private struct PreMadeListEditor: View {
    let list: PreMadeList
    /// False while a locked block includes this list: it can grow, never shrink.
    let canLoosen: Bool

    private enum Pane: Hashable { case sites, words, apps }

    @Environment(\.dismiss) private var dismiss
    @State private var lists = PreMadeLists.shared
    @State private var installed = InstalledApps.shared
    @State private var pane: Pane = .sites
    @State private var search = ""
    @State private var isShowingAppPicker = false
    @State private var isImporting = false
    @State private var importNote: String?

    /// The 18+ list: its built-in sites and words are hidden and can't be searched.
    private var isSealed: Bool { list.isSealed }
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 10) {
                SegmentedSelector(
                    selection: $pane,
                    options: [
                        .init(.sites, "Websites", symbol: "globe"),
                        .init(.words, "Words", symbol: "textformat"),
                        .init(.apps, "Apps", symbol: "app.badge"),
                    ],
                    tint: Paper.coral
                )
                .frame(width: 290)

                Spacer(minLength: 8)

                // No search on the 18+ list: it would turn it into a directory.
                if !isSealed {
                    FenceTextField(prompt: searchPrompt, text: $search, symbol: "magnifyingglass")
                        .frame(width: 170)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Rectangle().fill(Paper.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !canLoosen {
                        Label("A locked block uses this list. You can add to it, but not take anything off.", systemImage: "lock.fill")
                            .font(PlayType.rounded(12, .medium))
                            .foregroundStyle(Paper.coralText)
                    }

                    switch pane {
                    case .sites: sitesPane
                    case .words: wordsPane
                    case .apps: appsPane
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                // Clear of the floating Done button.
                .padding(.bottom, 56)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Paper.coral)
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)
            .padding(18)
        }
        .frame(width: 540, height: 600)
        .background(Paper.background.ignoresSafeArea())
        .onAppear { installed.loadIfNeeded() }
        .onChange(of: pane) { _, _ in search = "" }
        .sheet(isPresented: $isShowingAppPicker) {
            AppPickerView(
                selected: Binding(
                    get: { lists.apps(in: list) },
                    set: { lists.setApps($0, in: list) }
                ),
                canRemove: canLoosen
            )
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: ListImport.types) { result in
            importFile(result)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: list.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Paper.onCoral)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Paper.coral))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(list.title)
                    .font(PlayType.rounded(20, .bold))
                    .foregroundStyle(Paper.ink)
                Text(summary)
                    .font(PlayType.rounded(12))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 8)

            if canLoosen && lists.isEdited(list) {
                Button("Restore defaults") {
                    withAnimation(.snappy(duration: 0.25)) { lists.restoreDefaults(list) }
                }
                .buttonStyle(.plain)
                .font(PlayType.rounded(12, .semibold))
                .foregroundStyle(Paper.coralText)
                .help("Undo every change you’ve made to this list")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var summary: String {
        let sites = lists.siteCount(in: list)
        let words = lists.wordCount(in: list)
        let apps = lists.apps(in: list).count
        var parts = ["\(sites.formatted()) site\(sites == 1 ? "" : "s")"]
        if words > 0 { parts.append("\(words) word\(words == 1 ? "" : "s")") }
        parts.append("\(apps) app\(apps == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    private var searchPrompt: String {
        switch pane {
        case .sites: "Search sites"
        case .words: "Search words"
        case .apps: "Search apps"
        }
    }

    // MARK: Websites

    @ViewBuilder private var sitesPane: some View {
        HStack(spacing: 8) {
            RuleInput(prompt: "Add a site, like example.com") { lists.addSite($0, to: list) }
                .editorCard()
            ImportButton(note: importNote) { isImporting = true }
        }

        if isSealed {
            SealedNote(text: "\(lists.builtInSites(in: list).count.formatted()) sites are built in. They stay hidden, with no search, so this list can’t become a way to find them.")
        }

        let sites = visibleSites
        if !sites.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if isSealed { SmallCaps(text: "Added by you") }
                ChipCloud(items: sites.map(siteItem), canRemove: canLoosen)
            }
        } else if !query.isEmpty {
            Text("No sites match “\(search)”.")
                .font(PlayType.rounded(12))
                .foregroundStyle(.secondary)
        }
    }

    private var visibleSites: [String] {
        if isSealed { return lists.addedSites(in: list) }
        let all = lists.sites(in: list)
        return query.isEmpty ? all : all.filter { $0.contains(query) }
    }

    private func siteItem(_ host: String) -> EntryItem {
        let isAdded = lists.addedSites(in: list).contains(host)
        return EntryItem(
            id: host,
            title: host,
            detail: isAdded ? "Added by you" : "Built in",
            symbol: "globe",
            isHighlighted: isAdded
        ) {
            lists.removeSite(host, from: list)
        }
    }

    // MARK: Words

    /// Any address containing one of these is blocked: a site not on the list yet, a page,
    /// or a search (26 Nov 2026, the user's call). Like every edit here, it's to the list.
    @ViewBuilder private var wordsPane: some View {
        RuleInput(prompt: isSealed ? "Add a word or phrase" : "Add a word, like casino", symbol: "plus") {
            lists.addWord($0, to: list)
        }
        .editorCard()

        if isSealed {
            SealedNote(text: "\(list.builtInWords.count) words and phrases are built in, checked against every page’s address and title. They stay hidden too.")
        }

        let all = isSealed ? lists.addedWords(in: list) : lists.words(in: list)
        let words = query.isEmpty ? all : all.filter { $0.contains(query) }
        if !words.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SmallCaps(text: isSealed ? "Added by you" : "Blocked in an address or title")
                    .help("A page with one of these in its address, title or search is blocked. One word matches anywhere, even inside a site’s name; a phrase matches word for word. Pages you always allow still open.")
                ChipCloud(items: words.map(wordItem), canRemove: canLoosen)
            }
        } else if !isSealed {
            Text(all.isEmpty ? "No words yet. Add one, and any page with it in its address or title is blocked, searches too." : "No words match “\(search)”.")
                .font(PlayType.rounded(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func wordItem(_ word: String) -> EntryItem {
        let isAdded = lists.addedWords(in: list).contains(word)
        return EntryItem(
            id: "w:" + word,
            title: word,
            detail: isAdded ? "Added by you" : "Built in",
            symbol: "textformat",
            isHighlighted: isAdded
        ) {
            lists.removeWord(word, from: list)
        }
    }

    // MARK: Apps

    @ViewBuilder private var appsPane: some View {
        let apps = lists.apps(in: list).filter(matchesSearch)
        let here = apps.filter { installed.installedApp($0) != nil }
        let elsewhere = apps.filter { installed.installedApp($0) == nil }

        HStack(spacing: 8) {
            Button {
                isShowingAppPicker = true
            } label: {
                Label("Choose apps", systemImage: "plus")
                    .font(PlayType.rounded(12, .semibold))
                    .foregroundStyle(Paper.onCoral)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule(style: .continuous).fill(Paper.coral))
                    .contentShape(Capsule())
            }
            .buttonStyle(SquishButtonStyle())
            ImportButton(note: importNote) { isImporting = true }
            Spacer(minLength: 0)
        }

        if !here.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SmallCaps(text: "On this Mac")
                ChipCloud(items: here.map(appItem), canRemove: canLoosen)
            }
        }

        if !elsewhere.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SmallCaps(text: "Blocked if you install them")
                ChipCloud(items: elsewhere.map(appItem), canRemove: canLoosen)
            }
        }

        if apps.isEmpty {
            Text(query.isEmpty ? "No apps on this list." : "No apps match “\(search)”.")
                .font(PlayType.rounded(12))
                .foregroundStyle(.secondary)
        }
    }

    private func matchesSearch(_ bundleID: String) -> Bool {
        guard !query.isEmpty else { return true }
        return appName(bundleID).lowercased().contains(query) || bundleID.lowercased().contains(query)
    }

    private func appName(_ bundleID: String) -> String {
        installed.installedApp(bundleID)?.name ?? PreMadeList.appNames[bundleID] ?? bundleID
    }

    private func appItem(_ bundleID: String) -> EntryItem {
        let app = installed.installedApp(bundleID)
        return EntryItem(
            id: "a:" + bundleID,
            title: appName(bundleID),
            detail: bundleID,
            symbol: "app",
            image: app.map { installed.icon(for: $0) },
            isHighlighted: !list.builtInApps.contains(bundleID)
        ) {
            lists.removeApp(bundleID, from: list)
        }
    }

    // MARK: Import

    private func importFile(_ result: Result<URL, Error>) {
        let note: String
        do {
            let file = try ListImport.read(result.get())
            let sites = lists.addSites(file.entries, to: list)
            let current = lists.apps(in: list)
            let newApps = file.apps.filter { !current.contains($0) }
            if !newApps.isEmpty { lists.setApps(current + newApps, in: list) }
            note = ListImport.note(
                added: sites.added + newApps.count,
                skipped: sites.skipped,
                truncated: file.truncated
            )
        } catch {
            note = "Couldn’t read that file"
        }
        withAnimation { importNote = note }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if importNote == note { withAnimation { importNote = nil } }
        }
    }
}

/// What's built into the 18+ list, said once, in place of the list itself.
private struct SealedNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(PlayType.rounded(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Paper.tile))
    }
}

/// "Import" with a ? beside it that shows the file formats, and the last import's result.
private struct ImportButton: View {
    var note: String?
    let action: () -> Void

    @State private var isShowingFormat = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: action) {
                Label("Import", systemImage: "square.and.arrow.down")
                    .font(PlayType.rounded(12, .semibold))
                    .foregroundStyle(Paper.ink.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule(style: .continuous).fill(Paper.tile))
                    .contentShape(Capsule())
            }
            .buttonStyle(SquishButtonStyle())
            .help("Add sites and apps from a .txt or .json file")
            .fixedSize()

            IconButton(symbol: "questionmark.circle", help: "File formats") {
                isShowingFormat.toggle()
            }
            .popover(isPresented: $isShowingFormat, arrowEdge: .bottom) {
                ImportFormatHelp()
            }

            if let note {
                Text(note)
                    .font(PlayType.rounded(11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - Help

/// Help popovers are examples first, a few plain words each (26 Nov 2026, the user's call:
/// the old ones were paragraphs of rules). Anyone should get it at a glance.
private struct HelpCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(PlayType.rounded(14, .bold))
                .foregroundStyle(Paper.ink)
            content
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
    }
}

/// An example on the left, what it does on the right.
private struct HelpExample: View {
    let example: String
    let meaning: String

    var body: some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(example)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Paper.ink)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Paper.tile))
                .gridColumnAlignment(.leading)
            Text(meaning)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .gridColumnAlignment(.leading)
        }
    }
}

/// A file's contents, as it would look.
private struct HelpFile: View {
    let label: String
    let contents: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(contents)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Paper.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Paper.tile))
                .textSelection(.enabled)
        }
    }
}

private struct WebsiteHelp: View {
    var body: some View {
        HelpCard(title: "What to type") {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                HelpExample(example: "youtube.com", meaning: "The whole site")
                HelpExample(example: "youtube.com/shorts", meaning: "Just that part")
                HelpExample(example: "casino", meaning: "Any address with this word, searches too")
                HelpExample(example: "a.com, b.com", meaning: "Several at once")
            }

            Divider()

            Text("Switch to Allow")
                .font(PlayType.rounded(12, .bold))
                .foregroundStyle(Paper.ink)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                HelpExample(example: "youtube.com/watch", meaning: "Opens, even with YouTube blocked")
            }

            Divider()

            HelpFile(label: "Import a .txt file, one per line, or JSON", contents: """
                instagram.com
                youtube.com/shorts
                """)
        }
    }
}

private struct ImportFormatHelp: View {
    var body: some View {
        HelpCard(title: "Import a list") {
            HelpFile(label: "A text file, one site per line", contents: """
                instagram.com
                reddit.com
                youtube.com/shorts
                """)
            HelpFile(label: "Or a JSON file, which can add apps too", contents: """
                {
                  "sites": ["instagram.com"],
                  "apps": ["com.apple.news"]
                }
                """)
        }
    }
}

/// Reads sites (and apps, from JSON) out of a file.
///
/// - Text: one entry per line, or several separated by commas. Lines starting with `#`,
///   `!` or `//` are comments. Hosts files work: `0.0.0.0 example.com` reads as example.com.
/// - JSON: `["a.com", "b.com"]`, or `{"sites": [...], "apps": [bundle IDs]}`.
private enum ListImport {
    struct File {
        var entries: [String] = []
        var apps: [String] = []
        var truncated = false
    }

    static let types: [UTType] = [.plainText, .json, .commaSeparatedText, .text]
    static let limit = 5_000

    private static let loopbacks: Set<String> = ["0.0.0.0", "127.0.0.1", "::1", "::"]
    private static let localNames: Set<String> = [
        "localhost", "localhost.localdomain", "local", "broadcasthost", "ip6-localhost", "ip6-loopback", "0.0.0.0",
    ]

    private struct JSONList: Decodable {
        var sites: [String]?
        var websites: [String]?
        var apps: [String]?
    }

    static func read(_ url: URL) throws -> File {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count <= 20_000_000 else { throw CocoaError(.fileReadTooLarge) }

        var file = File()
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([String].self, from: data) {
            file.entries = list
        } else if let object = try? decoder.decode(JSONList.self, from: data),
                  object.sites != nil || object.websites != nil || object.apps != nil {
            file.entries = (object.sites ?? []) + (object.websites ?? [])
            file.apps = (object.apps ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        } else {
            file.entries = lines(in: String(decoding: data, as: UTF8.self))
        }
        file.entries = file.entries.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if file.entries.count > limit {
            file.entries = Array(file.entries.prefix(limit))
            file.truncated = true
        }
        return file
    }

    private static func lines(in text: String) -> [String] {
        var result: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = (rawLine.components(separatedBy: " #").first ?? "").trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("!"), !line.hasPrefix("//") else { continue }
            for piece in line.split(whereSeparator: { ",;".contains($0) }) {
                let tokens = piece.split(whereSeparator: \.isWhitespace).map(String.init)
                if let first = tokens.first, loopbacks.contains(first) {
                    result += tokens.dropFirst().filter { !localNames.contains($0) }
                } else {
                    result.append(piece.trimmingCharacters(in: .whitespaces))
                }
            }
            if result.count > limit { break }
        }
        return result
    }

    static func note(added: Int, skipped: Int, truncated: Bool) -> String {
        var parts = [added == 0 ? "Nothing new to add" : "Added \(added.formatted())"]
        if skipped > 0 { parts.append("\(skipped.formatted()) skipped") }
        if truncated { parts.append("first \(limit.formatted()) only") }
        return parts.joined(separator: " · ")
    }
}

private extension InstalledApps {
    /// Bundle IDs aren't always written with the case the app uses.
    func installedApp(_ bundleID: String) -> InstalledApp? {
        apps.first { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }
}

// MARK: - Wrapping layout

/// Fills each row left to right using the items' natural widths, wrapping when full.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(in: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrangement(in: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, layout.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func arrangement(in width: CGFloat?, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let availableWidth = max(0, width ?? .infinity)
        var frames: [CGRect] = []
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0

        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let itemWidth = min(ideal.width, availableWidth)
            if x > 0, x + itemWidth > availableWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: itemWidth, height: ideal.height))
            contentWidth = max(contentWidth, x + itemWidth)
            rowHeight = max(rowHeight, ideal.height)
            x += itemWidth + spacing
        }

        let size = CGSize(width: availableWidth.isFinite ? availableWidth : contentWidth, height: y + rowHeight)
        return (size, frames)
    }
}

// MARK: - App picker

/// Every installed app, searchable, with icons. Replaces sending people to an open panel.
struct AppPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: [String]
    var canRemove = true

    @State private var catalog = InstalledApps.shared
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Choose apps")
                        .font(PlayType.rounded(20, .bold))
                        .foregroundStyle(Paper.ink)
                    Text(selected.isEmpty ? "Nothing chosen yet" : "\(selected.count) chosen")
                        .font(PlayType.rounded(12))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                FenceTextField(prompt: "Search", text: $query, symbol: "magnifyingglass")
                    .frame(width: 200)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Rectangle().fill(Paper.hairline).frame(height: 1)

            if catalog.isLoading {
                ProgressView("Looking for apps…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(catalog.matching(query)) { app in
                            let isSelected = selected.contains(app.bundleID)
                            AppTile(app: app, isSelected: isSelected) {
                                if let index = selected.firstIndex(of: app.bundleID) {
                                    guard canRemove else { return }
                                    selected.remove(at: index)
                                } else {
                                    selected.append(app.bundleID)
                                }
                            }
                            .disabled(isSelected && !canRemove)
                        }
                    }
                    .padding(16)
                    // Clear of the floating Done button.
                    .padding(.bottom, 56)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Paper.coral)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(18)
        }
        .frame(width: 640, height: 520)
        .background(Paper.background.ignoresSafeArea())
        .onAppear { catalog.loadIfNeeded() }
    }
}

private struct AppTile: View {
    let app: InstalledApp
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            HStack(spacing: 8) {
                Image(nsImage: InstalledApps.shared.icon(for: app))
                    .resizable()
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Paper.ink)
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Paper.coral) : AnyShapeStyle(.quaternary))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(shape.fill(isSelected ? Paper.coralSoft : (isHovering ? Paper.card : Paper.card.opacity(0.7))))
            .overlay {
                shape.strokeBorder(isSelected ? Paper.coral : Paper.hairline, lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(SquishButtonStyle())
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
