import SwiftUI

/// Every place the mascot appears, with the words it appears with and the mood those words
/// call for. Opened from Settings → Previews → "Mascot gallery".
///
/// Nudge cards are drawn by `NudgeCardPreview`, the same card the HUD shows, and in-app
/// cards by `MascotCard`, the same one onboarding, Blocks and the Dashboard use. Reward
/// examples are taken from `PauseCopy`, each with the mood written beside it, so they show what the
/// app really pairs. Keep the other examples in step with their screens when copy changes.
struct MascotGallery: View {
    @Environment(\.dismiss) private var dismiss
    /// Built once, so the tiles keep their identity and their mascots keep moving.
    @State private var sections = MascotGallery.makeSections()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(MascotMood.allCases.count) MOODS")
                        .font(PlayType.rounded(11, .bold))
                        .tracking(0.9)
                        .foregroundStyle(Paper.coralText)
                    Text("Mascot gallery")
                        .font(PlayType.rounded(26, .bold))
                        .foregroundStyle(Paper.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, PlayRhythm.page)
            .padding(.top, 22)
            .padding(.bottom, PlayRhythm.section)

            ScrollView {
                VStack(alignment: .leading, spacing: PlayRhythm.page) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: PlayRhythm.inner) {
                            SmallCaps(text: section.title)
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 340), spacing: PlayRhythm.section, alignment: .top)],
                                alignment: .leading,
                                spacing: PlayRhythm.section
                            ) {
                                ForEach(section.examples) { example in
                                    ExampleTile(example: example)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, PlayRhythm.page)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 780, height: 720)
        .background(Paper.background)
    }
}

// MARK: - Examples

private struct GallerySection: Identifiable {
    let title: String
    let examples: [GalleryExample]
    var id: String { title }
}

private struct GalleryExample: Identifiable {
    enum Surface {
        /// The floating nudge card.
        case nudge(NudgeContent)
        /// A paper card inside the main window.
        case paper(title: String, detail: String)
    }

    let id = UUID()
    let mood: MascotMood
    /// When this appears, in a few words.
    let when: String
    let surface: Surface

    static func nudge(_ kind: NudgeContent.Kind, _ mood: MascotMood, when: String, _ headline: String, _ detail: String) -> Self {
        GalleryExample(mood: mood, when: when, surface: .nudge(NudgeContent(headline: headline, detail: detail, kind: kind, mood: mood)))
    }

    static func paper(_ mood: MascotMood, when: String, _ title: String, _ detail: String) -> Self {
        GalleryExample(mood: mood, when: when, surface: .paper(title: title, detail: detail))
    }

    /// The heads-up before the pause, with its words and button as the app writes them.
    @MainActor
    static func warning(count: Int, when: String, name: String, closesTab: Bool) -> Self {
        let copy = PauseCopy.warning(name: name, blockName: "Distractions", count: count, closesTab: closesTab, variant: 0)
        return GalleryExample(mood: copy.mood, when: when, surface: .nudge(NudgeContent(
            headline: copy.headline, detail: copy.detail, kind: .warning, mood: copy.mood)))
    }

    /// A real turning-back line and the mood the app pairs with it.
    static func reward(_ line: PauseCopy.Reward, when: String) -> Self {
        .nudge(.reward, line.mood, when: when, line.title, line.subtitle)
    }
}

private extension MascotGallery {
    static func firstLine(_ lines: [PauseCopy.Reward], _ mood: MascotMood) -> PauseCopy.Reward {
        lines.first { $0.mood == mood } ?? lines[0]
    }

