import AppKit
import QuartzCore
import SwiftUI

/// Draws a view that changes every frame, touching as little of its window as SwiftUI allows.
///
/// A `TimelineView(.animation)` updates the whole SwiftUI graph it lives in on every tick.
/// Measured with Instruments on 26 Nov 2026: the Dashboard's mascot (two 30 fps canvases,
/// about 7 ms of drawing a second) cost the dashboard 33% CPU, because each tick also
/// re-measured the window's whole view tree for its size limits and made the sidebar's
/// Liquid Glass re-resolve its interaction state about eight times (some 470 graph updates
/// a second). The heads-up card cost the helper 10% for the same reason.
///
/// Here the view is hosted in a graph of its own, inside a plain view with a fixed size,
/// and `FrameClock` hands it `frame(date)` up to `framesPerSecond` times a second. The
/// window still lays out once per frame (a nested hosting view always reports its updates
/// to the one around it), but that's one cheap pass instead of eight full ones.
///
/// Tried and dropped on the way, so nobody tries them again:
/// - A `TimelineView` inside the nested hosting view never advances.
/// - Drawing each frame with `ImageRenderer` into a layer avoids layout entirely but
///   rasterises on the CPU, and cost more than this.
///
/// Suits drawing that doesn't depend on the environment (`frame` gets none from outside but
/// the window's appearance and system accessibility settings) and takes no input. While
/// `running` is false nothing ticks and the last frame stays, as a paused `TimelineView` would.
struct OwnRenderLoop<Content: View>: NSViewRepresentable {
    /// False holds the current frame still.
    let running: Bool
    var framesPerSecond: Float = 30
    let frame: (Date) -> Content

    func makeNSView(context: Context) -> FrameLoopView<Content> {
        let view = FrameLoopView(first: frame(Date()))
        view.framesPerSecond = framesPerSecond
        view.render = frame
        view.setRunning(running)
        return view
    }

    func updateNSView(_ view: FrameLoopView<Content>, context: Context) {
        // Called only when something outside changed (a new mood, the minute turning), so
        // drawing once more here is cheap, and it shows the change even while paused.
        view.framesPerSecond = framesPerSecond
        view.render = frame
        view.drawFrame()
        view.setRunning(running)
    }

    /// Whatever SwiftUI offers: the caller gives this a fixed frame. Answering here means
    /// SwiftUI never has to measure the view, which it otherwise did after every frame.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FrameLoopView<Content>, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    static func dismantleNSView(_ view: FrameLoopView<Content>, coordinator: ()) {
        view.setRunning(false)
    }
}

/// A decoration view: transparent, never the target of a click, and redrawn only by
/// `FrameClock`. A plain view holding the hosting view, so nothing outside sees a size that
/// could change.
final class FrameLoopView<Content: View>: NSView, FrameClockSubscriber {
    var render: ((Date) -> Content)?
    var framesPerSecond: Float = 30 {
        didSet { if framesPerSecond != oldValue, isSubscribed { FrameClock.shared.subscriptionsChanged() } }
    }

    private let hosting: PassThroughHostingView<Content>
    private var wantsFrames = false
    private var isSubscribed = false

    init(first: Content) {
        hosting = PassThroughHostingView(rootView: first)
        super.init(frame: .zero)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateSubscription()
    }

    func setRunning(_ running: Bool) {
        wantsFrames = running
        updateSubscription()
    }

    /// Hands the hosted view its next frame.
    func drawFrame() {
        guard let render else { return }
        hosting.rootView = render(Date())
    }

    /// Ticks only while frames are wanted and the view is in a window: a closed window or a
    /// paused animation leaves nothing ticking.
    private func updateSubscription() {
        let needed = wantsFrames && window != nil
        guard needed != isSubscribed else { return }
        isSubscribed = needed
        if needed {
            FrameClock.shared.add(self)
        } else {
            FrameClock.shared.remove(self)
        }
    }
}

/// Something `FrameClock` redraws.
@MainActor
protocol FrameClockSubscriber: AnyObject {
    var framesPerSecond: Float { get }
    func drawFrame()
}

/// One display link for every `OwnRenderLoop`, so views animating together (the mascot's
/// body and hands, drawn as two layers) take their frames in the same pass. With a link
/// each, they ticked out of step and the window laid itself out twice per frame. Nothing
/// ticks while nothing is subscribed.
@MainActor
final class FrameClock {
    static let shared = FrameClock()

    private var subscribers: [ObjectIdentifier: () -> FrameClockSubscriber?] = [:]
    private var link: CADisplayLink?
    private lazy var ticker = DisplayLinkTicker { [weak self] in self?.tick() }
    private var screenObserver: NSObjectProtocol?

    func add(_ subscriber: FrameClockSubscriber) {
        subscribers[ObjectIdentifier(subscriber)] = { [weak subscriber] in subscriber }
        subscriptionsChanged()
    }

    func remove(_ subscriber: FrameClockSubscriber) {
        subscribers[ObjectIdentifier(subscriber)] = nil
        subscriptionsChanged()
    }

    /// Starts, retunes or stops the link to suit whoever is subscribed.
    func subscriptionsChanged() {
        let rates = subscribers.values.compactMap { $0()?.framesPerSecond }
        guard let fastest = rates.max() else {
            stop()
            return
        }
        interval = 1.0 / CFTimeInterval(fastest)
        if link == nil { start() }
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: min(15, fastest), maximum: fastest, preferred: fastest)
    }

    private func start() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let link = screen.displayLink(target: ticker, selector: #selector(DisplayLinkTicker.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        // A link belongs to one display; follow the main one if displays change.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stop()
                self?.subscriptionsChanged()
            }
        }
    }

    private func stop() {
        link?.invalidate()
        link = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    /// When the last frame went out, on the media clock.
    private var lastFrame: CFTimeInterval = 0
    private var interval: CFTimeInterval = 1.0 / 30

    private func tick() {
        // The link can run faster than asked (it ran at about 55 fps for a 30 fps request
        // on a 60 Hz display), so the rate is held here, as `TimelineView`'s
        // `minimumInterval` did. A little slack keeps 30 fps from dropping to 20 on jitter.
        let now = CACurrentMediaTime()
        guard now - lastFrame >= interval - 0.004 else { return }
        lastFrame = now
        var gone: [ObjectIdentifier] = []
        for (id, subscriber) in subscribers {
            if let subscriber = subscriber() { subscriber.drawFrame() } else { gone.append(id) }
        }
        guard !gone.isEmpty else { return }
        gone.forEach { subscribers[$0] = nil }
        subscriptionsChanged()
    }
}

/// Draws on the GPU like any SwiftUI view, but never measures itself, never insets for the
/// title bar and never takes a click.
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
        safeAreaRegions = []
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
    override var isOpaque: Bool { false }
}

/// The display link's target: it has to be an Objective-C object, and it holds no strong
/// reference back, so the link never keeps anything alive.
@MainActor
final class DisplayLinkTicker: NSObject {
    private let onTick: @MainActor () -> Void

    init(onTick: @escaping @MainActor () -> Void) {
        self.onTick = onTick
    }

    @objc func tick(_ link: CADisplayLink) {
        onTick()
    }
}
