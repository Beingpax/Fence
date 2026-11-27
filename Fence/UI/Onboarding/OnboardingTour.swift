import AppKit
import SwiftUI

/// Onboarding's tour: Fence acted out inside setup's own window, one guided step at a time.
///
/// The window becomes a browser. A guide card says what will happen, how, and what to do
/// next; a coral pointer marks where to click or swipe; and Fence answers the way it really
/// would, with the real card drawing and copy and the real pause view on today's photo.
/// Nothing runs on a clock: every step waits for the person (26 Nov 2026, the user's call;
/// a first version let the heads-up's ten seconds run out on their own). Nothing is
/// blocked, closed or journaled.
///
/// Chosen by the user on 26 Nov 2026 over two earlier tries: a real block on example.com
/// (the real flow, unguided), and tour cards in the screen corner beside a list of stops.
struct OnboardingTour: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Finished: setup moves on.
    let onFinish: () -> Void
    /// Left early: back to the tour's page.
    let onExit: () -> Void

    private enum Scene: Hashable {
        /// 1. The browser's start page, Instagram one click away.
        case startPage
        /// 2. Instagram open and the heads-up in the corner. Waits for it to be dismissed.
        case headsUp
        /// 3. The card is gone but the (paused) clock isn't: close the tab, or skip ahead.
        case cardDismissed
        /// 4. Closed in time: the cheer.
        case turnedBack
        /// 4. Stayed past ten seconds: what the pause will ask, before it opens.
        case pauseIntro
        /// 4. The real pause, full window.
        case pause
        /// 5. Answered the pause and closed.
        case closedAfterPause
        /// 5. "I need it" at the pause.
        case access(minutes: Int)
    }

    private static let site = "instagram.com"

    @State private var scene: Scene = .startPage
    @State private var card: NudgeContent?
    @State private var sawCheer = false
    @State private var sawPause = false
    @State private var wallpaper: PauseWallpaper?
    @State private var pauseRequest: PauseRequest?
    @State private var dragOffset: CGFloat = 0

    private var showsFeed: Bool {
        switch scene {
        case .headsUp, .cardDismissed, .pauseIntro, .pause, .access: true
        default: false
        }
    }

    var body: some View {
        ZStack {
            FakeBrowser(
                showsFeed: showsFeed,
                highlightsInstagram: scene == .startPage,
                highlightsClose: scene == .cardDismissed,
                onOpenInstagram: { openInstagram() },
                onCloseTab: { closeTab() }
            )

            if scene == .pause, let wallpaper, let pauseRequest {
                PauseView(request: pauseRequest, wallpaper: wallpaper, onEvent: { handlePause($0) })
                    .transition(.opacity)
            }

            pointers
            nudgeCorner
            guideCorner

            exitButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 12)
                .padding(.trailing, 14)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.84), value: scene)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.8), value: card)
    }

    // MARK: The corner card

    private var nudgeCorner: some View {
        ZStack(alignment: .bottomTrailing) {
            if let card {
                NudgeCardPreview(content: card)
                    .offset(x: max(0, dragOffset))
                    .contentShape(Rectangle())
                    .onTapGesture { dismissCard() }
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { dragOffset = $0.translation.width }
                            .onEnded { value in
                                if value.translation.width > 60 {
                                    dismissCard()
                                } else {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { dragOffset = 0 }
                                }
                            }
                    )
                    // A two-finger swipe, as on the real card.
                    .overlay { TrackpadSwipe { dismissCard() } }
                    .help("Click it, or swipe it away")
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .id(card.headline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }

    private func dismissCard() {
        guard card != nil else { return }
        withAnimation { card = nil }
        dragOffset = 0
        if scene == .headsUp {
            withAnimation { scene = .cardDismissed }
        }
    }

    // MARK: Pointers

    /// Coral labels that say exactly where to act: beside the card, and under the tab's ×.
    @ViewBuilder
    private var pointers: some View {
        if scene == .headsUp, card != nil {
            PointerLabel(text: "Click or swipe right to dismiss", arrow: "arrow.right")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                // Left of the card (300 wide, 20 from the edge), level with its words.
                .padding(.trailing, 336)
                .padding(.bottom, 64)
                .transition(.opacity)
        }
        if scene == .cardDismissed {
            PointerLabel(text: "Close the tab", arrow: "arrow.up", arrowLeading: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Under the tab's ×: the tab starts at 84 and is 190 wide.
                .padding(.leading, 236)
                .padding(.top, 62)
                .transition(.opacity)
        }
    }

    // MARK: The guide

    /// The tour's voice is a friend's, about Lumi as a character, and says why each moment
    /// happens rather than how it's built (26 Nov 2026, the user's call). Few words, few labels.
    private var guideCorner: some View {
        Group {
            switch scene {
            case .startPage:
                TourGuide(
                    step: 1,
                    title: "Reach for a distraction",
                    text: "We all do it without thinking. Click Instagram, and \(Mascot.name) will show you what happens next."
                )
            case .headsUp:
                TourGuide(
                    step: 2,
                    title: "\(Mascot.name) taps you on the shoulder",
                    text: "Before the feed can hook you, \(Mascot.name) lets you know. Nothing is blocked yet: you get ten seconds to leave on your own, because a choice you make yourself is the one that sticks."
                )
            case .cardDismissed:
                TourGuide(
                    step: 3,
                    title: "\(Mascot.name) is still counting",
                    text: "Waving \(Mascot.name) away doesn’t stop the ten seconds. Close the tab and you’ll get a cheer. Stay, and \(Mascot.name) steps in with a pause."
                ) {
                    Button("Stay on the page") { showPauseIntro() }
                        .buttonStyle(GuideButtonStyle(isPrimary: false))
                }
            case .turnedBack:
                TourGuide(
                    step: 4,
                    title: "\(Mascot.name) is cheering",
                    text: "Turning back gets celebrated, right away. A reward in the moment is what turns one good choice into a habit."
                ) {
                    HStack(spacing: 8) {
                        if !sawPause {
                            Button("See the pause") { showPauseIntro() }
                                .buttonStyle(GuideButtonStyle(isPrimary: true))
                        }
                        Button("Finish", action: onFinish)
                            .buttonStyle(GuideButtonStyle(isPrimary: sawPause))
                    }
                }
            case .pauseIntro:
                TourGuide(
                    step: 4,
                    title: "\(Mascot.name) steps in",
                    text: "Still there after ten seconds? \(Mascot.name) clears the screen for a short pause. Not a punishment: a little room to choose."
                ) {
                    VStack(alignment: .leading, spacing: 9) {
                        PauseStepLine(number: 1, title: "Breathe", why: "Urges rise and fade. One breath is often enough.")
                        PauseStepLine(number: 2, title: "Name the pull", why: "Putting a feeling into words loosens its grip.")
                        PauseStepLine(number: 3, title: "Turn back", why: "One click. The right choice should also be the easy one.")
                    }
                    .padding(.bottom, 4)
                    Button("Show me") { startPause() }
                        .buttonStyle(GuideButtonStyle(isPrimary: true))
                }
            case .pause:
                PauseHint()
            case .closedAfterPause:
                TourGuide(
                    step: 5,
                    title: "That’s the whole pause",
                    text: "For real, the tab closes now. Your words stay on this Mac, so later you can see what really pulls you, and when."
                ) {
                    HStack(spacing: 8) {
                        if !sawCheer {
                            Button("Try turning back", action: tryTurningBack)
                                .buttonStyle(GuideButtonStyle(isPrimary: false))
                        }
                        Button("Finish", action: onFinish)
                            .buttonStyle(GuideButtonStyle(isPrimary: true))
                    }
                }
            case .access(let minutes):
                TourGuide(
                    step: 5,
                    title: "When you truly need it",
                    text: "Just that one site opens for \(minutes) minutes, then \(Mascot.name) checks in again. Real needs get through; habits don’t."
                ) {
                    Button("Finish", action: onFinish)
                        .buttonStyle(GuideButtonStyle(isPrimary: true))
                }
            }
        }
        .id(scene)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: scene == .pause ? .topLeading : .bottomLeading)
        // On the pause, a single line up by the traffic lights, clear of the pause's own words.
        .padding(.leading, scene == .pause ? 84 : 20)
        .padding(.top, scene == .pause ? 11 : 0)
        .padding(.bottom, 20)
    }

    private var exitButton: some View {
        Button(action: onExit) {
            HStack(spacing: 5) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .black))
                Text("Exit tour")
            }
            .font(PlayType.rounded(12, .bold))
            .foregroundStyle(scene == .pause ? Color.white : Paper.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule(style: .continuous).fill(scene == .pause ? Color.white.opacity(0.16) : Paper.tile))
            .overlay(Capsule(style: .continuous).strokeBorder(scene == .pause ? Color.white.opacity(0.2) : Paper.hairline, lineWidth: 1))
        }
        .buttonStyle(SquishButtonStyle())
        .keyboardShortcut(.cancelAction)
    }

    // MARK: Steps

    private func openInstagram() {
        guard scene == .startPage else { return }
        withAnimation { scene = .headsUp }
        Task {
            // A beat for the page to appear, as detection takes a moment in real life too.
            try? await Task.sleep(for: .milliseconds(450))
            guard scene == .headsUp else { return }
            let copy = PauseCopy.warning(name: Self.site, blockName: "Distractions", count: 1, closesTab: true, variant: 0)
            card = NudgeContent(headline: copy.headline, detail: copy.detail, kind: .warning, mood: copy.mood)
        }
    }

    /// The tab's ×. Works with the card still up too: closing straight away is turning back.
    private func closeTab() {
        guard scene == .headsUp || scene == .cardDismissed else { return }
        sawCheer = true
        withAnimation { scene = .turnedBack }
        cheer(PauseCopy.rewardForTurningBackEarly())
    }

    private func showPauseIntro() {
        card = nil
        withAnimation { scene = .pauseIntro }
    }

    private func startPause() {
        card = nil
        sawPause = true
        let copy = PauseCopy.pause(visit: 1)
        pauseRequest = PauseRequest(
            blockName: "Distractions", blockID: nil, ruleTarget: .website(Self.site), target: Self.site,
            appName: "Safari", isBrowser: true, visit: 1, title: copy.title, subtitle: copy.subtitle
        )
        if wallpaper == nil { wallpaper = PauseWallpaper() }
        if model.playNudgeSounds { NudgeSound.playPause() }
        withAnimation(.easeInOut(duration: 0.45)) { scene = .pause }
    }

    private func handlePause(_ event: PauseEvent) {
        switch event {
        case .close(let reason, _):
            withAnimation(.easeInOut(duration: 0.4)) { scene = .closedAfterPause }
            cheer(PauseCopy.reward(for: reason, visit: 1))
        case .takeBreak(let minutes, let note):
            withAnimation(.easeInOut(duration: 0.4)) { scene = .access(minutes: minutes) }
            card = NudgeContent(
                headline: "\(Self.site) is open",
                detail: note.isEmpty ? "The pause comes back when time’s up." : note,
                kind: .access, mood: .resting,
                endsAt: Date().addingTimeInterval(TimeInterval(minutes) * 60)
            )
        }
    }

    private func cheer(_ line: PauseCopy.Reward) {
        card = nil
        if model.playNudgeSounds { NudgeSound.playReward() }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            card = NudgeContent(headline: line.title, detail: line.subtitle, kind: .reward, mood: line.mood)
        }
    }

    private func tryTurningBack() {
        card = nil
        withAnimation { scene = .startPage }
    }
}