    @MainActor
    static func makeSections() -> [GallerySection] {
        [
            GallerySection(title: "Before the pause", examples: [
                .warning(count: 1, when: "A blocked site, the first time in an hour",
                         name: "x.com", closesTab: true),
                .warning(count: 2, when: "The same site again within the hour",
                         name: "x.com", closesTab: true),
                .warning(count: 3, when: "A third time within the hour",
                         name: "x.com", closesTab: true),
                .warning(count: 1, when: "A blocked app",
                         name: "Steam", closesTab: false),
                .reward(PauseCopy.turnedBackEarly[0], when: "Moved on during the heads-up"),
            ]),
            GallerySection(title: "Drift hints", examples: [
                .nudge(.hint, .curious, when: "The first drift hint in half an hour",
                       "“Shorts” looks like a feed", "youtube.com"),
                .nudge(.hint, .cheeky, when: "The same drift again soon after",
                       "“Reels” looks like a feed", "instagram.com"),
                .nudge(.hint, .worried, when: "A third drift hint in half an hour",
                       "“For You” looks like a feed", "x.com"),
            ]),
            GallerySection(title: "Turning back", examples: [
                .reward(firstLine(PauseCopy.turnedBack, .happy), when: "Turning back: most lines"),
                .reward(firstLine(PauseCopy.turnedBack, .cheer), when: "Turning back: an exuberant line"),
                .reward(firstLine(PauseCopy.turnedBack, .proud), when: "Turning back: a line about strength"),
                .reward(PauseCopy.turnedBackAgain[0], when: "Turning back on a repeat reach"),
                .reward(PauseCopy.changedMind[0], when: "Closing after “I need it”"),
                .reward(PauseCopy.turnedBackBecause[.stuck]?.first ?? PauseCopy.turnedBack[0],
                        when: "Turning back after “This is hard”"),
            ]),
            GallerySection(title: "Access and problems", examples: [
                GalleryExample(mood: .resting, when: "“I need it” access, counting down", surface: .nudge(NudgeContent(
                    headline: "x.com is open", detail: "Reply to Sam about Friday’s plans before the meeting.",
                    kind: .access, mood: .resting, endsAt: Date().addingTimeInterval(5 * 60)))),
                .nudge(.status, .worried, when: "Access couldn’t start",
                       "Access didn’t start.", "x.com wasn’t open anymore."),
                .nudge(.status, .worried, when: "A tab couldn’t be closed",
                       "Couldn’t close that tab.", "Please close it yourself this time."),
                .nudge(.status, .worried, when: "You need to close it yourself",
                       "Please close the tab yourself.",
                       "To do it for you, I need access in \(PermissionsManager.BrowserAccessPane.current.settingsPath)."),
            ]),
            GallerySection(title: "In the app", examples: [
                .paper(.hello, when: "Onboarding, the first page", "Make room for focus",
                       "Shift gently stops you before a distraction pays out, and cheers when you turn back."),
                .paper(.happy, when: "Onboarding, the last page", "Name your first block",
                       "A block is a set of sites and apps with its own schedule and lock."),
                .paper(.thinking, when: "Blocks, before there are any", "Let’s make your first block",
                       "Pick the sites and apps that pull at you, and when. I’ll step in before they load."),
                .paper(.idle, when: "Dashboard, on a normal day", "Good morning",
                       "Distractions has your back until 5:00 PM."),
                .paper(.hello, when: "Dashboard, with no blocks yet", "Good morning",
                       "Make a block and I’ll stand guard over your day."),
                .paper(.curious, when: "Dashboard, a permission missing", "Good morning",
                       "One setting needs your OK before I can guard you properly. It’s just above."),
            ]),
            GallerySection(title: "Not used yet", examples: [
                .nudge(.status, .shy, when: "Welcome back after a while",
                       "Welcome back.", "Nice to see you."),
            ]),
        ]
    }
}

// MARK: - A tile

private struct ExampleTile: View {
    let example: GalleryExample

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: PlayRhythm.inner) {
            HStack(spacing: PlayRhythm.tile) {
                Text(example.mood.title)
                    .font(PlayType.rounded(11, .bold))
                    .foregroundStyle(Paper.coralText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(Paper.coralSoft))
                Text(example.when)
                    .font(PlayType.rounded(12, .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            surface
                .frame(maxWidth: .infinity)
        }
        .padding(PlayRhythm.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(radius: 20)
    }

    @ViewBuilder
    private var surface: some View {
        switch example.surface {
        case .nudge(let content):
            NudgeCardPreview(content: content)
        case .paper(let title, let detail):
            MascotCard(mood: example.mood, start: start, animates: !reduceMotion) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(PlayType.rounded(16, .bold))
                        .foregroundStyle(Paper.ink)
                    Text(detail)
                        .font(PlayType.rounded(12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(PlayRhythm.card)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 300)
        }
    }
}
