import SwiftUI

/// Who the mascot is. Named on 26 Nov 2026 at the user's request so onboarding can talk
/// about it as a character ("Lumi taps you on the shoulder"), not a card that slides in.
/// Lumi, for light: the bulb on its antenna glows with its mood.
/// One place, so a rename is one line.
enum Mascot {
    static let name = "Lumi"
}

/// What the mascot is feeling. Every mood from the studies (`Studies/mascot-compare.html`),
/// grouped as they are there. Each card picks the one that fits its words, so the same kind
/// of card can wear different moods: a drift hint is curious, then cheeky, then worried; a
/// reward is happy, cheering or proud depending on the line it shows.
enum MascotMood: String, CaseIterable, Equatable, Sendable {
    // Everyday
    /// Fence is on, nothing to do. Plain status lines.
    case idle
    /// Waving: onboarding and first launch.
    case hello
    /// Hand on chin: empty states.
    case thinking
    /// Sinks a little, blushing: welcome back after a while.
    case shy

    // Nudges
    /// A question mark: the first drift hint.
    case curious
    /// One eyebrow up, a sly smile: the same drift again soon after.
    case cheeky
    /// Sweating, ears down: drift that keeps coming back, or something that didn't work.
    case worried
    /// Steaming, tapping its fingers on the card: the heads-up before the pause.
    case annoyed

    // Rewards
    /// Waving, sparkles: you turned back.
    case happy
    /// Both fists up: an exuberant turn back.
    case cheer
    /// Chin up, thumb up, gold light: turning back when it was hard.
    case proud

    // Access and bad news
    /// Dozing, sinking behind the card, dim light: "I need it" access has started.
    case resting
    /// A tear, drooping: the heads-up, a third time in an hour.
    case sad

    /// Its name in Settings' preview.
    var title: String {
        switch self {
        case .idle: "Idle"
        case .hello: "Hello"
        case .thinking: "Thinking"
        case .shy: "Shy"
        case .curious: "Curious"
        case .cheeky: "Cheeky"
        case .worried: "Worried"
        case .annoyed: "Annoyed"
        case .happy: "Happy"
        case .cheer: "Cheer"
        case .proud: "Proud"
        case .resting: "On a break"
        case .sad: "Sad"
        }
    }

    /// When it's used, for Settings' preview.
    var use: String {
        switch self {
        case .idle: "Plain status lines."
        case .hello: "Onboarding and first launch."
        case .thinking: "Empty states."
        case .shy: "Welcome back after a while."
        case .curious: "The first drift hint."
        case .cheeky: "The same drift again soon after."
        case .worried: "Drift that keeps coming back, or something that didn’t work."
        case .annoyed: "The heads-up before the pause."
        case .happy: "Turning back."
        case .cheer: "Turning back, with a celebration."
        case .proud: "Turning back when it was hard."
        case .resting: "“I need it” access has started."
        case .sad: "The heads-up, a third time in an hour."
        }
    }
}

/// Fence's mascot: a marigold creature with round ears, white mitten hands and an antenna
/// whose bulb carries the mood. It peeks over the top of the nudge card and holds its edge.
///
/// Chosen from HTML studies (`Studies/mascot-compare.html`, "Classic") over a glossy 3D
/// direction. What makes it work:
///
/// - **A flat cartoon with an ink outline.** One cel-shaded crescent and one highlight give
///   it volume without gradients, so it stays crisp at any size and reads at a glance.
/// - **The antenna light is the mood you see from the corner of your eye**: warm at rest,
///   teal when curious, amber when worried, deep red when annoyed, gold when proud, blue
///   when sad, dim on a break.
/// - **It holds the card.** The hands curl over the card's top edge, so the card and the
///   creature read as one object rather than a sticker beside a banner. Moods let go of the
///   edge to wave, cheer or point.
///
/// Every number here comes from the study's mood table. The study draws in "scene" units
/// 1.9 times the size of these, so its positions appear divided by 1.9.
///
/// The card sits between two layers, so the view is drawn twice: `.body` behind the card
/// (the parent clips it at the card's edge) and `.hands` in front of it. Both layers take
/// the same `start`, so they move on one clock.
///
/// Everything is drawn in fixed design units (the body is 96 wide) and scaled by `scale`.
struct MascotView: View {
    enum Layer { case body, hands }

    let mood: MascotMood
    let layer: Layer
    /// False under Reduce Motion: the creature still draws, it just holds still.
    let animates: Bool
    let start: Date
    /// Points per design unit for this copy. The Dashboard's greeting tile draws a smaller one.
    var pointScale: CGFloat = MascotView.scale

    /// Holds the idle still while its window is closed, minimised or covered.
    @Environment(\.windowIsVisible) private var windowIsVisible

    /// Points per design unit.
    static let scale: CGFloat = 1.2
    /// The drawable area in design units, with the body's centre at the origin. Wide enough
    /// for a raised hand, tall enough for the antenna's glow.
    private static let box = CGRect(x: -82, y: -94, width: 164, height: 146)
    /// Where the card's top edge falls, in design units.
    private static let cardEdge: CGFloat = 38

