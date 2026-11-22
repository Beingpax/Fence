import SwiftUI

/// Flop — the nudge character, drawn and animated entirely in SwiftUI.
///
/// A being rather than an object, and an invented one rather than a real animal. Several
/// rounds proved both halves of that: rendered 3D art of a boy, then a drawn boy, then a
/// cat, then a run of faceless objects — a plant, a gauge, a candle. The boy fell into the
/// uncanny valley; the objects stopped being someone you could feel anything about.
///
/// Two things make this one work where earlier blobs didn't:
///
/// 1. **The ears.** They carry the escalation in pure silhouette — perked and fluttering,
///    one cocked back, then both pinned flat. You can read the rung from the corner of your
///    eye without resolving a single facial feature. If you change one thing about the
///    expressions, change `earAngle`.
/// 2. **The outline.** A dark stroke around every shape is the whole difference between a
///    designed mascot and a gradient blob with eyes on it. Don't remove it.
///
/// Drawn rather than shipped as artwork: crisp at any size, kilobytes instead of megabytes,
/// and it can blink. A face that never blinks reads as a sticker.
///
/// Everything is drawn in a 100 x 120 design box and scaled, so the geometry below reads as
/// fixed coordinates. One `Canvas` pass, one clock.
struct NudgeCharacterView: View {
    let mood: NudgeMood
    /// False under Reduce Motion: the creature still draws, it just holds still.
    let animates: Bool
    var height: CGFloat = 168

    @State private var start = Date()

