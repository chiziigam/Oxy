import SwiftUI

/// The small animations shown beside the step in progress. For long work they take turns.
enum DSWorkKind: CaseIterable {
    case figureEight, spark, morph, hex, pendulum, sunflower, flip, attractor
}

/// One graphic at a time, in a square of `size` points, switching to the next every few seconds
/// for as long as the work runs. `since` is when the work started, so the order carries on
/// across steps instead of restarting.
struct DSWorkingGraphic: View {
    var since: Date
    var size: CGFloat = 18

    static let interval: TimeInterval = 8

    @State private var index = 0

    var body: some View {
        let kinds = DSWorkKind.allCases
        DSWorkCanvas(kind: kinds[index % kinds.count], size: size)
        .id(index)
        .transition(.opacity.combined(with: .scale(scale: 0.6)))
        .frame(width: size, height: size)
        .onAppear { index = Self.current(since) }
        .task {
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(since)
                let wait = Self.interval - elapsed.truncatingRemainder(dividingBy: Self.interval)
                try? await Task.sleep(for: .seconds(wait))
                if Task.isCancelled { break }
                withAnimation(.smooth(duration: 0.5)) { index = Self.current(since) }
            }
        }
    }

    private static func current(_ since: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(since) / interval))
    }
}

private struct DSWorkCanvas: View {
    let kind: DSWorkKind
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 3.0 : context.date.timeIntervalSinceReferenceDate
            Canvas { gc, canvasSize in
                gc.scaleBy(x: canvasSize.width / 96, y: canvasSize.height / 96)
                DSWorkDrawing.draw(kind, &gc, t, DS.ink)
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Drawing (all in a 96 x 96 space)

private enum DSWorkDrawing {
    static func draw(_ kind: DSWorkKind, _ gc: inout GraphicsContext, _ t: Double, _ ink: Color) {
        switch kind {
        case .figureEight: figureEight(&gc, t, ink)
        case .spark: spark(&gc, t, ink)
        case .morph: morph(&gc, t, ink)
        case .hex: hex(&gc, t, ink)
        case .pendulum: pendulum(&gc, t, ink)
        case .sunflower: sunflower(&gc, t, ink)
        case .flip: flip(&gc, t, ink)
        case .attractor: attractor(&gc, t, ink)
        }
    }

    private static func dot(_ gc: inout GraphicsContext, _ x: Double, _ y: Double, _ r: Double, _ alpha: Double, _ ink: Color) {
        gc.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(ink.opacity(alpha)))
    }

    static func spark(_ gc: inout GraphicsContext, _ t: Double, _ ink: Color) {
        let n = 12
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi + t * 0.7
            let g = 0.5 + 0.5 * sin(t * 2.2 + Double(i) * (2 * .pi / Double(n)) * 2)
            let r0 = 8 + 5 * g, r1 = r0 + 10 + 22 * g
            var p = Path()
            p.move(to: CGPoint(x: 48 + cos(a) * r0, y: 48 + sin(a) * r0))
            p.addLine(to: CGPoint(x: 48 + cos(a) * r1, y: 48 + sin(a) * r1))
            gc.stroke(p, with: .color(ink.opacity(0.3 + 0.7 * g)), style: StrokeStyle(lineWidth: 5 + 4 * g, lineCap: .round))
        }
    }