    static var size: CGSize { CGSize(width: box.width * scale, height: box.height * scale) }
    /// Distance from the top of the view to the card's top edge, in points.
    static var cardEdgeOffset: CGFloat { (cardEdge - box.minY) * scale }

    /// The drawing box at another scale.
    static func size(pointScale: CGFloat) -> CGSize {
        CGSize(width: box.width * pointScale, height: box.height * pointScale)
    }

    /// The card's top edge at another scale.
    static func cardEdgeOffset(pointScale: CGFloat) -> CGFloat { (cardEdge - box.minY) * pointScale }

    var body: some View {
        // Drawn in a hosting view of its own, on its own 30 fps clock, so a frame redraws
        // only the canvas and not the window around it (`OwnRenderLoop`).
        OwnRenderLoop(running: animates && windowIsVisible) { [mood, layer, animates, start, pointScale] date in
            MascotFrame(
                mood: mood,
                layer: layer,
                animates: animates,
                t: animates ? date.timeIntervalSince(start) : 0.7,
                pointScale: pointScale
            )
        }
        .frame(width: Self.box.width * pointScale, height: Self.box.height * pointScale)
        .accessibilityHidden(true)
    }

    /// One frame of the idle, `t` seconds in.
    fileprivate struct MascotFrame: View {
        let mood: MascotMood
        let layer: Layer
        let animates: Bool
        let t: TimeInterval
        var pointScale: CGFloat = MascotView.scale

        var body: some View {
            Canvas(rendersAsynchronously: false) { context, _ in
                context.translateBy(x: -MascotView.box.minX * pointScale, y: -MascotView.box.minY * pointScale)
                context.scaleBy(x: pointScale, y: pointScale)
                let rig = MascotRig(pose: mood.pose, t: t, moving: animates, cardEdge: MascotView.cardEdge)
                switch layer {
                case .body: rig.drawBody(in: &context)
                case .hands: rig.drawHands(in: &context)
                }
            }
            .frame(width: MascotView.box.width * pointScale, height: MascotView.box.height * pointScale)
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Moods

/// Every expression is a handful of numbers. The rig draws whatever they say.
private struct MascotPose {
    enum Pulse { case gentle, cross }

    // Body and motion
    var look: (x: Double, y: Double) = (0, 0)
    /// Pupil size, 1 normal. Small pupils read as alarm.
    var pupil = 1.0
    var blush = 0.35
    /// A red wash over the top of the head.
    var flush = 0.0
    /// Degrees, about the feet.
    var tilt = 0.0
    /// Positive flattens, negative stretches.
    var squash = 0.0
    /// Little hops, 0 to 1.
    var bounce = 0.0
    var bobAmplitude = 1.6
    var bobSpeed = 2.0
    /// Sinks behind the card, 0 to 1.
    var sink = 0.0

    // Antenna
    var glow: Color = MascotPalette.glowWarm
    var glowStrength = 0.85
    var pulse = Pulse.gentle
    var antennaDroop = 0.0

    // Face
    /// Degrees outward from upright. Positive droops them.
    var ears: (left: Double, right: Double) = (0, 0)
    /// How far each brow lifts, 0 to 1.
    var brows: (left: Double, right: Double) = (0.15, 0.15)
    /// Positive lifts the inner ends of the brows (worry); negative pulls them down (anger).
    var browAngle = 0.0
    var eyeSize = 1.0
    /// Closed, upturned eyes.
    var eyesSmiling = false
    /// Eyes squeezed shut: > <.
    var eyesSqueezed = false
    /// Upper eyelids, 0 open to 1 closed.
    var lid = 0.0
    /// -1 frowns, 1 smiles.
    var mouthCurve = 0.45
    /// 0 closed, 1 wide open.
    var mouthOpen = 0.0
    var mouthWidth = 6.0
    var mouthX = 0.0
    var faceY = 0.0

    // Effects, 0 to 1
    var sparkle = 0.0, zzz = 0.0, question = 0.0, sweat = 0.0, tear = 0.0, steam = 0.0

    // Hands: each pulls both hands from their grip on the card toward a pose.
    var wave = 0.0, fist = 0.0, thumb = 0.0, chin = 0.0, tap = 0.0
    /// Grips the card closer to the middle.
    var handsIn = 0.0
}

private extension MascotMood {
    // The study's mood table, in the same order. Its classic-only numbers (ears, brows,
    // eyes, mouth) and shared numbers (motion, effects, hands) are merged into one pose.
    var pose: MascotPose {
        var p = MascotPose()
        switch self {
        case .idle:
            break
        case .hello:
            p.tilt = -4; p.look = (0.15, 0); p.blush = 0.5; p.bounce = 0.15; p.wave = 1
            p.brows = (0.45, 0.45); p.mouthCurve = 0.85; p.mouthOpen = 0.35; p.mouthWidth = 7; p.ears = (0, -10)
            p.glow = MascotPalette.glowBright
        case .thinking:
            p.tilt = -6; p.look = (-0.5, -0.7); p.bobAmplitude = 1; p.chin = 1
            p.ears = (14, 0); p.brows = (0.75, 0.2); p.mouthCurve = -0.05; p.mouthWidth = 4; p.mouthX = 4
            p.glow = MascotPalette.glowTeal
        case .shy:
            p.blush = 1; p.look = (-0.6, 0.45); p.tilt = -8; p.handsIn = 0.6; p.sink = 0.12
            p.lid = 0.25; p.mouthCurve = 0.35; p.mouthWidth = 3; p.ears = (22, 22)
        case .curious:
            p.tilt = 8; p.look = (0.55, -0.25); p.question = 1; p.handsIn = 0.2
            p.ears = (-12, 28); p.brows = (0.05, 0.95); p.mouthCurve = 0.1; p.mouthWidth = 4
            p.glow = MascotPalette.glowTeal
        case .cheeky:
            p.tilt = 6; p.look = (0.65, 0); p.glowStrength = 1
            p.lid = 0.42; p.brows = (0.05, 0.95); p.mouthCurve = 0.75; p.mouthWidth = 5; p.mouthX = 3; p.ears = (-6, 22)
        case .worried:
            p.look = (-0.25, 0.15); p.pupil = 0.88; p.blush = 0.15; p.glowStrength = 0.65; p.sweat = 1
            p.bobAmplitude = 0.8; p.handsIn = 0.55
            p.browAngle = 1; p.brows = (0.35, 0.35); p.mouthCurve = -0.4; p.mouthWidth = 5.5; p.ears = (38, 38); p.eyeSize = 1.08
            p.glow = MascotPalette.glowAmber
        case .annoyed:
            p.pupil = 0.8; p.blush = 0; p.flush = 1; p.glowStrength = 1.15; p.pulse = .cross; p.steam = 1
            p.tilt = -2; p.tap = 1
            p.lid = 0.35; p.browAngle = -1; p.brows = (0, 0); p.mouthCurve = -0.6; p.mouthWidth = 5; p.ears = (50, 50)
            p.glow = MascotPalette.glowCrimson
        case .happy:
            p.blush = 0.85; p.glowStrength = 1.3; p.bounce = 0.6; p.sparkle = 0.7; p.look = (0, -0.1); p.wave = 1
            p.eyesSmiling = true; p.mouthCurve = 1; p.mouthOpen = 0.55; p.mouthWidth = 9; p.brows = (0.55, 0.55); p.ears = (-14, -14)
            p.glow = MascotPalette.glowBright
        case .cheer:
            p.blush = 0.7; p.glowStrength = 1.35; p.bounce = 1; p.sparkle = 1; p.fist = 1
            p.eyesSqueezed = true; p.mouthOpen = 0.85; p.mouthCurve = 1; p.mouthWidth = 8; p.ears = (-18, -18)
            p.glow = MascotPalette.glowBright
        case .proud:
            // Proud reads from the whole body, not the face: chin up, chest out, eyes shut
            // in satisfaction, a thumb up.
            p.tilt = -8; p.squash = -0.06; p.blush = 0.55; p.glowStrength = 1.25; p.sparkle = 0.65
            p.look = (0, -0.4); p.thumb = 1
            p.eyesSmiling = true; p.mouthCurve = 0.95; p.mouthWidth = 7; p.mouthX = 2; p.brows = (0.8, 0.8)
            p.ears = (-12, -12); p.faceY = -3
            p.glow = MascotPalette.glowGold
        case .resting:
            p.look = (0, 0.3); p.blush = 0.45; p.glowStrength = 0.25; p.antennaDroop = 0.8; p.tilt = -7; p.zzz = 1
            p.bobAmplitude = 3; p.bobSpeed = 1.1; p.sink = 0.2
            p.lid = 0.78; p.mouthCurve = 0.15; p.mouthOpen = 0.14; p.mouthWidth = 2.8; p.ears = (52, 52)
            p.glow = MascotPalette.glowDim
        case .sad:
            p.look = (0, 0.5); p.blush = 0.2; p.glowStrength = 0.45; p.antennaDroop = 1; p.tear = 1; p.tilt = -4
            p.squash = 0.05; p.bobSpeed = 1; p.sink = 0.32; p.handsIn = 0.55
            p.browAngle = 1; p.brows = (0.2, 0.2); p.mouthCurve = -0.85; p.mouthWidth = 6; p.lid = 0.35; p.ears = (72, 72)
            p.glow = MascotPalette.glowBlue
        }
        return p
    }
}

private enum MascotPalette {
    static let body = Color(hex: 0xFFAD33)
    static let shade = Color(hex: 0xFA7400)
    static let belly = Color(hex: 0xFCE4C1)
    static let ear = Color(hex: 0xFF9A8A)
    static let ink = Color(hex: 0x3B1F11)
    static let hand = Color(hex: 0xFFFAF2)
    static let mouth = Color(hex: 0x4F2217)
    static let tongue = Color(hex: 0xFF7A7A)
    static let blush = Color(hex: 0xFF8F8F)

    static let glowWarm = Color(hex: 0xFFD25A)
    static let glowBright = Color(hex: 0xFFF27A)
    static let glowTeal = Color(hex: 0x5FE6D4)
    static let glowAmber = Color(hex: 0xFF9A3C)
    static let glowCrimson = Color(hex: 0xE0203A)
    static let glowGold = Color(hex: 0xFFC23A)
    static let glowDim = Color(hex: 0x9C8F74)
    static let glowBlue = Color(hex: 0x7AA8FF)
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Drawing

/// One frame of the mascot. A value type built per frame from the pose and the clock.
private struct MascotRig {
    let pose: MascotPose
    let t: Double
    /// False under Reduce Motion: no shaking, hopping or drifting effects.
    let moving: Bool
    let cardEdge: Double

    private typealias P = MascotPalette
    private static let seed = 1.7
    /// The study's scene units per design unit.
    private static let scene = 1.9
    private static let body = Self.superellipse(rx: 48, ry: 36, power: 3.1, centerY: 8)
    private static let bodyShadeMask = Self.superellipse(rx: 48, ry: 36, power: 3.1, centerX: -7, centerY: 1)

    private func line(_ width: Double) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    // MARK: Body layer

    func drawBody(in context: inout GraphicsContext) {
        let p = pose
        let bob = sin(t * p.bobSpeed) * p.bobAmplitude * 0.5 - abs(sin(t * 4.4)) * 3 * p.bounce
        let breath = sin(t * 2) * 0.012

        // Effects float with the body but don't tilt with it.
        var base = context
        base.translateBy(x: 0, y: bob + p.sink * 62 / Self.scene)

        var body = base
        // Tilt and breathing pivot on the feet, so the head travels and the base stays put.
        body.translateBy(x: 0, y: 44)
        body.rotate(by: .degrees(p.tilt) + .radians(sin(t * 0.55) * 0.02))
        body.scaleBy(x: 1 + p.squash + breath, y: 1 - p.squash - breath)
        body.translateBy(x: 0, y: -44)

        drawEars(in: &body)
        drawAntenna(in: &body)
        drawTorso(in: &body)

        var faceContext = body
        faceContext.translateBy(x: p.look.x * 2.5, y: 5 + p.look.y * 2 + p.faceY)
        drawFace(in: &faceContext)

        drawEffects(in: &base)
    }

    private func drawEars(in context: inout GraphicsContext) {
        for side in [-1.0, 1.0] {
            let angle = side < 0 ? pose.ears.left : pose.ears.right
            var ear = context
            ear.translateBy(x: side * 31, y: -18)
            ear.rotate(by: .degrees(side * (18 + angle * 0.7)))
            let outer = Self.ellipse(0, -7, 9, 11.5)
            ear.fill(outer, with: .color(P.body))
            ear.stroke(outer, with: .color(P.ink), lineWidth: 2.7)
            ear.fill(Self.ellipse(0, -7, 4.5, 6.5), with: .color(P.ear))
        }
    }

    /// Sways on its own clock, twitches now and then, and leans with the gaze. A drooping
    /// antenna bends forward. The bulb glows in the mood's colour; warnings make it pulse.
    private func drawAntenna(in context: inout GraphicsContext) {
        let droop = max(0, min(1, pose.antennaDroop))
        var antenna = context
        antenna.translateBy(x: 0, y: -25)
        antenna.rotate(by: .radians(sin(t * 1.8) * 0.12 * (1 - droop * 0.6) + droop + twitch(at: t) * 0.25 + pose.look.x * 0.08))
        let tip = CGPoint(x: droop * 9, y: -31 + droop * 9)

        var stalk = Path()
        stalk.move(to: .zero)
        stalk.addQuadCurve(to: tip, control: CGPoint(x: droop * 2, y: -16))
        antenna.stroke(stalk, with: .color(P.ink), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))

        let pulse: Double = switch pose.pulse {
        case .gentle: 0.9 + 0.1 * sin(t * 2.4)
        case .cross: 0.75 + 0.25 * sin(t * 7)
        }
        let strength = max(0, min(1.4, pose.glowStrength * pulse))
        antenna.fill(Self.ellipse(tip.x, tip.y, 26, 26), with: .radialGradient(
            Gradient(colors: [pose.glow.opacity(0.55 * strength), pose.glow.opacity(0)]),
            center: tip, startRadius: 2, endRadius: 26))
        let bulb = Self.ellipse(tip.x, tip.y, 7.5, 7.5)
        antenna.fill(bulb, with: .color(pose.glow.mix(with: .white, by: 0.15 * min(1, strength))))
        antenna.stroke(bulb, with: .color(P.ink), lineWidth: 2.7)
        antenna.fill(Self.ellipse(tip.x - 2.5, tip.y - 3, 2.2, 1.4, rotation: -0.6), with: .color(.white.opacity(0.85)))
    }

    /// Flat fill, one cel-shaded crescent, a soft highlight, then the outline over all of it.
    private func drawTorso(in context: inout GraphicsContext) {
        context.fill(Self.body, with: .color(P.body))
        context.fill(Self.ellipse(0, 25, 28, 13), with: .color(P.belly))

        var shaded = context
        shaded.clip(to: Self.body)
        var crescent = Path(CGRect(x: -200, y: -200, width: 400, height: 400))
        crescent.addPath(Self.bodyShadeMask)
        shaded.fill(crescent, with: .color(P.shade), style: FillStyle(eoFill: true))
        if pose.flush > 0.02 {
            shaded.fill(Path(CGRect(x: -60, y: -40, width: 120, height: 50)), with: .linearGradient(
                Gradient(colors: [Color(red: 1, green: 0.24, blue: 0.24).opacity(0.45 * pose.flush), .clear]),
                startPoint: CGPoint(x: 0, y: -30), endPoint: CGPoint(x: 0, y: 10)))
        }
        shaded.fill(Self.ellipse(-27, -15, 9, 5, rotation: -0.45), with: .color(.white.opacity(0.55)))
        shaded.fill(Self.ellipse(-33, -10, 2, 2), with: .color(.white.opacity(0.9)))

        context.stroke(Self.body, with: .color(P.ink), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
    }

    private func drawFace(in context: inout GraphicsContext) {
        let p = pose
        let blink = blink(at: t)
        let glance = saccade(at: t)
        let lookX = max(-1, min(1, p.look.x + glance.width))
        let lookY = max(-1, min(1, p.look.y + glance.height))

        if p.blush > 0.03 {
            for side in [-1.0, 1.0] {
                context.fill(Self.ellipse(side * 28, 9, 7, 4), with: .color(P.blush.opacity(min(1, p.blush) * 0.6)))
            }
        }

        for side in [-1.0, 1.0] {
            let center = CGPoint(x: side * 17, y: -4)
            let radiusX = 8.8 * p.eyeSize, fullRadiusY = 10.6 * p.eyeSize
            let openness = 1 - blink

            if p.eyesSqueezed {
                var squeeze = Path()
                squeeze.move(to: CGPoint(x: center.x + side * 6, y: center.y - 6))
                squeeze.addLine(to: CGPoint(x: center.x - side * 5, y: center.y))
                squeeze.addLine(to: CGPoint(x: center.x + side * 6, y: center.y + 6))
                context.stroke(squeeze, with: .color(P.ink), style: line(3.4))
            } else if p.eyesSmiling {
                context.stroke(Self.quad(CGPoint(x: center.x - 7.5, y: center.y + 3), CGPoint(x: center.x, y: center.y - 9),
                                         CGPoint(x: center.x + 7.5, y: center.y + 3)), with: .color(P.ink), style: line(3.4))
            } else if openness < 0.14 {
                context.stroke(Self.quad(CGPoint(x: center.x - 8, y: center.y + 1), CGPoint(x: center.x, y: center.y + 4),
                                         CGPoint(x: center.x + 8, y: center.y + 1)), with: .color(P.ink), style: line(3))
            } else {
                let radiusY = fullRadiusY * openness
                let white = Self.ellipse(center.x, center.y, radiusX, radiusY)
                context.fill(white, with: .color(.white))
                var inside = context
                inside.clip(to: white)
                let pupil = 4.8 * p.pupil
                let pupilCenter = CGPoint(x: center.x + lookX * (radiusX - pupil - 0.5), y: center.y + lookY * (radiusY - pupil - 0.5))
                inside.fill(Self.ellipse(pupilCenter.x, pupilCenter.y, pupil, pupil * min(1, radiusY / pupil)), with: .color(P.ink))
                inside.fill(Self.ellipse(pupilCenter.x - pupil * 0.35, pupilCenter.y - pupil * 0.4, pupil * 0.34, pupil * 0.34), with: .color(.white))
                inside.fill(Self.ellipse(pupilCenter.x + pupil * 0.35, pupilCenter.y + pupil * 0.35, pupil * 0.15, pupil * 0.15), with: .color(.white))
                if p.lid > 0.02 {
                    // The lid follows the brow: worried lids tilt up inward, cross ones down.
                    let top = center.y - radiusY, height = 2 * radiusY * min(1, p.lid), slant = side * p.browAngle * 1.5
                    var lid = Path()
                    lid.move(to: CGPoint(x: center.x - radiusX - 2, y: top - 2))
                    lid.addLine(to: CGPoint(x: center.x + radiusX + 2, y: top - 2))
                    lid.addLine(to: CGPoint(x: center.x + radiusX + 2, y: top + height + slant))
                    lid.addLine(to: CGPoint(x: center.x - radiusX - 2, y: top + height - slant))
                    lid.closeSubpath()
                    inside.fill(lid, with: .color(P.body))
                    var edge = Path()
                    edge.move(to: CGPoint(x: center.x - radiusX, y: top + height - slant))
                    edge.addLine(to: CGPoint(x: center.x + radiusX, y: top + height + slant))
                    inside.stroke(edge, with: .color(P.ink), style: line(2.5))
                }
                context.stroke(white, with: .color(P.ink), lineWidth: 2.7)
            }

            // The inner end lifts with worry and drops with anger.
            let lift = side < 0 ? p.brows.left : p.brows.right
            let browY = center.y - fullRadiusY - 6 - lift * 5
            let inner = CGPoint(x: center.x - side * 6, y: browY - p.browAngle * 4.5)
            let outer = CGPoint(x: center.x + side * 7, y: browY + p.browAngle * 1.5)
            context.stroke(Self.quad(inner, CGPoint(x: center.x, y: min(inner.y, outer.y) - 2.2), outer),
                           with: .color(P.ink), style: line(3.4))
        }

        var mouth = context
        mouth.translateBy(x: p.mouthX, y: 14)
        let width = p.mouthWidth, curve = p.mouthCurve * 8, open = p.mouthOpen * 14
        if open < 1.2 {
            mouth.stroke(Self.quad(CGPoint(x: -width, y: 0), CGPoint(x: 0, y: curve), CGPoint(x: width, y: 0)),
                         with: .color(P.ink), style: line(3))
        } else {
            var shape = Path()
            shape.move(to: CGPoint(x: -width, y: 0))
            shape.addQuadCurve(to: CGPoint(x: width, y: 0), control: CGPoint(x: 0, y: curve * 0.55))
            shape.addQuadCurve(to: CGPoint(x: -width, y: 0), control: CGPoint(x: 0, y: curve + open))
            shape.closeSubpath()
            mouth.fill(shape, with: .color(P.mouth))
            var tongue = mouth
            tongue.clip(to: shape)
            tongue.fill(Self.ellipse(0, (curve + open) * 0.55 + open * 0.2, width * 0.62, open * 0.32 + 1), with: .color(P.tongue))
            mouth.stroke(shape, with: .color(P.ink), style: line(2.7))
        }
    }

    // MARK: Effects

    /// The floating marks: zzz, ?, sweat, a tear, steam and sparkles. Positions are the
    /// study's scene units divided by `scene`.
    private func drawEffects(in context: inout GraphicsContext) {
        let p = pose
        let k = Self.scene

        if p.zzz > 0.05 {
            for index in 0..<3 {
                let phase = (t * 0.35 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                glyph("z", x: (78 + phase * 40) / k, y: (-100 - phase * 60) / k, size: (16 + phase * 18) / k,
                      fill: Color(hex: 0xC6BDFF), ink: Color(hex: 0x3A2F7A), rotation: 0.1,
                      opacity: p.zzz * sin(phase * .pi), in: &context)
            }
        }
        if p.question > 0.05 {
            glyph("?", x: -96 / k, y: (-104 + sin(t * 2.2) * 4) / k, size: 44 / k,
                  fill: P.glowTeal, ink: Color(hex: 0x1C3A40), rotation: -0.2, opacity: min(1, p.question), in: &context)
        }
        if p.sweat > 0.05 {
            drop(x: 96 / k, y: (-74 + (t * 0.5).truncatingRemainder(dividingBy: 1) * 22) / k, scale: 1 / k,
                 color: Color(hex: 0x7CC8FF), opacity: min(1, p.sweat), in: &context)
        }
        if p.tear > 0.05 {
            let phase = (t * 0.45).truncatingRemainder(dividingBy: 1)
            drop(x: -56 / k, y: (4 + phase * 34) / k, scale: 0.8 / k,
                 color: Color(hex: 0x8AB8FF), opacity: min(1, p.tear) * (1 - phase * 0.6), in: &context)
        }
        if p.steam > 0.05 {
            for side in [-1.0, 1.0] {
                for index in 0..<2 {
                    let phase = (t * 0.8 + Double(index) * 0.5 + (side > 0 ? 0.25 : 0)).truncatingRemainder(dividingBy: 1)
                    let radius = (7 + phase * 10) / k
                    var puff = context
                    puff.opacity = min(1, p.steam) * (1 - phase) * 0.85
                    puff.fill(Self.ellipse(side * (74 + phase * 18) / k, (-80 - phase * 40) / k, radius, radius), with: .color(.white))
                }
            }
        }
        if p.sparkle > 0.05 {
            for index in 0..<5 {
                let i = Double(index)
                let angle = i / 5 * 2 * .pi + t * 0.5
                let radius = (140 + sin(t * 2 + i) * 6) / k
                let size = (7 + 4 * sin(t * 5 + i * 1.7)) * min(1, p.sparkle) / k
                guard size > 0.5 else { continue }
                let center = CGPoint(x: cos(angle) * radius, y: -24 / k + sin(angle) * radius * 0.7)
                var star = Path()
                for point in 0..<8 {
                    let a = Double(point) / 8 * 2 * .pi - .pi / 2
                    let r = point.isMultiple(of: 2) ? size : size * 0.32
                    let corner = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
                    point == 0 ? star.move(to: corner) : star.addLine(to: corner)
                }
                star.closeSubpath()
                context.fill(star, with: .color(Color(hex: 0xFFD84D)))
                context.stroke(star, with: .color(Color(hex: 0x7A5200)), style: line(2 / k))
            }
        }
    }

    /// A rounded glyph with an ink outline, drawn as the ink shape offset all round with the
    /// fill on top: Canvas has no stroked text.
    private func glyph(_ character: String, x: Double, y: Double, size: Double, fill: Color, ink: Color,
                       rotation: Double, opacity: Double, in context: inout GraphicsContext) {
        guard opacity > 0.01 else { return }
        var mark = context
        mark.opacity = opacity
        mark.translateBy(x: x, y: y)
        mark.rotate(by: .radians(rotation))
        let font = Font.system(size: size, weight: .heavy, design: .rounded)
        let outline = mark.resolve(Text(character).font(font).foregroundStyle(ink))
        let face = mark.resolve(Text(character).font(font).foregroundStyle(fill))
        let reach = size * 0.06
        for step in 0..<8 {
            let a = Double(step) / 8 * 2 * .pi
            mark.draw(outline, at: CGPoint(x: cos(a) * reach, y: sin(a) * reach))
        }
        mark.draw(face, at: .zero)
    }

    /// A drop with a white highlight: sweat or a tear.
    private func drop(x: Double, y: Double, scale s: Double, color: Color, opacity: Double, in context: inout GraphicsContext) {
        guard opacity > 0.01 else { return }
        var shape = Path()
        shape.move(to: CGPoint(x: x, y: y - 16 * s))
        shape.addCurve(to: CGPoint(x: x, y: y + 6 * s), control1: CGPoint(x: x + 4 * s, y: y - 8 * s), control2: CGPoint(x: x + 10 * s, y: y))
        shape.addCurve(to: CGPoint(x: x, y: y - 16 * s), control1: CGPoint(x: x - 10 * s, y: y), control2: CGPoint(x: x - 4 * s, y: y - 8 * s))
        var drop = context
        drop.opacity = opacity
        drop.fill(shape, with: .radialGradient(Gradient(colors: [.white, color]),
                                              center: CGPoint(x: x - 2 * s, y: y - 3 * s), startRadius: s, endRadius: 12 * s))
    }

    // MARK: Hands layer

    /// The hands sit in front of the card. At rest they curl over its top edge; each mood
    /// pulls them toward a pose: waving, fists up, a thumb, a hand to the chin, or tapping
    /// on the card. Worked in the study's scene units, where the card's
    /// edge is at 71, then converted.
    func drawHands(in context: inout GraphicsContext) {
        let p = pose
        let k = Self.scene
        for side in [-1.0, 1.0] {
            let tapping = p.tap * max(0, sin(t * 12 + (side > 0 ? 0 : 1.8))) * 6
            var x = side * Self.lerp(66, 38, p.handsIn), y = 71 - tapping
            var rotation = 0.0, open = 0.6, thumb = 0.0, grip = 1.0
            func pull(_ weight: Double, _ tx: Double, _ ty: Double, _ tr: Double, _ topen: Double, _ tthumb: Double) {
                let w = max(0, min(1, weight))
                guard w > 0.001 else { return }
                x = Self.lerp(x, tx, w); y = Self.lerp(y, ty, w); rotation = Self.lerp(rotation, tr, w)
                open = Self.lerp(open, topen, w); thumb = Self.lerp(thumb, tthumb, w); grip = Self.lerp(grip, 0, w)
            }
            if side > 0 { pull(p.wave, 120, -6, 0.25 + sin(t * 9) * 0.4, 1, 0) }
            pull(p.fist, side * 100, -46 + sin(t * 10 + side) * 5, side * 0.15, 0, 0)
            if side > 0 { pull(p.thumb, 108, 10, 0, 0, 1) }
            if side > 0 { pull(p.chin, 34, 50, -0.5, 0.2, 0) }
            y += sin(t * 2 + side) * 1.5

            var hand = context
            hand.translateBy(x: x / k, y: cardEdge + 0.5 + (y - 71) / k)
            hand.rotate(by: .radians(rotation))
            hand.scaleBy(x: side, y: 1)
            if grip > 0.5 {
                drawGrip(in: &hand)
            } else {
                drawMitten(open: open, point: 0, thumb: thumb, in: &hand)
            }
        }
    }

    private func drawGrip(in context: inout GraphicsContext) {
        let palm = Self.ellipse(0, 0, 12.1, 6.8)
        context.fill(palm, with: .color(P.hand))
        context.stroke(palm, with: .color(P.ink), lineWidth: 2.4)
        for x in [-5.8, 0, 5.8] {
            let finger = Self.ellipse(x, 6.3, 3.2, 3.9)
            context.fill(finger, with: .color(P.hand))
            context.stroke(finger, with: .color(P.ink), lineWidth: 2.2)
        }
    }

    /// A mitten: four fingers and a thumb under a round palm. `open` curls it into a fist,
    /// `point` extends the first finger, `thumb` makes a thumbs-up.
    private func drawMitten(open: Double, point: Double, thumb: Double, in context: inout GraphicsContext) {
        var parts: [Path] = []
        for (index, angle) in [-0.5, -0.17, 0.17, 0.5].enumerated() {
            var length = Self.lerp(2.5, 10, open)
            length = index == 0 ? Self.lerp(length, 15, point) : Self.lerp(length, 1.5, point)
            length *= 1 - thumb * 0.75
            let reach = 7.5 + length / 2
            parts.append(Self.ellipse(sin(angle) * reach, 2 - cos(angle) * reach, 3.8, length / 2 + 3.8, rotation: angle))
        }
        let thumbAngle = Self.lerp(-1.3, -0.05, thumb)
        let thumbLength = Self.lerp(Self.lerp(3, 8, open), 12, thumb)
        let thumbReach = 8 + thumbLength / 2
        parts.append(Self.ellipse(sin(thumbAngle) * thumbReach, 3 - cos(thumbAngle) * thumbReach, 4, thumbLength / 2 + 4, rotation: thumbAngle))
        parts.append(Self.ellipse(0, 3, 10.5, 10))
        for part in parts {
            context.fill(part, with: .color(P.hand))
            context.stroke(part, with: .color(P.ink), lineWidth: 2.7)
        }
    }

    // MARK: Idle motion

    /// Blinks on a jittered schedule, roughly every third a quick double. A fixed interval
    /// reads as a metronome.
    private func blink(at t: Double) -> Double {
        let base = 3.6, duration = 0.14
        let index = (t / base).rounded(.down)
        let noise = abs((sin(index * 12.9898 + Self.seed) * 43758.5453).truncatingRemainder(dividingBy: 1))
        let local = t - index * base - noise * 2.4
        var amount = 0.0
        if local >= 0, local <= duration { amount = sin(local / duration * .pi) }
        if noise > 0.66 {
            let second = local - duration * 1.9
            if second >= 0, second <= duration { amount = max(amount, sin(second / duration * .pi)) }
        }
        return amount
    }

    /// Quick glances that snap and hold. Eyes that only glide look painted on.
    private func saccade(at t: Double) -> CGSize {
        let base = 2.4
        let index = (t / base).rounded(.down)
        let local = t - index * base
        let nx = (sin(index * 91.17 + Self.seed) * 7919.3).truncatingRemainder(dividingBy: 1)
        let ny = (sin(index * 47.31) * 3571.7).truncatingRemainder(dividingBy: 1)
        let travel = min(1, local / 0.07)
        let settle = local > base * 0.6 ? max(0, 1 - (local - base * 0.6) / 0.5) : 1
        return CGSize(width: nx * 0.22 * travel * settle, height: ny * 0.14 * travel * settle)
    }

    /// The antenna's occasional flick, on its own jittered schedule.
    private func twitch(at t: Double) -> Double {
        let base = 4.7
        let index = (t / base).rounded(.down)
        let noise = abs((sin(index * 3.77 + Self.seed) * 9187.1).truncatingRemainder(dividingBy: 1))
        let local = t - index * base - noise * 3
        return local > 0 && local < 0.25 && noise > 0.35 ? sin(local / 0.25 * .pi) : 0
    }

    // MARK: Geometry

    private static func lerp(_ a: Double, _ b: Double, _ amount: Double) -> Double {
        a + (b - a) * amount
    }

    private static func ellipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, rotation: Double = 0) -> Path {
        Path(ellipseIn: CGRect(x: -max(0.01, rx), y: -max(0.01, ry), width: max(0.01, rx) * 2, height: max(0.01, ry) * 2))
            .applying(CGAffineTransform(rotationAngle: rotation).concatenating(CGAffineTransform(translationX: x, y: y)))
    }

    private static func quad(_ start: CGPoint, _ control: CGPoint, _ end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }

    /// A squared-off ellipse: the body's soft rectangle.
    private static func superellipse(rx: Double, ry: Double, power: Double, centerX: Double = 0, centerY: Double = 0) -> Path {
        var path = Path()
        let steps = 96
        for step in 0..<steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            let c = cos(angle), s = sin(angle)
            let point = CGPoint(x: centerX + rx * (c < 0 ? -1 : 1) * pow(abs(c), 2 / power),
                                y: centerY + ry * (s < 0 ? -1 : 1) * pow(abs(s), 2 / power))
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}
