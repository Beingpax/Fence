import SwiftUI

/// The breathing visual: a constellation that opens and gathers with the breath.
///
/// On the out-breath every star draws together into a tight knot with a warm glow at its
/// heart. Breathing in, they open out into a wide sky, and thin lines draw themselves from
/// star to star until a constellation appears; letting go, the lines retract and the stars
/// gather again.
///
/// What makes it feel alive rather than animated:
/// - **Depth.** Three layers: faint distant stars that barely move, the constellation
///   itself, and a few large near stars that travel furthest. The difference in travel is
///   what reads as drifting forward into the sky.
/// - **Each star is its own.** Warm and cool whites, each twinkling on its own clock, the
///   whole sky turning very slowly with each depth at its own pace.
/// - **A shooting star** crosses the upper sky every thirteen seconds or so.
///
/// It's cheap: one `Canvas` at 30 frames a second, the stars generated once from a fixed
/// seed, and each one stamped from a single pre-drawn glow (`symbols`), never re-rendered.
/// The breath is computed from the clock (3 s in, 2 s out) so it stays in step with the cue.
/// It was chosen by the user from six studies; an organic blob before it was rejected.
struct ConstellationBreath: View {
    /// When the breathing started. Before that, the stars sit gathered.
    let start: Date?
    let animates: Bool

    @State private var origin = Date()

    /// 0 at the bottom of the out-breath, 1 at the top of the in-breath.
    static func breath(at date: Date, start: Date?) -> Double {
        guard let start else { return 0 }
        let t = max(0, date.timeIntervalSince(start)).truncatingRemainder(dividingBy: 5)
        func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        return t < 3 ? smooth(t / 3) : 1 - smooth((t - 3) / 2)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animates)) { timeline in
            let time = timeline.date.timeIntervalSince(origin)
            let b = animates ? Self.breath(at: timeline.date, start: start) : 0.7

            Canvas { context, size in
                Self.draw(in: &context, size: size, time: animates ? time : 0, breath: b, animates: animates)
            } symbols: {
                ForEach(Array(Sky.tints.enumerated()), id: \.offset) { index, tint in
                    Circle()
                        .fill(RadialGradient(
                            stops: [
                                .init(color: tint, location: 0),
                                .init(color: tint.opacity(0.9), location: 0.12),
                                .init(color: tint.opacity(0.28), location: 0.32),
                                .init(color: tint.opacity(0), location: 1),
                            ],
                            center: .center, startRadius: 0, endRadius: 32
                        ))
                        .frame(width: 64, height: 64)
                        .tag(index)
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Drawing

    private static func draw(in context: inout GraphicsContext, size: CGSize, time: Double, breath b: Double, animates: Bool) {
        // The sky is laid out on a square of side `w`, centred, squashed a little vertically.
        let w = min(size.width, size.height / 0.86)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        context.blendMode = .plusLighter

        // The knot of light the stars gather into. Brightest when closed.
        let core = (1 - b) * 0.55 + 0.08
        let coreRadius = w * (0.08 + b * 0.22)
        context.fill(
            Path(ellipseIn: CGRect(x: c.x - coreRadius, y: c.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(red: 1, green: 0.97, blue: 0.93).opacity(core), location: 0),
                    .init(color: Color(red: 0.86, green: 0.89, blue: 1).opacity(core * 0.35), location: 0.4),
                    .init(color: Color(red: 0.78, green: 0.82, blue: 1).opacity(0), location: 1),
                ]),
                center: c, startRadius: 0, endRadius: coreRadius
            )
        )

        // Where every star is this frame: blended from its place in the knot to its place
        // in the open sky, the sky slowly turning, each depth at its own pace.
        var points = [CGPoint](repeating: .zero, count: Sky.stars.count)
        for (index, star) in Sky.stars.enumerated() {
            let layer = Sky.layers[star.depth]
            let open = min(1, b * layer.reach + (1 - layer.reach) * b * b)
            let spin = time * layer.spin
            let spread = 0.9 + layer.reach * 0.1
            let kx = cos(star.knotAngle) * star.knot, ky = sin(star.knotAngle) * star.knot
            let ox = cos(star.angle + spin) * star.radius * spread
            let oy = sin(star.angle + spin) * star.radius * 0.82 * spread
            let scale = star.depth == 2 ? 1.12 : 1
            points[index] = CGPoint(x: c.x + (kx + (ox - kx) * open) * w * scale,
                                    y: c.y + (ky + (oy - ky) * open) * w * scale)
        }

        // Lines draw themselves outward as the breath fills, and retract as it empties.
        for edge in Sky.edges {
            let t = max(0, min(1, (b - 0.35 - edge.delay * 0.4) / 0.4))
            guard t > 0 else { continue }
            let a = points[edge.from], d = points[edge.to]
            let end = CGPoint(x: a.x + (d.x - a.x) * t, y: a.y + (d.y - a.y) * t)
            var line = Path()
            line.move(to: a)
            line.addLine(to: end)
            context.stroke(line, with: .linearGradient(
                Gradient(colors: [.white.opacity(0.38 * t), .white.opacity(0.12 * t)]),
                startPoint: a, endPoint: end
            ), lineWidth: 0.8)
        }

        // The stars, each twinkling on its own clock, stamped from the pre-drawn glow.
        for (index, star) in Sky.stars.enumerated() {
            guard let glow = context.resolveSymbol(id: star.tint) else { continue }
            let layer = Sky.layers[star.depth]
            let twinkle = 0.65 + 0.35 * sin(time * star.twinkle + star.phase)
            let side = star.size * (star.depth == 1 ? 1 + b * 0.25 : 1) * 7
            let p = points[index]
            context.opacity = layer.alpha * twinkle
            context.draw(glow, in: CGRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side))
        }
        context.opacity = 1

        // Now and then, a shooting star across the upper sky.
        guard animates else { return }
        let every = 13.0, offset = 4.0
        let round = ((time - offset) / every).rounded(.down)
        let local = time - offset - round * every
        guard round >= 0, local >= 0, local < 1.1 else { return }
        let hash = { (n: Double) in abs((sin(round * 12.9898 + n) * 43758.5453).truncatingRemainder(dividingBy: 1)) }
        let fromLeft = hash(1) < 0.5
        let dir: Double = fromLeft ? 1 : -1
        let p = local / 1.1
        let length = w * 0.22
        let head = CGPoint(x: (fromLeft ? size.width * 0.1 : size.width * 0.9) + dir * w * 0.55 * p,
                           y: c.y - w * 0.36 + w * (0.12 + hash(2) * 0.2) + w * 0.18 * p)
        let tail = CGPoint(x: head.x - dir * length, y: head.y - length * 0.33)
        var streak = Path()
        streak.move(to: head)
        streak.addLine(to: tail)
        context.stroke(streak, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.85 * sin(p * .pi)), .white.opacity(0)]),
            startPoint: head, endPoint: tail
        ), lineWidth: 1.2)
    }
}

