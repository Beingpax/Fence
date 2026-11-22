import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                ActivityListView()
            }

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { model.refreshPermissions() }
    }

    private var header: some View {
        HStack {
            Text("Shift")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Spacer()
            Text("Local AI · on-device")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
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

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .disabled(!model.canQuitApp)
                .help(model.canQuitApp ? "Quit Shift" : "Locked session: Shift can't be quit until it ends")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What are you working on?")
                .font(.headline)

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
                    Label(level.title, systemImage: level.symbol).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(strictness.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: start) {
                Text("Start focus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(goal.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func start() {
        model.startSession(goal: goal, minutes: minutes, strictness: strictness)
        goal = ""
    }
}

// MARK: - Active

private struct ActiveSessionView: View {
    @Environment(AppModel.self) private var model
    let session: FocusSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focusing on")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(session.goal)
                .font(.headline)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(format(session.remaining(at: context.date)))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            HStack {
                Label(session.strictness.title, systemImage: session.strictness.symbol)
                Spacer()
                Label("\(session.strikes) strike\(session.strikes == 1 ? "" : "s")", systemImage: "hand.raised")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Button("End session") { model.endSession() }
                .disabled(!model.canEndSession)
                .help(model.canEndSession ? "" : "Locked: this session can't be ended early")
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - What Shift sees

private struct LiveContextView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What Shift sees")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let context = model.lastContext {
                row("App", context.appName)
                if let title = context.windowTitle { row("Window", title) }
                if let host = context.hostAndPath { row("Page", host) }
                if let verdict = model.lastVerdict {
                    HStack(alignment: .firstTextBaseline) {
                        VerdictPill(kind: verdict.kind)
                        Text(verdict.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } else {
                Text(model.session == nil ? "Start a session to see live context." : "Waiting for the first reading…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !model.accessibilityGranted {
                Button {
                    PermissionsManager.openAccessibilitySettings()
                } label: {
                    Label("Grant Accessibility to read window titles", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.orange)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct VerdictPill: View {
    let kind: Verdict.Kind

    var body: some View {
        Text(kind.rawValue.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch kind {
        case .allow: .green
        case .nudge: .orange
        case .block: .red
        }
    }
}

// MARK: - Activity

private struct ActivityListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(model.activity.prefix(5)) { event in
                HStack(spacing: 6) {
                    Image(systemName: event.symbol)
                        .frame(width: 14)
                        .foregroundStyle(.secondary)
                    Text(event.text)
                        .lineLimit(1)
                    Spacer()
                    Text(event.date, style: .time)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
            }
        }
    }
}