// MARK: - The guide card

/// The tour's voice: a dark card in the corner with where you are, a title, what's happening
/// and why, and sometimes a button or two.
private struct TourGuide<Actions: View>: View {
    let step: Int
    let title: String
    let text: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(step) of 5")
                .font(PlayType.rounded(11, .bold))
                .foregroundStyle(Paper.coralSolid)
            Text(title)
                .font(PlayType.rounded(17, .bold))
                .foregroundStyle(.white)
            Text(text)
                .font(PlayType.rounded(13))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
            let extras = actions()
            if !(extras is EmptyView) {
                VStack(alignment: .leading, spacing: 8) { extras }
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.13, green: 0.12, blue: 0.11))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }
}

extension TourGuide where Actions == EmptyView {
    init(step: Int, title: String, text: String) {
        self.init(step: step, title: title, text: text) { EmptyView() }
    }
}

/// One of the pause's three asks: what it is, and why it helps.
private struct PauseStepLine: View {
    let number: Int
    let title: String
    let why: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .font(PlayType.rounded(11, .heavy))
                .foregroundStyle(Paper.onCoralSolid)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Paper.coralSolid))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(PlayType.rounded(13, .bold))
                    .foregroundStyle(.white)
                Text(why)
                    .font(PlayType.rounded(12))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The guide while the pause is up: one line by the traffic lights, so it never sits on