    private static let design = CGSize(width: 100, height: 120)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animates)) { timeline in
            let t = animates ? timeline.date.timeIntervalSince(start) : 0.7

            Canvas(rendersAsynchronously: false) { context, size in
                context.scaleBy(x: size.height / Self.design.height,
                                y: size.height / Self.design.height)
                draw(in: &context, time: t)
            }
        }
        .frame(width: height * (Self.design.width / Self.design.height), height: height)
        .accessibilityHidden(true)
    }

    // MARK: Idle motion

    /// Blinks on a jittered schedule, and roughly every third blink is a quick double.
    /// A fixed interval reads as a metronome; the double is what tips it from "animated"
    /// into "alive".
    private func blink(at t: Double) -> CGFloat {
        let base = 3.4, duration = 0.13
        let index = (t / base).rounded(.down)
        let noise = abs((sin(index * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1))
        let local = t - index * base - noise * (base - duration * 5)

        var amount: CGFloat = 0
        if local >= 0, local <= duration {
            amount = sin(local / duration * .pi)
        }
        if noise > 0.66 {
            let second = local - duration * 1.9
            if second >= 0, second <= duration {
                amount = max(amount, sin(second / duration * .pi))
            }
        }
        return amount
    }

    private func draw(in context: inout GraphicsContext, time t: Double) {
        let spec = mood.face
        let bob = sin(t * spec.tempo)
        let sway = sin(t * 0.55)
        let shiver = spec.shiver > 0 ? sin(t * 18) * spec.shiver : 0

        drawShadow(in: &context, bob: bob)

        context.translateBy(x: 50, y: 104)
        context.rotate(by: .degrees(spec.lean + sway * spec.swayAmount))
        context.translateBy(x: -50 + shiver, y: -104 + bob * spec.bobAmount)

        drawEars(in: &context, spec: spec, t: t)
        drawBody(in: &context, spec: spec)
        drawFace(in: &context, spec: spec, lid: blink(at: t), t: t)
    }

    // MARK: Parts

    private func drawShadow(in context: inout GraphicsContext, bob: Double) {
        let spread = 1 + bob * 0.07
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 4))
            let w = 48 * spread
            layer.fill(Path(ellipseIn: CGRect(x: 50 - w / 2, y: 103, width: w, height: 9)),
                       with: .color(.black.opacity(0.24 / spread)))
        }
    }

    /// Long floppy ears, rotated about the point where they meet the head.
    ///
    /// Drawn before the body so they tuck behind it, which is what stops them looking
    /// stuck on. One path serves both ears, mirrored.
    private func drawEars(in context: inout GraphicsContext, spec: FaceSpec, t: Double) {
        let flutter = sin(t * spec.earTempo) * spec.earFlutter

        for side in [-1.0, 1.0] {
            let pivot = CGPoint(x: 50 + side * 16, y: 48)
            // Only the left ear takes the asymmetry, so the sceptical pose isn't a mirror.
            let asymmetry = side < 0 ? spec.earAsymmetry : 0
            let angle = side * (spec.earAngle + asymmetry) + flutter * side

            context.drawLayer { layer in
                layer.translateBy(x: pivot.x, y: pivot.y)
                layer.rotate(by: .degrees(angle))
                layer.scaleBy(x: side, y: 1)
                layer.translateBy(x: -pivot.x, y: -pivot.y)

                var ear = Path()
                ear.move(to: CGPoint(x: pivot.x, y: pivot.y))
                ear.addCurve(to: CGPoint(x: pivot.x - 2, y: pivot.y - 34),
                             control1: CGPoint(x: pivot.x - 9, y: pivot.y - 13),
                             control2: CGPoint(x: pivot.x - 11, y: pivot.y - 30))
                ear.addCurve(to: CGPoint(x: pivot.x + 7, y: pivot.y),
                             control1: CGPoint(x: pivot.x + 6, y: pivot.y - 36),
                             control2: CGPoint(x: pivot.x + 9, y: pivot.y - 17))
                ear.closeSubpath()

                layer.fill(ear, with: .color(spec.earFill))
                layer.stroke(ear, with: .color(spec.ink), lineWidth: 2.4)
            }
        }
    }

    private func drawBody(in context: inout GraphicsContext, spec: FaceSpec) {
        let body = Path(ellipseIn: CGRect(x: 50 - spec.width, y: 41,
                                          width: spec.width * 2, height: 66))
        context.fill(body, with: .radialGradient(
            Gradient(colors: [spec.lit, spec.body, spec.shade]),
            center: CGPoint(x: 36, y: 54), startRadius: 3, endRadius: 62))
        context.stroke(body, with: .color(spec.ink), lineWidth: 2.5)

        // A glazed highlight, clipped inside so it never crosses the outline.
        context.drawLayer { layer in
            layer.clip(to: body)
            layer.addFilter(.blur(radius: 3))
            layer.fill(Path(ellipseIn: CGRect(x: 27, y: 48, width: 22, height: 12)),
                       with: .color(.white.opacity(0.45)))
        }

        guard spec.cheek > 0.01 else { return }
        context.drawLayer { layer in
            layer.clip(to: body)
            layer.addFilter(.blur(radius: 4))
            for x in [20.0, 68.0] {
                layer.fill(Path(ellipseIn: CGRect(x: x, y: 82, width: 14, height: 9)),
                           with: .color(spec.blush.opacity(spec.cheek)))
            }
        }
    }

    private func drawFace(in context: inout GraphicsContext, spec: FaceSpec,
                          lid: CGFloat, t: Double) {
        // The pupils drift, as if reading the message beside them.
        let drift = CGSize(width: sin(t * 0.43) * 0.6, height: cos(t * 0.36) * 0.35)
        let openness = max(0.06, 1 - lid * 0.94)

        for side in [-1.0, 1.0] {
            let cx = 50 + side * 11
            let ry = 9.5 * spec.eyeOpen * openness
            let socket = CGRect(x: cx - 9, y: 74 - ry, width: 18, height: ry * 2)
            let eye = Path(ellipseIn: socket)

            context.fill(eye, with: .color(Palette.white))
            context.stroke(eye, with: .color(spec.ink), lineWidth: 1.6)

            context.drawLayer { layer in
                layer.clip(to: eye)
                let ix = cx + spec.pupilOffset.width + drift.width
                let iy = 74 + spec.pupilOffset.height * openness + drift.height

                layer.fill(Path(ellipseIn: CGRect(x: ix - 4.6, y: iy - 4.6 * openness,
                                                  width: 9.2, height: 9.2 * openness)),
                           with: .color(Palette.pupil))
                layer.fill(Path(ellipseIn: CGRect(x: ix - 3.4, y: iy - 4.2 * openness,
                                                  width: 3.6, height: 3.6 * openness)),
                           with: .color(.white.opacity(0.95)))

                // The angry lid: a hard wedge falling toward the INNER corner. Slope it
                // the other way and the identical shape reads as tired and sad.
                guard spec.lidWedge > 0.01 else { return }
                let drop = socket.height * spec.lidWedge
                let innerIsRight = side < 0
                var wedge = Path()
                wedge.move(to: CGPoint(x: socket.minX - 3, y: socket.minY - 4))
                wedge.addLine(to: CGPoint(x: socket.maxX + 3, y: socket.minY - 4))
                wedge.addLine(to: CGPoint(x: socket.maxX + 3,
                                          y: socket.minY + (innerIsRight ? drop : drop * 0.2)))
                wedge.addLine(to: CGPoint(x: socket.minX - 3,
                                          y: socket.minY + (innerIsRight ? drop * 0.2 : drop)))
                wedge.closeSubpath()
                layer.fill(wedge, with: .color(spec.body))
            }
        }

        // Brows, only when something is wrong.
        if spec.browTilt > 0.1 {
            for side in [-1.0, 1.0] {
                let cx = 50 + side * 11
                var brow = Path()
                brow.move(to: CGPoint(x: cx + side * -10, y: 59 + spec.browTilt))
                brow.addLine(to: CGPoint(x: cx + side * 10, y: 59 - spec.browTilt * 0.55))
                context.stroke(brow, with: .color(spec.ink),
                               style: StrokeStyle(lineWidth: spec.browWeight, lineCap: .round))
            }
        }

        var mouth = Path()
        switch spec.mouth {
        case .smile:
            mouth.move(to: CGPoint(x: 42, y: 89))
            mouth.addQuadCurve(to: CGPoint(x: 58, y: 89), control: CGPoint(x: 50, y: 97))
        case .wavy:
            mouth.move(to: CGPoint(x: 42, y: 91))
            mouth.addQuadCurve(to: CGPoint(x: 48, y: 89), control: CGPoint(x: 45, y: 87))
            mouth.addQuadCurve(to: CGPoint(x: 54, y: 91), control: CGPoint(x: 51, y: 93))
            mouth.addQuadCurve(to: CGPoint(x: 60, y: 89), control: CGPoint(x: 57, y: 87))
        case .frown:
            // A stroke, never a filled shape. Filled, at this scale, it stops reading as
            // a mouth and starts reading as lipstick.
            mouth.move(to: CGPoint(x: 42, y: 95))
            mouth.addQuadCurve(to: CGPoint(x: 58, y: 95), control: CGPoint(x: 50, y: 86))
        }
        context.stroke(mouth, with: .color(spec.ink),
                       style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
    }
}

