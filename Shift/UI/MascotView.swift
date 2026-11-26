import SwiftUI

/// What the mascot is feeling. One per moment the nudge card can show.
enum MascotMood: Equatable, Sendable {
    /// A plain status line: a break starting, nothing wrong.
    case calm
    /// The soft drift hint: a feed keyword in a window title.
    case curious
    /// Turning back on your own. The step the habit is built on.
    case happy
    /// Something didn't work: the tab couldn't be closed, the break couldn't start.
    case sorry
}

/// Shift's mascot: a marigold creature with round ears, white mitten hands and an antenna
/// whose bulb carries the mood. It peeks over the top of the nudge card and holds its edge.
///
/// Chosen from HTML studies (`Studies/mascot-compare.html`, "Classic") over a glossy 3D
/// direction and the earlier Flop. What makes it work:
///
/// - **A flat cartoon with an ink outline.** One cel-shaded crescent and one highlight give
///   it volume without gradients, so it stays crisp at any size and reads at a glance.
/// - **The antenna light is the mood you see from the corner of your eye**: warm at rest,
///   teal when curious, bright when you turn back, amber when something went wrong.
/// - **It holds the card.** The hands curl over the card's top edge, so the card and the
///   creature read as one object rather than a sticker beside a banner.
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

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animates)) { timeline in
            let t = animates ? timeline.date.timeIntervalSince(start) : 0.7
            Canvas(rendersAsynchronously: false) { context, _ in
                context.translateBy(x: -Self.box.minX * Self.scale, y: -Self.box.minY * Self.scale)
                context.scaleBy(x: Self.scale, y: Self.scale)
                let rig = MascotRig(face: mood.face, t: t, cardEdge: Self.cardEdge)
                switch layer {
                case .body: rig.drawBody(in: &context)
                case .hands: rig.drawHands(in: &context)
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }
}

// MARK: - Moods

/// Every expression is a handful of numbers. The rig draws whatever they say.
private struct MascotFace {
    enum Hand { case grip(inset: Double), wave, shrug }
    enum Mark { case question, sweat }

    /// Degrees outward from upright. Positive droops them.
    var ears: (left: Double, right: Double) = (0, 0)
    /// How far each brow lifts, 0 to 1.
    var brows: (left: Double, right: Double) = (0.15, 0.15)
    /// Lifts the inner ends of both brows: worry.
    var browWorry: Double = 0
    /// Closed, upturned eyes.
    var eyesSmiling = false
    var look: (x: Double, y: Double) = (0, 0)
    /// -1 frowns, 1 smiles.
    var mouthCurve: Double = 0.45
    /// 0 closed, 1 wide open.
    var mouthOpen: Double = 0
    var mouthWidth: Double = 6
    var blush: Double = 0.35
    /// Degrees, about the feet.
    var tilt: Double = 0
    /// Little hops, 0 to 1.
    var bounce: Double = 0
    var glow: Color = MascotPalette.glowWarm
    var glowStrength: Double = 0.85
    var hands: (left: Hand, right: Hand) = (.grip(inset: 0), .grip(inset: 0))
    var mark: Mark?
}

private extension MascotMood {
    var face: MascotFace {
        var face = MascotFace()
        switch self {
        case .calm:
            break
        case .curious:
            face.ears = (-12, 28)
            face.brows = (0.05, 0.95)
            face.look = (0.55, -0.25)
            face.mouthCurve = 0.1
            face.mouthWidth = 4
            face.tilt = 8
            face.glow = MascotPalette.glowTeal
            face.hands = (.grip(inset: 0.2), .grip(inset: 0.2))
            face.mark = .question
        case .happy:
            face.ears = (-14, -14)
            face.brows = (0.55, 0.55)
            face.eyesSmiling = true
            face.look = (0, -0.1)
            face.mouthCurve = 1
            face.mouthOpen = 0.55
            face.mouthWidth = 9
            face.blush = 0.85
            face.bounce = 0.6
            face.glow = MascotPalette.glowBright
            face.glowStrength = 1.3
            face.hands = (.grip(inset: 0), .wave)
        case .sorry:
            face.ears = (32, 32)
            face.brows = (0.4, 0.4)
            face.browWorry = 0.9
            face.look = (0.3, 0)
            face.mouthCurve = -0.05
            face.tilt = 6
            face.glow = MascotPalette.glowAmber
            face.glowStrength = 0.6
            face.hands = (.shrug, .shrug)
            face.mark = .sweat
        }
        return face
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
    static let glowTeal = Color(hex: 0x5FE6D4)
    static let glowBright = Color(hex: 0xFFF27A)
    static let glowAmber = Color(hex: 0xFF9A3C)
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Drawing

/// One frame of the mascot. A value type built per frame from the face and the clock.
private struct MascotRig {
    let face: MascotFace
    let t: Double
    let cardEdge: Double

    private typealias P = MascotPalette
    private static let seed = 1.7
    private static let body = Self.superellipse(rx: 48, ry: 36, power: 3.1, centerY: 8)
    private static let bodyShadeMask = Self.superellipse(rx: 48, ry: 36, power: 3.1, centerX: -7, centerY: 1)

    // MARK: Body layer

    func drawBody(in context: inout GraphicsContext) {
        let bob = sin(t * 2) * 0.8 - abs(sin(t * 4.4)) * 3 * face.bounce
        let breath = sin(t * 2) * 0.012

        context.translateBy(x: 0, y: bob)
        // Tilt and breathing pivot on the feet, so the head travels and the base stays put.
        context.translateBy(x: 0, y: 44)
        context.rotate(by: .degrees(face.tilt) + .radians(sin(t * 0.55) * 0.02))
        context.scaleBy(x: 1 + breath, y: 1 - breath)
        context.translateBy(x: 0, y: -44)

        drawEars(in: &context)
        drawAntenna(in: &context)
        drawTorso(in: &context)

        var faceContext = context
        faceContext.translateBy(x: face.look.x * 2.5, y: 5 + face.look.y * 2)
        drawFace(in: &faceContext)

        drawMark(in: &context)
    }

    private func drawEars(in context: inout GraphicsContext) {
        for side in [-1.0, 1.0] {
            let angle = side < 0 ? face.ears.left : face.ears.right
            var ear = context
            ear.translateBy(x: side * 31, y: -18)
            ear.rotate(by: .degrees(side * (18 + angle * 0.7)))
            let outer = Self.ellipse(0, -7, 9, 11.5)
            ear.fill(outer, with: .color(P.body))
            ear.stroke(outer, with: .color(P.ink), lineWidth: 2.7)
            ear.fill(Self.ellipse(0, -7, 4.5, 6.5), with: .color(P.ear))
        }
    }

    /// Sways on its own clock and leans with the gaze. The bulb glows in the mood's colour.
    private func drawAntenna(in context: inout GraphicsContext) {
        var antenna = context
        antenna.translateBy(x: 0, y: -25)
        antenna.rotate(by: .radians(sin(t * 1.8) * 0.12 + face.look.x * 0.08))
        let tip = CGPoint(x: 0, y: -31)

        var stalk = Path()
        stalk.move(to: .zero)
        stalk.addQuadCurve(to: tip, control: CGPoint(x: 0, y: -16))
        antenna.stroke(stalk, with: .color(P.ink), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))

        let strength = min(1.4, face.glowStrength * (0.9 + 0.1 * sin(t * 2.4)))
        antenna.fill(Self.ellipse(tip.x, tip.y, 26, 26), with: .radialGradient(
            Gradient(colors: [face.glow.opacity(0.55 * strength), face.glow.opacity(0)]),
            center: tip, startRadius: 2, endRadius: 26))
        let bulb = Self.ellipse(tip.x, tip.y, 7.5, 7.5)
        antenna.fill(bulb, with: .color(face.glow))
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
        shaded.fill(Self.ellipse(-27, -15, 9, 5, rotation: -0.45), with: .color(.white.opacity(0.55)))
        shaded.fill(Self.ellipse(-33, -10, 2, 2), with: .color(.white.opacity(0.9)))

        context.stroke(Self.body, with: .color(P.ink), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
    }

    private func drawFace(in context: inout GraphicsContext) {
        let blink = blink(at: t)
        let glance = saccade(at: t)
        let lookX = max(-1, min(1, face.look.x + glance.width))
        let lookY = max(-1, min(1, face.look.y + glance.height))
        let line = { (width: Double) in StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round) }

        for side in [-1.0, 1.0] {
            context.fill(Self.ellipse(side * 28, 9, 7, 4), with: .color(P.blush.opacity(face.blush * 0.6)))
        }

        for side in [-1.0, 1.0] {
            let center = CGPoint(x: side * 17, y: -4)
            let radiusX = 8.8, fullRadiusY = 10.6
            let openness = 1 - blink

            if face.eyesSmiling {
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
                let pupil = 4.8
                let pupilCenter = CGPoint(x: center.x + lookX * (radiusX - pupil - 0.5), y: center.y + lookY * (radiusY - pupil - 0.5))
                inside.fill(Self.ellipse(pupilCenter.x, pupilCenter.y, pupil, pupil * min(1, radiusY / pupil)), with: .color(P.ink))
                inside.fill(Self.ellipse(pupilCenter.x - pupil * 0.35, pupilCenter.y - pupil * 0.4, pupil * 0.34, pupil * 0.34), with: .color(.white))
                inside.fill(Self.ellipse(pupilCenter.x + pupil * 0.35, pupilCenter.y + pupil * 0.35, pupil * 0.15, pupil * 0.15), with: .color(.white))
                context.stroke(white, with: .color(P.ink), lineWidth: 2.7)
            }

            // The inner end lifts with worry.
            let lift = side < 0 ? face.brows.left : face.brows.right
            let browY = center.y - fullRadiusY - 6 - lift * 5
            let inner = CGPoint(x: center.x - side * 6, y: browY - face.browWorry * 4.5)
            let outer = CGPoint(x: center.x + side * 7, y: browY + face.browWorry * 1.5)
            context.stroke(Self.quad(inner, CGPoint(x: center.x, y: min(inner.y, outer.y) - 2.2), outer),
                           with: .color(P.ink), style: line(3.4))
        }

        var mouth = context
        mouth.translateBy(x: 0, y: 14)
        let width = face.mouthWidth, curve = face.mouthCurve * 8, open = face.mouthOpen * 14
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

    private func drawMark(in context: inout GraphicsContext) {
        switch face.mark {
        case .question:
            var mark = context
            mark.translateBy(x: -52, y: -56 + sin(t * 2.2) * 2)
            mark.rotate(by: .degrees(-12))
            mark.draw(Text("?").font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(P.glowTeal), at: .zero)
        case .sweat:
            let y = -40 + (t * 0.5).truncatingRemainder(dividingBy: 1) * 12
            var drop = Path()
            drop.move(to: CGPoint(x: 52, y: y - 8))
            drop.addCurve(to: CGPoint(x: 52, y: y + 3), control1: CGPoint(x: 54, y: y - 4), control2: CGPoint(x: 57, y: y))
            drop.addCurve(to: CGPoint(x: 52, y: y - 8), control1: CGPoint(x: 47, y: y), control2: CGPoint(x: 50, y: y - 4))
            context.fill(drop, with: .color(Color(hex: 0x7CC8FF)))
        case nil:
            break
        }
    }

    // MARK: Hands layer

    /// The hands sit in front of the card. Gripping, they curl over its top edge.
    func drawHands(in context: inout GraphicsContext) {
        for side in [-1.0, 1.0] {
            let hand = side < 0 ? face.hands.left : face.hands.right
            var palm = context
            switch hand {
            case .grip(let inset):
                palm.translateBy(x: side * (34.7 - inset * 14.7), y: cardEdge + 0.5 + sin(t * 2 + side) * 0.8)
                palm.scaleBy(x: side, y: 1)
                drawGrip(in: &palm)
            case .wave:
                palm.translateBy(x: side * 63, y: -3 + sin(t * 2 + side) * 0.8)
                palm.rotate(by: .radians(side * (0.25 + sin(t * 6) * 0.35)))
                palm.scaleBy(x: side, y: 1)
                drawMitten(in: &palm)
            case .shrug:
                palm.translateBy(x: side * 74, y: 17 + sin(t * 2 + side) * 0.8)
                palm.rotate(by: .radians(side * 1.35))
                palm.scaleBy(x: side, y: 1)
                drawMitten(in: &palm)
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

    /// An open mitten: four fingers and a thumb under a round palm.
    private func drawMitten(in context: inout GraphicsContext) {
        var parts: [Path] = []
        for angle in [-0.5, -0.17, 0.17, 0.5] {
            let length = 10.0, reach = 7.5 + length / 2
            parts.append(Self.ellipse(sin(angle) * reach, 2 - cos(angle) * reach, 3.8, length / 2 + 3.8, rotation: angle))
        }
        let thumbAngle = -1.3, thumbLength = 8.0, thumbReach = 8 + thumbLength / 2
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

    // MARK: Geometry

    private static func ellipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, rotation: Double = 0) -> Path {
        Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: max(0.01, ry) * 2))
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