/// the pause's own words.
private struct PauseHint: View {
    var body: some View {
        Text("Breathe, name the pull, and you’re free to go.")
            .font(PlayType.rounded(12, .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule(style: .continuous).fill(Color.black.opacity(0.45)))
            .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
    }
}

/// A coral label pointing at the thing to act on, nudging gently towards it.
private struct PointerLabel: View {
    let text: String
    let arrow: String
    var arrowLeading = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nudged = false

    private var isVertical: Bool { arrow == "arrow.up" || arrow == "arrow.down" }

    var body: some View {
        HStack(spacing: 7) {
            if arrowLeading { arrowImage }
            Text(text)
                .font(PlayType.rounded(13, .bold))
            if !arrowLeading { arrowImage }
        }
        .foregroundStyle(Paper.onCoralSolid)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(Capsule(style: .continuous).fill(Paper.coralSolid))
        .shadow(color: Paper.coralSolid.opacity(0.35), radius: 10, y: 4)
        .offset(x: isVertical ? 0 : (nudged ? 6 : 0), y: isVertical ? (nudged ? -5 : 0) : 0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { nudged = true }
        }
        .allowsHitTesting(false)
    }

    private var arrowImage: some View {
        Image(systemName: arrow)
            .font(.system(size: 12, weight: .black))
    }
}

private struct GuideButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PlayType.rounded(12, .bold))
            .foregroundStyle(isPrimary ? Paper.onCoralSolid : .white)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(Capsule(style: .continuous).fill(isPrimary ? Paper.coralSolid : Color.white.opacity(0.14)))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Swipe