// MARK: - Expression

/// One mood, ears to mouth. The ears are the headline; the face only confirms.
struct FaceSpec {
    enum Mouth { case smile, wavy, frown }

    /// Degrees each ear swings back from upright. 0 is perked, ~96 is pinned flat.
    var earAngle: Double
    /// Extra rotation on the left ear only, so a pose isn't a mirror of itself.
    var earAsymmetry: Double
    var earFlutter: Double
    var earTempo: Double

    var width: CGFloat
    var lean: Double
    var bobAmount: Double
    var swayAmount: Double
    var tempo: Double
    /// High-frequency shake. Only the last rung has any.
    var shiver: Double

    var eyeOpen: CGFloat
    var pupilOffset: CGSize
    /// How far a hard angled lid cuts into the eye.
    var lidWedge: CGFloat
    var browTilt: CGFloat
    var browWeight: CGFloat
    var mouth: Mouth
    var cheek: Double

    var body: Color
    var lit: Color
    var shade: Color
    var earFill: Color
    var ink: Color
    var blush: Color
}

extension NudgeMood {
    var face: FaceSpec {
        switch self {
        case .calm:
            // Ears up and fluttering, bouncing, blushing. Nothing is wrong yet.
            FaceSpec(earAngle: 0, earAsymmetry: 0, earFlutter: 13, earTempo: 3.4,
                     width: 32, lean: -1.5, bobAmount: 3.0, swayAmount: 1.3, tempo: 1.6,
                     shiver: 0,
                     eyeOpen: 1.0, pupilOffset: CGSize(width: -0.6, height: 0),
                     lidWedge: 0, browTilt: 0, browWeight: 3, mouth: .smile, cheek: 0.7,
                     body: Palette.calm, lit: Palette.calmLit, shade: Palette.calmShade,
                     earFill: Palette.calmEar, ink: Palette.calmInk, blush: Palette.blush)

        case .concerned:
            // One ear cocked back, head tilted, eyes narrowed and looking away: "really?"
            FaceSpec(earAngle: 10, earAsymmetry: 34, earFlutter: 4, earTempo: 1.3,
                     width: 32, lean: 8, bobAmount: 1.6, swayAmount: 0.6, tempo: 0.95,
                     shiver: 0,
                     eyeOpen: 0.82, pupilOffset: CGSize(width: -2.2, height: -1.0),
                     lidWedge: 0.2, browTilt: 3.0, browWeight: 3.2, mouth: .wavy,
                     cheek: 0.2,
                     body: Palette.warn, lit: Palette.warnLit, shade: Palette.warnShade,
                     earFill: Palette.warnEar, ink: Palette.warnInk, blush: Palette.blush)

        case .alarmed:
            // Both ears pinned flat back, wider stance, shivering. Out of patience.
            FaceSpec(earAngle: 96, earAsymmetry: 0, earFlutter: 3, earTempo: 14,
                     width: 34, lean: 0, bobAmount: 0.8, swayAmount: 0.2, tempo: 2.8,
                     shiver: 0.5,
                     eyeOpen: 0.94, pupilOffset: CGSize(width: 0, height: -0.6),
                     lidWedge: 0.58, browTilt: 6.0, browWeight: 4.2, mouth: .frown,
                     cheek: 0.28,
                     body: Palette.cross, lit: Palette.crossLit, shade: Palette.crossShade,
                     earFill: Palette.crossEar, ink: Palette.crossInk, blush: Palette.flush)
        }
    }
}

