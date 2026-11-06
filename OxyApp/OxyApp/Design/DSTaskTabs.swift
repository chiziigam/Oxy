import SwiftUI

/// One task shown as a circle on the composer's tab.
struct DSTaskItem: Identifiable, Equatable {
    let id: String
    let title: String
    var needsYou = false
    var working = false
    var icon: DSIcon?

    /// A small icon for what kind of task this is, from its title. Nothing matches means its first letter.
    static func icon(for title: String) -> DSIcon? {
        let t = title.lowercased()
        let groups: [(DSIcon, [String])] = [
            (.train, ["train", "flight", "trip", "travel", "hotel", "uber", "taxi"]),
            (.card, ["pay", "bill", "invoice", "card", "refund", "£", "$"]),
            (.bag, ["order", "grocer", "buy", "basket", "shop", "delivery"]),
            (.search, ["find", "search", "compare", "look", "research"])
        ]
        return groups.first { _, words in words.contains { t.contains($0) } }?.0
    }
}

/// The composer and its tab drawn as one outline: the box, a raised tab for the task circles,
/// and a smaller tab on the right, joined with curved shoulders. No stroke; it is filled.
/// Each tab top is a half-circle around its circle (8 points of room), so the two curves are
/// concentric. The other corners ease into their edges instead of meeting them at a hard angle.
struct DSComposerShape: Shape {
    var leftTabWidth: CGFloat
    var rightTabWidth: CGFloat = DSTaskTabRow.circle + DSTaskTabRow.pad * 2
    var tabHeight: CGFloat = DSTaskTabRow.height
    static let inset: CGFloat = 52

    func path(in rect: CGRect) -> Path {
        let w = rect.width, t = tabHeight, h = rect.height - tabHeight
        let x0 = Self.inset, x1 = Self.inset + leftTabWidth
        let rx1 = w - Self.inset, rx0 = rx1 - rightTabWidth
        let top = t / 2          // a full half-circle, concentric with the circle inside
        // point, radius, how far the curve eases out, and how much longer the flat side's reach is
        let corners: [(CGPoint, CGFloat, CGFloat, CGFloat)] = [
            (CGPoint(x: 0, y: t), 24, 0, 1),
            (CGPoint(x: x0, y: t), 14, 0.5, 1.8), (CGPoint(x: x0, y: 0), top, 0, 1),
            (CGPoint(x: x1, y: 0), top, 0, 1), (CGPoint(x: x1, y: t), 14, 0.5, 1.8),
            (CGPoint(x: rx0, y: t), 14, 0.5, 1.8), (CGPoint(x: rx0, y: 0), top, 0, 1),
            (CGPoint(x: rx1, y: 0), top, 0, 1), (CGPoint(x: rx1, y: t), 14, 0.5, 1.8),
            (CGPoint(x: w, y: t), 24, 0, 1), (CGPoint(x: w, y: t + h), 24, 0, 1), (CGPoint(x: 0, y: t + h), 24, 0, 1)
        ]
        func unit(_ a: CGPoint, _ b: CGPoint) -> (CGPoint, CGFloat) {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = max((dx * dx + dy * dy).squareRoot(), 0.0001)
            return (CGPoint(x: dx / length, y: dy / length), length)
        }
        let n = corners.count
        var path = Path()
        path.move(to: CGPoint(x: 0, y: t + h / 2))
        for i in 0..<n {
            let v = corners[i].0
            let (d1, len1) = unit(corners[(i + n - 1) % n].0, v)
            let (d2, len2) = unit(v, corners[(i + 1) % n].0)
            let base = (1 + corners[i].2) * corners[i].1
            let flare = corners[i].3
            let reach1 = min(base * (abs(d1.x) > 0.5 ? flare : 1), len1 / 2)
            let reach2 = min(base * (abs(d2.x) > 0.5 ? flare : 1), len2 / 2)
            let c: CGFloat = 0.45
            let start = CGPoint(x: v.x - d1.x * reach1, y: v.y - d1.y * reach1)
            let end = CGPoint(x: v.x + d2.x * reach2, y: v.y + d2.y * reach2)
            path.addLine(to: start)
            path.addCurve(
                to: end,
                control1: CGPoint(x: v.x - d1.x * reach1 * c, y: v.y - d1.y * reach1 * c),
                control2: CGPoint(x: v.x + d2.x * reach2 * c, y: v.y + d2.y * reach2 * c)
            )
        }
        path.closeSubpath()
        return path
    }
}