/// Turns a two-finger sideways swipe into a dismissal, as the real card does. SwiftUI
/// gestures don't see trackpad scrolls, so this view reads them itself, and it only claims
/// scroll events: clicks pass straight through to the card.
private struct TrackpadSwipe: NSViewRepresentable {
    let onSwipe: () -> Void

    func makeNSView(context: Context) -> SwipeView {
        let view = SwipeView()
        view.onSwipe = onSwipe
        return view
    }

    func updateNSView(_ view: SwipeView, context: Context) {
        view.onSwipe = onSwipe
    }

    final class SwipeView: NSView {
        var onSwipe: (() -> Void)?
        private var travel: CGFloat = 0
        private var fired = false

        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }

        override func scrollWheel(with event: NSEvent) {
            guard event.hasPreciseScrollingDeltas else { return super.scrollWheel(with: event) }
            switch event.phase {
            case .began:
                travel = 0
                fired = false
            case .changed:
                travel += event.scrollingDeltaX
                if !fired, abs(travel) > 36, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                    fired = true
                    onSwipe?()
                }
            case .ended, .cancelled:
                travel = 0
                fired = false
            default:
                break
            }
        }
    }
}

// MARK: - The browser

/// A browser drawn to fill setup's window: a tab with its ×, an address bar, and either a
/// start page of favourites or a feed sketched in soft grey. Clear of the traffic lights.
private struct FakeBrowser: View {
    let showsFeed: Bool
    let highlightsInstagram: Bool
    let highlightsClose: Bool
    let onOpenInstagram: () -> Void
    let onCloseTab: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(Paper.hairline).frame(height: 1)
            ZStack {
                Paper.background
                if showsFeed {
                    Feed().transition(.opacity)
                } else {
                    startPage.transition(.opacity)
                }
            }
        }
        .background(Paper.background)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            // The tab.
            HStack(spacing: 7) {
                Image(systemName: showsFeed ? "camera.fill" : "star.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(showsFeed ? Paper.ink : Paper.coralSolid))
                Text(showsFeed ? "Instagram" : "Start Page")
                    .font(PlayType.rounded(12, .semibold))
                    .foregroundStyle(Paper.ink)
                Spacer(minLength: 6)
                if showsFeed {
                    Button(action: onCloseTab) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(highlightsClose ? Paper.onCoralSolid : Paper.ink.opacity(0.6))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(highlightsClose ? Paper.coralSolid : Paper.tile))
                            .overlay { if highlightsClose { Pulse(shape: Circle()) } }
                    }
                    .buttonStyle(SquishButtonStyle())
                    .help("Close the tab")
                    .accessibilityLabel("Close the tab")
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(width: 190, height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Paper.card))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Paper.hairline, lineWidth: 1))

            // The address.
            HStack(spacing: 6) {
                Image(systemName: showsFeed ? "lock.fill" : "magnifyingglass")
                    .font(.system(size: 9, weight: .bold))
                Text(showsFeed ? "instagram.com" : "Search or enter website")
                    .font(PlayType.rounded(12, showsFeed ? .semibold : .regular))
            }
            .foregroundStyle(Paper.ink.opacity(showsFeed ? 0.8 : 0.4))
            .frame(maxWidth: 320)
            .frame(height: 30)
            .background(Capsule(style: .continuous).fill(Paper.tile))

            Spacer(minLength: 110)
        }
        // Clear of the window's traffic lights.
        .padding(.leading, 84)
        .padding(.trailing, 14)
        .frame(height: 52)
        .background(Paper.card)
    }

    private var startPage: some View {
        VStack(spacing: 18) {
            Text("Favourites")
                .font(PlayType.rounded(15, .bold))
                .foregroundStyle(Paper.ink.opacity(0.7))
            HStack(spacing: 18) {
                favourite("Instagram", symbol: "camera.fill", isLive: true)
                favourite("Docs", symbol: "doc.text.fill", isLive: false)
                favourite("Calendar", symbol: "calendar", isLive: false)
                favourite("Maps", symbol: "map.fill", isLive: false)
            }
        }
        .padding(.bottom, 60)
    }

    private func favourite(_ name: String, symbol: String, isLive: Bool) -> some View {
        let highlighted = isLive && highlightsInstagram
        return Button(action: { if isLive { onOpenInstagram() } }) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(highlighted ? Paper.onCoralSolid : Paper.ink.opacity(0.55))
                    .frame(width: 68, height: 68)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(highlighted ? Paper.coralSolid : Paper.card))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Paper.hairline.opacity(highlighted ? 0 : 1), lineWidth: 1))
                    .overlay { if highlighted { Pulse(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)) } }
                    .shadow(color: highlighted ? Paper.coralSolid.opacity(0.35) : .black.opacity(0.05), radius: highlighted ? 14 : 6, y: 4)
                Text(name)
                    .font(PlayType.rounded(12, .semibold))
                    .foregroundStyle(Paper.ink.opacity(isLive ? 0.85 : 0.45))
            }
        }
        .buttonStyle(SquishButtonStyle())
        .disabled(!isLive)
        .accessibilityLabel(name)
    }
}

/// A coral ring that breathes outward from whatever the guide wants clicked.
private struct Pulse<S: InsettableShape>: View {
    let shape: S
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var out = false

    var body: some View {
        shape
            .strokeBorder(Paper.coralSolid, lineWidth: 2)
            .scaleEffect(out ? 1.35 : 1)
            .opacity(out ? 0 : 0.9)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { out = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A feed sketched in soft shapes: stories along the top, then posts. No real content.
private struct Feed: View {
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                ForEach(0..<6, id: \.self) { index in
                    Circle()
                        .fill(Paper.tile)
                        .overlay(Circle().strokeBorder(Paper.coralSolid.opacity(index < 3 ? 0.7 : 0.2), lineWidth: 2.5))
                        .frame(width: 46, height: 46)
                }
            }
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle().fill(Paper.tile).frame(width: 26, height: 26)
                        Capsule().fill(Paper.ink.opacity(0.12)).frame(width: 90, height: 8)
                    }
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Paper.tile)
                        .frame(height: 200)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 30, weight: .light))
                                .foregroundStyle(Paper.ink.opacity(0.15))
                        }
                }
                .frame(width: 380)
            }
        }
        .padding(.top, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .accessibilityHidden(true)
    }
}