// MARK: - Palette

/// The body shifts temperature with the mood — mint, sand, dusty rose — and each mood
/// carries its own `ink`, a much darker tone of the same hue. One black outline across all
/// three would read as a printed sticker; a tinted one reads as drawn.
private enum Palette {
    static let calmLit = Color(red: 0.85, green: 0.98, blue: 0.95)
    static let calm = Color(red: 0.49, green: 0.81, blue: 0.75)
    static let calmShade = Color(red: 0.21, green: 0.56, blue: 0.52)
    static let calmEar = Color(red: 0.62, green: 0.87, blue: 0.82)
    static let calmInk = Color(red: 0.06, green: 0.30, blue: 0.28)

    static let warnLit = Color(red: 0.99, green: 0.94, blue: 0.82)
    static let warn = Color(red: 0.95, green: 0.79, blue: 0.42)
    static let warnShade = Color(red: 0.70, green: 0.52, blue: 0.14)
    static let warnEar = Color(red: 0.97, green: 0.87, blue: 0.63)
    static let warnInk = Color(red: 0.28, green: 0.19, blue: 0.03)

    static let crossLit = Color(red: 0.99, green: 0.86, blue: 0.84)
    static let cross = Color(red: 0.93, green: 0.56, blue: 0.55)
    static let crossShade = Color(red: 0.63, green: 0.24, blue: 0.26)
    static let crossEar = Color(red: 0.95, green: 0.69, blue: 0.68)
    static let crossInk = Color(red: 0.30, green: 0.07, blue: 0.09)

    static let blush = Color(red: 0.97, green: 0.49, blue: 0.53)
    static let flush = Color(red: 0.84, green: 0.22, blue: 0.26)
    static let white = Color(red: 0.99, green: 0.99, blue: 0.99)
    static let pupil = Color(red: 0.09, green: 0.14, blue: 0.18)
}