// MARK: - The sky, generated once

private enum Sky {
    struct Layer {
        let count: Int
        let reach: Double
        let size: ClosedRange<Double>
        let alpha: Double
        let spin: Double
    }

    struct Star {
        let depth: Int
        let angle: Double
        let radius: Double
        let size: Double
        let tint: Int
        let twinkle: Double
        let phase: Double
        let knot: Double
        let knotAngle: Double
    }

    struct Edge {
        let from: Int
        let to: Int
        let delay: Double
    }

    /// Far, the constellation itself, and near.
    static let layers = [
        Layer(count: 46, reach: 0.62, size: 0.6...1.3, alpha: 0.55, spin: 0.006),
        Layer(count: 26, reach: 1.0, size: 1.2...2.2, alpha: 0.95, spin: 0.010),
        Layer(count: 9, reach: 1.4, size: 2.0...3.2, alpha: 0.75, spin: 0.016),
    ]

    /// White, warm and cool, so the sky isn't one flat colour.
    static let tints: [Color] = [
        Color(red: 1, green: 1, blue: 1),
        Color(red: 1, green: 0.93, blue: 0.84),
        Color(red: 0.84, green: 0.89, blue: 1),
        Color(red: 1, green: 0.96, blue: 0.93),
        Color(red: 0.89, green: 0.93, blue: 1),
    ]

    static var stars: [Star] { generated.stars }
    static var edges: [Edge] { generated.edges }

    private static let generated: (stars: [Star], edges: [Edge]) = {
        var seed: Int64 = 11
        func rand() -> Double {
            seed = (seed * 16807) % 2_147_483_647
            return Double(seed) / 2_147_483_647
        }

        var stars: [Star] = []
        for (depth, layer) in layers.enumerated() {
            for _ in 0..<layer.count {
                let angle = rand() * 2 * .pi
                let radius = 0.14 + pow(rand(), 0.75) * 0.34
                let size = layer.size.lowerBound + rand() * (layer.size.upperBound - layer.size.lowerBound)
                stars.append(Star(
                    depth: depth, angle: angle, radius: radius, size: size,
                    tint: Int(rand() * Double(tints.count)) % tints.count,
                    twinkle: 0.6 + rand() * 1.8, phase: rand() * 2 * .pi,
                    knot: 0.02 + rand() * 0.06, knotAngle: rand() * 2 * .pi
                ))
            }
        }

        // Join the constellation layer with a small spanning tree, nearest neighbour first,
        // so the figure reads as drawn rather than random. Very long jumps are left out.
        let mid = stars.indices.filter { stars[$0].depth == 1 }
        func spot(_ i: Int) -> (Double, Double) {
            (cos(stars[i].angle) * stars[i].radius, sin(stars[i].angle) * stars[i].radius * 0.82)
        }
        var inTree: Set<Int> = [mid[0]]
        var edges: [Edge] = []
        while inTree.count < mid.count {
            var best: (a: Int, b: Int, d: Double)?
            for a in inTree {
                for b in mid where !inTree.contains(b) {
                    let (ax, ay) = spot(a), (bx, by) = spot(b)
                    let d = hypot(ax - bx, ay - by)
                    if best == nil || d < best!.d { best = (a, b, d) }
                }
            }
            guard let best else { break }
            inTree.insert(best.b)
            if best.d < 0.2 { edges.append(Edge(from: best.a, to: best.b, delay: rand() * 0.35)) }
        }
        return (stars, edges)
    }()
}