    static func morph(_ gc: inout GraphicsContext, _ t: Double, _ ink: Color) {
        let sides = [3, 4, 6, 0]
        let hold = 0.9, move = 0.7, period = hold + move
        let cycle = t.truncatingRemainder(dividingBy: period * Double(sides.count))
        let index = Int(cycle / period)
        let local = cycle - Double(index) * period
        var e = 0.0
        if local > hold {
            let u = (local - hold) / move
            e = u < 0.5 ? 2 * u * u : 1 - pow(-2 * u + 2, 2) / 2
        }
        let a = sides[index], b = sides[(index + 1) % sides.count]
        func radius(_ n: Int, _ th: Double) -> Double {
            if n == 0 { return 1 }
            let seg = 2 * Double.pi / Double(n)
            var m = th.truncatingRemainder(dividingBy: seg)
            if m < 0 { m += seg }
            return cos(.pi / Double(n)) / cos(m - .pi / Double(n))
        }
        let spin = t * 0.5
        var path = Path()
        for i in 0...120 {
            let th = Double(i) / 120 * 2 * .pi
            let r = (radius(a, th) * (1 - e) + radius(b, th) * e) * 34
            let p = CGPoint(x: 48 + cos(th + spin) * r, y: 48 + sin(th + spin) * r)
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        gc.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: 6, lineJoin: .round))
    }

    static func hex(_ gc: inout GraphicsContext, _ t: Double, _ ink: Color) {
        let r = 15.0, dx = r * 1.5, dy = r * 0.866
        let cells: [(Double, Double)] = [(0, 0), (1, -1), (1, 1), (0, -2), (0, 2), (-1, -1), (-1, 1)]
        for (i, cell) in cells.enumerated() {
            let cx = 48 + cell.0 * dx, cy = 48 + cell.1 * dy
            let lit = pow(0.5 + 0.5 * sin(t * 2.6 - Double(i) * 0.9), 2.2)
            var path = Path()
            for k in 0..<6 {
                let a = Double(k) * .pi / 3
                let p = CGPoint(x: cx + cos(a) * (r - 2), y: cy + sin(a) * (r - 2))
                k == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            path.closeSubpath()
            gc.fill(path, with: .color(ink.opacity(0.1 + 0.9 * lit)))
        }
    }

    static func pendulum(_ gc: inout GraphicsContext, _ t: Double, _ ink: Color) {
        let n = 7
        for i in 0..<n {
            let x = 14 + Double(i) * (68 / Double(n - 1))
            let y = 48 + 28 * sin(2 * .pi * Double(10 + i) * t / 8)
            dot(&gc, x, y, 5.5, 0.9, ink)
        }
    }

    static func sunflower(_ gc: inout GraphicsContext, _ t: Double, _ ink: Color) {
        let n = 64
        let golden = 137.508 * Double.pi / 180
        for i in 1...n {
            let fi = Double(i)
            let phase = sin(t * 2.2 - fi * 0.16)
            let swell = 1 + 0.07 * phase
            let r = fi.squareRoot() * 5 * swell
            let a = fi * golden + t * 0.35
            dot(&gc, 48 + cos(a) * r, 48 + sin(a) * r, 1.8 + 1.4 * (fi / Double(n)), 0.35 + 0.65 * (0.5 + 0.5 * phase), ink)
        }
    }

    static func flip(_ gc: inout GraphicsContext, _ t: Double, _ ink: Color) {
        for i in 0..<3 {
            for j in 0..<3 {
                let phase = t * 3.2 - Double(i + j) * 0.55
                let s = cos(phase)
                let h = 24 * max(abs(s), 0.05)
                let rect = CGRect(x: 10 + Double(i) * 28, y: 48 + Double(j - 1) * 28 - h / 2, width: 24, height: h)
                gc.fill(Path(roundedRect: rect, cornerRadius: min(5, h / 2)), with: .color(ink.opacity(s > 0 ? 0.95 : 0.3)))
            }
        }
    }

    // MARK: Three bodies chasing along a figure eight

    private enum Orbit {
        static let period = 6.3259
        static let count = 2400

        /// Positions of the three bodies over one period, from the published starting values.
        static let samples: [[CGPoint]] = {
            var p: [[Double]] = [
                [-0.97000436, 0.24308753, 0.46620369, 0.43236573],
                [0.97000436, -0.24308753, 0.46620369, 0.43236573],
                [0, 0, -0.93240737, -0.86473146]
            ]
            func acceleration(_ p: [[Double]]) -> [[Double]] {
                p.enumerated().map { i, body in
                    var ax = 0.0, ay = 0.0
                    for (j, other) in p.enumerated() where i != j {
                        let dx = other[0] - body[0], dy = other[1] - body[1]
                        let d = pow(dx * dx + dy * dy + 1e-6, 1.5)
                        ax += dx / d
                        ay += dy / d
                    }
                    return [ax, ay]
                }
            }
            let perSample = 5
            let h = period / Double(count * perSample)
            var out = [[CGPoint]](repeating: [], count: 3)
            for _ in 0..<count {
                for b in 0..<3 { out[b].append(CGPoint(x: p[b][0], y: p[b][1])) }
                for _ in 0..<perSample {
                    var a = acceleration(p)
                    for b in 0..<3 {
                        p[b][2] += a[b][0] * h / 2
                        p[b][3] += a[b][1] * h / 2
                        p[b][0] += p[b][2] * h
                        p[b][1] += p[b][3] * h
                    }
                    a = acceleration(p)
                    for b in 0..<3 {
                        p[b][2] += a[b][0] * h / 2
                        p[b][3] += a[b][1] * h / 2
                    }
                }
            }
            return out
        }()
    }

    static func figureEight(_ gc: inout GraphicsContext, _ t: Double, _ ink: Color) {
        let n = Orbit.count
        func point(_ body: Int, _ simTime: Double) -> CGPoint {
            var u = simTime.truncatingRemainder(dividingBy: Orbit.period)
            if u < 0 { u += Orbit.period }
            let q = Orbit.samples[body][Int(u / Orbit.period * Double(n)) % n]
            return CGPoint(x: 48 + q.x * 33, y: 48 + q.y * 33)
        }
        let sim = t * 0.9
        for body in 0..<3 {
            for m in stride(from: 25, through: 1, by: -1) {
                let p = point(body, sim - Double(m) * 0.015)
                dot(&gc, p.x, p.y, 2, pow(1 - Double(m) / 26, 2) * 0.6, ink)
            }
            let p = point(body, sim)
            dot(&gc, p.x, p.y, 4.8, 1, ink)
        }
    }

    // MARK: Particles riding the Lorenz butterfly

    private enum Lorenz {
        static let count = 9000

        static let samples: [(Double, Double, Double)] = {
            var x = 1.0, y = 1.0, z = 1.0
            let h = 0.005
            func step() {
                let nx = x + 10 * (y - x) * h
                let ny = y + (x * (28 - z) - y) * h
                let nz = z + (x * y - 8.0 / 3.0 * z) * h
                x = nx; y = ny; z = nz
            }
            for _ in 0..<2000 { step() }
            var out: [(Double, Double, Double)] = []
            out.reserveCapacity(count)
            for _ in 0..<count { out.append((x, y, z)); step() }
            return out
        }()
    }

    static func attractor(_ gc: inout GraphicsContext, _ t: Double, _ ink: Color) {
        let n = Lorenz.count
        let angle = t * 0.35
        let ca = cos(angle), sa = sin(angle)
        let base = Int(t * 280) % n
        for i in 0..<46 {
            let p = Lorenz.samples[(base + i * 1237) % n]
            let px = p.0 * ca + p.1 * sa
            dot(&gc, 48 + px * 2.1, 90 - p.2 * 1.55, 2.6, 0.9, ink)
        }
    }
}