/// The row of circles that sits in the tab: the main conversation first, then each open task.
struct DSTaskTabRow: View {
    var tasks: [DSTaskItem]
    var onTask: (DSTaskItem) -> Void
    var onNew: () -> Void

    static let circle: CGFloat = 28
    static let gap: CGFloat = 6
    static let pad: CGFloat = 5
    static let height: CGFloat = 38

    /// Width of the left tab for this many tasks, plus the main-conversation circle.
    static func leftWidth(_ count: Int) -> CGFloat {
        pad * 2 + CGFloat(count + 1) * circle + CGFloat(count) * gap
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: Self.gap) {
                ZStack {
                    Circle().fill(DS.ink)
                    DSIconView(icon: .mark, size: 15).foregroundStyle(DS.bg)
                }
                .frame(width: Self.circle, height: Self.circle)
                .accessibilityLabel("Main conversation")
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    Button { onTask(task) } label: { DSTaskCircle(item: task, ringStyle: index) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(task.title + (task.needsYou ? ", needs you" : ""))
                }
            }
            .padding(.horizontal, Self.pad)
            .padding(.leading, DSComposerShape.inset)
            Spacer(minLength: 0)
            Button(action: onNew) {
                ZStack {
                    Circle().fill(DS.bg)
                    DSIconView(icon: .plus, size: 15).foregroundStyle(DS.ink)
                }
                .frame(width: Self.circle, height: Self.circle)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DSTaskTabRow.pad)
            .padding(.trailing, DSComposerShape.inset)
            .accessibilityLabel("New task")
        }
        .frame(height: Self.height)
    }
}

struct DSTaskCircle: View {
    let item: DSTaskItem
    var ringStyle = 0

    var body: some View {
        ZStack {
            Circle().fill(DS.bg)
            if let icon = item.icon {
                DSIconView(icon: icon, size: 14).foregroundStyle(DS.ink)
            } else {
                Text(String(item.title.first.map { Character($0.uppercased()) } ?? "•"))
                    .font(.ds(12, .semibold))
                    .foregroundStyle(DS.ink)
            }
            if item.working { DSTaskRing(style: ringStyle).frame(width: 34, height: 34).allowsHitTesting(false) }
        }
        .frame(width: DSTaskTabRow.circle, height: DSTaskTabRow.circle)
        .overlay(alignment: .topTrailing) {
            if item.needsYou {
                Circle().fill(DS.ink).frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(DS.card, lineWidth: 2).frame(width: 13, height: 13))
                    .offset(x: 2, y: -2)
            }
        }
    }
}

/// A thin moving ring around a working task. Each working task gets a different motion.
struct DSTaskRing: View {
    var style: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 1.0 : context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = size.width / 2 - 2.5
                func ring(_ radius: Double, _ alpha: Double, _ width: Double = 1.4, dash: [CGFloat] = [], phase: CGFloat = 0) {
                    let path = Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
                    gc.stroke(path, with: .color(DS.ink.opacity(alpha)), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash, dashPhase: phase))
                }
                switch style % 4 {
                case 0: // an orbiting dot
                    ring(r, 0.22)
                    let a = t * 2.6
                    let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                    gc.fill(Path(ellipseIn: CGRect(x: p.x - 2.4, y: p.y - 2.4, width: 4.8, height: 4.8)), with: .color(DS.ink))
                case 1: // turning dashes
                    ring(r, 0.9, 1.6, dash: [2.5, 5], phase: CGFloat(-t * 14))
                case 2: // pulsing
                    for k in 0..<2 {
                        let p = (t * 0.7 + Double(k) / 2).truncatingRemainder(dividingBy: 1)
                        ring(r - 3 + p * 4.5, (1 - p) * 0.8, 1.5)
                    }
                default: // two arcs chasing
                    for k in 0..<2 {
                        let a = t * 2.2 + Double(k) * .pi
                        var arc = Path()
                        for step in 0...12 {
                            let angle = a + 1.5 * Double(step) / 12
                            let q = CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
                            step == 0 ? arc.move(to: q) : arc.addLine(to: q)
                        }
                        gc.stroke(arc, with: .color(DS.ink.opacity(0.95)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    }
                }
            }
        }
    }
}
