import AppKit
import SwiftUI

/// Creates or edits one block.
///
/// Laid out as a sheet with a form, because every field here is a setting rather than
/// content. Fields that can't be changed while the block is locked are disabled with the
/// reason shown, instead of silently refusing the save.
struct BlockEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    @State private var draft: Block
    @State private var newHost = ""
    @State private var newApp = ""
    @State private var newKeyword = ""
    @State private var newException = ""

    private let onSave: (Block) -> Void
    private let isLocked: Bool

    init(block: Block, onSave: @escaping (Block) -> Void) {
        _draft = State(initialValue: block)
        self.onSave = onSave
        isLocked = block.lock.isLocked()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                identitySection
                listSection
                scheduleSection
                breaksSection
                lockSection
                frictionSection
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .frame(width: 580, height: 620)
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: Theme.Space.snug) {
            BlockBadge(symbol: draft.symbol, tint: draft.tint, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(draft.name.isEmpty ? "New block" : draft.name)
                    .font(.headline)
                Text(isLocked ? draft.lock.statusText() : "\(draft.contentsSummary) · \(draft.scheduleSummary)")
                    .font(.caption)
                    .foregroundStyle(isLocked ? .orange : .secondary)
            }
            Spacer()
        }
        .padding(Theme.Space.base)
    }

    private var footer: some View {
        HStack {
            if isLocked {
                Label("Locked: you can add to this block but not weaken it.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                onSave(draft)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(Theme.Space.base)
    }

    // MARK: Sections

    private var identitySection: some View {
        Section("Name and look") {
            TextField("Name", text: $draft.name)
            Picker("Colour", selection: $draft.tint) {
                ForEach(BlockTint.allCases) { tint in
                    HStack {
                        Circle().fill(tint.color).frame(width: 10, height: 10)
                        Text(tint.title)
                    }
                    .tag(tint)
                }
            }
            Picker("Icon", selection: $draft.symbol) {
                ForEach(Self.symbols, id: \.self) { symbol in
                    Label(Self.symbolName(symbol), systemImage: symbol).tag(symbol)
                }
            }
        }
    }

    private var listSection: some View {
        Section {
            Picker("Mode", selection: $draft.list.mode) {
                ForEach(BlockList.Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isLocked)

            EntryEditor(
                title: draft.list.mode == .allowlist ? "Allowed websites" : "Websites",
                hint: "instagram.com, or youtube.com/shorts for part of a site",
                entries: websiteBinding,
                newEntry: $newHost,
                canRemove: !isLocked
            )

            EntryEditor(
                title: draft.list.mode == .allowlist ? "Allowed apps" : "Apps",
                hint: "Pick an app, or type a bundle identifier",
                entries: $draft.list.apps,
                newEntry: $newApp,
                canRemove: !isLocked,
                accessory: AnyView(
                    Button("Choose App…", action: chooseApp)
                        .buttonStyle(.bordered)
                )
            )

            if draft.list.mode == .blocklist {
                EntryEditor(
                    title: "On-screen words",
                    hint: "Blocks when these appear on screen. Needs Screen Recording.",
                    entries: $draft.list.keywords,
                    newEntry: $newKeyword,
                    canRemove: !isLocked
                )

                if !draft.list.keywords.isEmpty && !model.screenRecordingGranted {
                    HStack {
                        Label("Screen Recording is off, so these won't fire.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Grant…") { model.requestScreenRecordingPermission() }
                            .buttonStyle(.bordered)
                    }
                }
            }

            EntryEditor(
                title: "Always allow",
                hint: "Exceptions win over everything else in this block",
                entries: $draft.list.exceptions,
                newEntry: $newException,
                canRemove: true
            )
        } header: {
            Text("What this block covers")
        } footer: {
            Text(draft.list.mode == .allowlist
                 ? "Everything except these is blocked while this block is active. Finder and System Settings are never blocked."
                 : "Subdomains are included. A slash makes it a path rule, so the rest of the site keeps working.")
            .foregroundStyle(.secondary)
        }
    }

    private var scheduleSection: some View {
        Section {
            Picker("When", selection: scheduleKind) {
                Text("All the time").tag(ScheduleKind.always)
                Text("On a schedule").tag(ScheduleKind.scheduled)
                Text("Start on demand").tag(ScheduleKind.manual)
            }
            .disabled(isLocked)

            if case .scheduled(let windows) = draft.schedule {
                ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                    ScheduleWindowEditor(
                        window: Binding(
                            get: { window },
                            set: { updated in
                                guard case .scheduled(var all) = draft.schedule else { return }
                                all[index] = updated
                                draft.schedule = .scheduled(all)
                            }
                        ),
                        onDelete: {
                            guard case .scheduled(var all) = draft.schedule else { return }
                            all.remove(at: index)
                            draft.schedule = .scheduled(all)
                        }
                    )
                    .disabled(isLocked)
                }
                Button("Add a time window") {
                    guard case .scheduled(var all) = draft.schedule else { return }
                    all.append(ScheduleWindow())
                    draft.schedule = .scheduled(all)
                }
                .buttonStyle(.bordered)
                .disabled(isLocked)
            }

            if case .manual(let minutes) = draft.schedule {
                Picker("Length", selection: Binding(
                    get: { minutes ?? 0 },
                    set: { draft.schedule = .manual(minutes: $0 == 0 ? nil : $0) }
                )) {
                    Text("Until I turn it off").tag(0)
                    Text("25 minutes").tag(25)
                    Text("50 minutes").tag(50)
                    Text("90 minutes").tag(90)
                }
                .disabled(isLocked)
            }
        } header: {
            Text("When it applies")
        }
    }

    private var breaksSection: some View {
        Section {
            Toggle("Allow breaks", isOn: $draft.breaks.isEnabled)
                .disabled(isLocked)
            if draft.breaks.isEnabled {
                Stepper("Each break lasts \(draft.breaks.minutes) min", value: $draft.breaks.minutes, in: 1...60)
                    .disabled(isLocked)
                Stepper("Allow \(draft.breaks.allowance) per day", value: $draft.breaks.allowance, in: 1...20)
                    .disabled(isLocked)
            }
        } header: {
            Text("Breaks")
        } footer: {
            Text("Breaks are decided in advance, not in the moment. The shield offers one only when the block allows it and you have some left.")
                .foregroundStyle(.secondary)
        }
    }

    private var lockSection: some View {
        Section {
            Picker("Lock", selection: $draft.lock.method) {
                ForEach(LockMethod.allCases) { method in
                    Label(method.title, systemImage: method.symbol).tag(method)
                }
            }
            .disabled(isLocked)

            switch draft.lock.method {
            case .duration:
                Picker("Stays on for", selection: $draft.lock.duration) {
                    Text("30 minutes").tag(TimeInterval(1800))
                    Text("1 hour").tag(TimeInterval(3600))
                    Text("4 hours").tag(TimeInterval(14400))
                    Text("8 hours").tag(TimeInterval(28800))
                    Text("24 hours").tag(TimeInterval(86400))
                }
                .disabled(isLocked)
            case .untilTime:
                TimeOfDayPicker(label: "Stays on until", time: $draft.lock.untilTime)
                    .disabled(isLocked)
            case .randomString:
                Stepper("String length \(draft.lock.stringLength)", value: $draft.lock.stringLength, in: 8...128, step: 8)
                    .disabled(isLocked)
            case .none, .restart:
                EmptyView()
            }
        } header: {
            Text("Lock")
        } footer: {
            Text(draft.lock.method.detail + " The lock engages the moment you switch the block on.")
                .foregroundStyle(.secondary)
        }
    }

    private var frictionSection: some View {
        Section {
            Picker("Friction", selection: $draft.friction) {
                ForEach(Friction.allCases) { level in
                    Label(level.title, systemImage: level.symbol).tag(level)
                }
            }
            TextField("Goal (optional)", text: $draft.goal, prompt: Text("e.g. Finish chapter 3"))
        } header: {
            Text("When you hit it")
        } footer: {
            Text(draft.friction.summary + " The goal, when set, is shown on the shield and will drive the intent tier later.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private enum ScheduleKind: Hashable { case always, scheduled, manual }

    private var scheduleKind: Binding<ScheduleKind> {
        Binding(
            get: {
                switch draft.schedule {
                case .always: .always
                case .scheduled: .scheduled
                case .manual: .manual
                }
            },
            set: { kind in
                switch kind {
                case .always: draft.schedule = .always
                case .scheduled:
                    if case .scheduled = draft.schedule { return }
                    draft.schedule = .scheduled([ScheduleWindow()])
                case .manual:
                    if case .manual = draft.schedule { return }
                    draft.schedule = .manual(minutes: 50)
                }
            }
        )
    }

    /// Hosts and paths are one list to the user; the model keeps them apart so the
    /// evaluator can match them differently.
    private var websiteBinding: Binding<[String]> {
        Binding(
            get: { draft.list.hosts + draft.list.paths },
            set: { combined in
                draft.list.hosts = combined.filter { !$0.contains("/") }
                draft.list.paths = combined.filter { $0.contains("/") }
            }
        )
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            if !draft.list.apps.contains(id) { draft.list.apps.append(id) }
        }
    }

    static let symbols = [
        "shield.lefthalf.filled", "moon.fill", "laptopcomputer", "book.closed.fill",
        "brain.head.profile", "briefcase.fill", "gamecontroller.fill", "bubble.left.and.bubble.right.fill",
        "tv.fill", "cart.fill", "newspaper.fill", "bolt.fill",
    ]

    static func symbolName(_ symbol: String) -> String {
        symbol
            .replacingOccurrences(of: ".fill", with: "")
            .replacingOccurrences(of: ".", with: " ")
            .capitalized
    }
}

// MARK: - Entry editor

/// A labelled list of strings with add and remove. Used for every list in the editor so
/// they all behave identically.
struct EntryEditor: View {
    let title: String
    let hint: String
    @Binding var entries: [String]
    @Binding var newEntry: String
    var canRemove: Bool = true
    var accessory: AnyView?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            Text(title)
                .font(.callout.weight(.medium))

            HStack(spacing: Theme.Space.tight) {
                TextField(hint, text: $newEntry)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .buttonStyle(.bordered)
                    .disabled(newEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                if let accessory {
                    accessory
                }
            }

            if entries.isEmpty {
                Text("Nothing yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Space.tight)],
                    alignment: .leading,
                    spacing: Theme.Space.tight
                ) {
                    ForEach(entries, id: \.self) { entry in
                        HStack(spacing: 4) {
                            Text(entry)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if canRemove {
                                Button {
                                    entries.removeAll { $0 == entry }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Remove \(entry)")
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.background.secondary, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func add() {
        let value = newEntry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty, !entries.contains(value) else { return }
        entries.append(value)
        newEntry = ""
    }
}

// MARK: - Schedule pieces

struct ScheduleWindowEditor: View {
    @Binding var window: ScheduleWindow
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HStack {
                ForEach(Weekday.allCases) { day in
                    Button {
                        if window.days.contains(day) {
                            window.days.remove(day)
                        } else {
                            window.days.insert(day)
                        }
                    } label: {
                        Text(day.letter)
                            .font(.caption.weight(.semibold))
                            .frame(width: 24, height: 24)
                            .background(
                                window.days.contains(day) ? Color.accentColor : Color.secondary.opacity(0.15),
                                in: Circle()
                            )
                            .foregroundStyle(window.days.contains(day) ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.shortTitle)
                    .accessibilityValue(window.days.contains(day) ? "on" : "off")
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove this time window")
            }

            HStack(spacing: Theme.Space.base) {
                TimeOfDayPicker(label: "From", time: $window.start)
                TimeOfDayPicker(label: "To", time: $window.end)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A time-of-day field backed by `DatePicker`, so the user gets the system's own control
/// and locale formatting rather than something bespoke.
struct TimeOfDayPicker: View {
    let label: String
    @Binding var time: TimeOfDay

    private var binding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = time.hour
                components.minute = time.minute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                time = TimeOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0)
            }
        )
    }

    var body: some View {
        DatePicker(label, selection: binding, displayedComponents: .hourAndMinute)
    }
}
