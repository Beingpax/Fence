import SwiftUI

/// The menu bar popover: start a session, see the live verdict, get out.
///
/// HIG: a menu bar extra is a quick-access surface, not an app window. Everything here is
/// one glance or one click deep, the width stays narrow, and anything longer lives in Settings.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.base) {
            header

            Divider()

            if let session = model.session {
                ActiveSessionView(session: session)
            } else {
                StartSessionView()
            }

            Divider()

            LiveContextView()

            if !model.activity.isEmpty {
                Divider()
                ActivityListView()
            }

            Divider()

            footer
        }
        .padding(Theme.Space.base + 2)
        .frame(width: Theme.menuWidth)
        .onAppear {
            model.refreshPermissions()
            model.refreshSystemState()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Shift")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Spacer()
            if let session = model.session {
                Label(session.strictness.title, systemImage: session.strictness.symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            } else {
                Text("On-device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var footer: some View {
        HStack(spacing: Theme.Space.tight) {
            Menu("Preview shield") {
                ForEach(1...3, id: \.self) { strike in
                    Button("Strike \(strike)") { model.previewShield(strike: strike) }
                }
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()

            Spacer()

            SettingsLink {
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
            .help(model.canQuitApp ? "Quit Shift" : "Locked session: Shift can't be quit until it ends")
            .accessibilityLabel("Quit Shift")
        }
        .font(.callout)
    }
}

// MARK: - Start

private struct StartSessionView: View {
    @Environment(AppModel.self) private var model
    @State private var goal = ""
    @State private var minutes = 50
    @State private var strictness: Strictness = .firm

    private var trimmedGoal: String {
        goal.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            SectionLabel(text: "What are you working on?")

            TextField("e.g. Finish chapter 3 of my thesis", text: $goal, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .onSubmit(start)

            Picker("Duration", selection: $minutes) {
                Text("25 min").tag(25)
                Text("50 min").tag(50)
                Text("90 min").tag(90)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Picker("Strictness", selection: $strictness) {
                ForEach(Strictness.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(alignment: .top, spacing: Theme.Space.tight) {
                Image(systemName: strictness.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(strictness.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: start) {
                Text(strictness == .locked ? "Start locked session" : "Start focus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(trimmedGoal.isEmpty)
            .keyboardShortcut(.defaultAction)

            if strictness == .locked {
                Label("You won't be able to end this early or quit Shift.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .calmTransition(.opacity)
            }
        }
    }

    private func start() {
        guard !trimmedGoal.isEmpty else { return }
        model.startSession(goal: goal, minutes: minutes, strictness: strictness)
        goal = ""
    }
}

// MARK: - Active

private struct ActiveSessionView: View {
    @Environment(AppModel.self) private var model
    let session: FocusSession

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            SectionLabel(text: "Focusing on")
            Text(session.goal)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = session.remaining(at: context.date)
                VStack(alignment: .leading, spacing: Theme.Space.tight) {
                    Text(format(remaining))
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .accessibilityLabel("\(Int(remaining / 60)) minutes remaining")

                    ProgressView(value: progress(remaining))
                        .progressViewStyle(.linear)
                        .tint(session.strictness == .locked ? .orange : .accentColor)
                        .accessibilityHidden(true)
                }
            }

            HStack {
                StrikeDots(strikes: session.strikes)
                Spacer()
                Text("\(session.strikes) strike\(session.strikes == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("End session") { model.endSession() }
                .buttonStyle(.glass)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!model.canEndSession)
                .help(model.canEndSession ? "End this session now" : "Locked: this session can't be ended early")
        }
    }

    private func progress(_ remaining: TimeInterval) -> Double {
        guard session.duration > 0 else { return 1 }
        return min(max(1 - remaining / session.duration, 0), 1)
    }

    private func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct StrikeDots: View {
    let strikes: Int

    var body: some View {
        HStack(spacing: Theme.Space.hair + 2) {
            ForEach(1...3, id: \.self) { index in
                Circle()
                    .fill(index <= strikes ? Color.orange : Color.secondary.opacity(0.22))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
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
                Text(model.session == nil ? "Start a session to see live context." : "Waiting for the first reading…")
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

// MARK: - Activity

private struct ActivityListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.hair + 2) {
            SectionLabel(text: "Recent")
            ForEach(model.activity.prefix(5)) { event in
                HStack(spacing: Theme.Space.tight) {
                    Image(systemName: event.symbol)
                        .frame(width: 14)
                        .foregroundStyle(.secondary)
                    Text(event.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: Theme.Space.tight)
                    Text(event.date, style: .time)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
