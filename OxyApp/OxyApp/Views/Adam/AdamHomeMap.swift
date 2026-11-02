import SwiftUI

// MARK: - The map

/// The home drawn in isometric, one floor plate per room, with each paired device standing in it.
/// The plan is laid out from the rooms you've named; it is not a measured floor plan.
struct HomeMap: View {
    struct Room: Identifiable {
        let name: String
        let devices: [HomeModel.Device]
        var id: String { "\(name)-\(devices.map(\.id).joined())" }
        var lit: Bool { devices.contains(where: \.online) }
    }

    var rooms: [Room]
    var compact = false

    static func rooms(from home: HomeModel) -> [Room] {
        var rooms = home.rooms.filter { !$0.devices.isEmpty }.map { Room(name: $0.name, devices: $0.devices) }
        if rooms.isEmpty {
            let placed = home.devices.filter { $0.room != nil }
            let byRoom = Dictionary(grouping: placed, by: { $0.room ?? "" })
            rooms = byRoom.keys.sorted().map { Room(name: $0, devices: byRoom[$0] ?? []) }
        }
        let loose = home.unassignedDevices.isEmpty ? home.devices.filter { $0.room == nil } : home.unassignedDevices
        // A display not placed in a room yet is labelled by its own name.
        rooms += loose.map { Room(name: $0.name, devices: [$0]) }
        let ordered = rooms.sorted { a, b in
            a.lit != b.lit ? a.lit : a.devices.count > b.devices.count
        }
        return Array(ordered.prefix(4))
    }

    /// Plan rectangles in floor units, by how many rooms there are.
    private var plan: [CGRect] {
        switch rooms.count {
        case 1: return [CGRect(x: 0, y: 0, width: 6.4, height: 4.6)]
        case 2: return [CGRect(x: 0, y: 0, width: 5.2, height: 4.4), CGRect(x: 5.2, y: 0, width: 3.6, height: 4.4)]
        case 3: return [CGRect(x: 0, y: 0, width: 5.2, height: 4.4), CGRect(x: 5.2, y: 0, width: 3.6, height: 4.4),
                        CGRect(x: 0, y: 4.4, width: 8.8, height: 1.8)]
        default: return [CGRect(x: 0, y: 0, width: 5, height: 3.4), CGRect(x: 5, y: 0, width: 3.8, height: 3.4),
                         CGRect(x: 0, y: 3.4, width: 5, height: 2.8), CGRect(x: 5, y: 3.4, width: 3.8, height: 2.8)]
        }
    }

    private struct Iso {
        let scale: CGFloat
        let origin: CGPoint
        func point(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat = 0) -> CGPoint {
            let c = cos(CGFloat.pi / 6), s = sin(CGFloat.pi / 6)
            return CGPoint(x: origin.x + (x - y) * c * scale, y: origin.y + (x + y) * s * scale - z * scale)
        }
    }

    private func iso(in size: CGSize) -> Iso {
        let bounds = plan.reduce(CGRect.null) { $0.union($1) }
        let c = cos(CGFloat.pi / 6), s = sin(CGFloat.pi / 6)
        let isoWidth = (bounds.width + bounds.height) * c
        let isoHeight = (bounds.width + bounds.height) * s
        let scale = min(size.width * 0.7 / isoWidth, (size.height - 76) / isoHeight)
        let left = (size.width - isoWidth * scale) / 2
        let top = size.height - isoHeight * scale - 14
        return Iso(scale: scale, origin: CGPoint(x: left + bounds.height * c * scale, y: top))
    }

    private func spot(_ index: Int, in room: CGRect, of count: Int) -> (CGFloat, CGFloat) {
        let step = room.width / CGFloat(count + 1)
        return (room.minX + step * CGFloat(index + 1), room.midY - 0.2)
    }

    var body: some View {
        GeometryReader { proxy in
            let g = iso(in: proxy.size)
            let tags = labels(g: g, width: proxy.size.width)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for (index, room) in rooms.enumerated() where index < plan.count {
                        drawRoom(plan[index], lit: room.lit, g: g, context: &context)
                    }
                    for (index, room) in rooms.enumerated() where index < plan.count {
                        let count = min(room.devices.count, 3)
                        for (n, device) in room.devices.prefix(3).enumerated() {
                            let s = spot(n, in: plan[index], of: count)
                            drawDevice(at: g.point(s.0, s.1), online: device.online, g: g, context: &context)
                        }
                    }
                    for tag in tags {
                        var line = Path()
                        line.move(to: tag.anchor)
                        line.addLine(to: tag.end)
                        context.stroke(line, with: .color(Color.appMuted.opacity(0.7)), lineWidth: 1)
                        context.fill(Path(ellipseIn: CGRect(x: tag.anchor.x - 2, y: tag.anchor.y - 2, width: 4, height: 4)),
                                     with: .color(Color.appMuted))
                    }
                }
                ForEach(tags) { tag in
                    VStack(alignment: tag.trailing ? .trailing : .leading, spacing: 1) {
                        Text(tag.title).font(.role(.footnote, weight: .medium)).foregroundStyle(Color.appInk)
                        Text(tag.state).font(.role(.caption, weight: .medium))
                            .foregroundStyle(tag.online ? Color.appSuccess : Color.appMuted)
                    }
                    .fixedSize()
                    .frame(width: proxy.size.width / 2 - 4, alignment: tag.trailing ? .trailing : .leading)
                    .position(x: tag.trailing ? proxy.size.width * 0.75 - 2 : proxy.size.width * 0.25 + 2, y: tag.textY + 14)
                }
            }
        }
        .frame(height: compact ? 214 : 252)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        rooms.map { room in
            let names = room.devices.map { "\($0.name) \($0.online ? "online" : "offline")" }.joined(separator: ", ")
            return "\(room.name): \(names)"
        }.joined(separator: ". ")
    }

    private func drawRoom(_ r: CGRect, lit: Bool, g: Iso, context: inout GraphicsContext) {
        let h: CGFloat = 0.5
        let floor = [g.point(r.minX, r.minY), g.point(r.maxX, r.minY), g.point(r.maxX, r.maxY), g.point(r.minX, r.maxY)]
        let back = [g.point(r.minX, r.minY), g.point(r.maxX, r.minY), g.point(r.maxX, r.minY, h), g.point(r.minX, r.minY, h)]
        let side = [g.point(r.minX, r.minY), g.point(r.minX, r.maxY), g.point(r.minX, r.maxY, h), g.point(r.minX, r.minY, h)]
        let edge = Color.appInk.opacity(lit ? 0.42 : 0.3)
        let faces: [([CGPoint], Color)] = [
            (floor, lit ? Color.appSuccess.opacity(0.12) : Color.appInk.opacity(0.05)),
            (back, Color.appInk.opacity(lit ? 0.1 : 0.07)),
            (side, Color.appInk.opacity(lit ? 0.08 : 0.055)),
        ]
        for (points, fill) in faces {
            var path = Path()
            path.addLines(points)
            path.closeSubpath()
            context.fill(path, with: .color(fill))
            context.stroke(path, with: .color(edge), lineWidth: 1)
        }
    }

    private func drawDevice(at base: CGPoint, online: Bool, g: Iso, context: inout GraphicsContext) {
        if online {
            let glow = CGRect(x: base.x - g.scale * 2.2, y: base.y - g.scale * 1.1, width: g.scale * 4.4, height: g.scale * 2.2)
            context.fill(Path(ellipseIn: glow), with: .radialGradient(
                Gradient(colors: [Color.appSuccess.opacity(0.32), Color.appSuccess.opacity(0)]),
                center: base, startRadius: 0, endRadius: g.scale * 2.2))
        }
        let size = CGSize(width: g.scale * 1.5, height: g.scale * 1.15)
        DisplayGlyph.draw(in: CGRect(x: base.x - size.width / 2, y: base.y - size.height, width: size.width, height: size.height),
                          online: online, context: &context)
    }

    private struct Tag: Identifiable {
        let id: String
        let title: String
        let state: String
        let online: Bool
        let anchor: CGPoint
        let end: CGPoint
        let textY: CGFloat
        let trailing: Bool
    }

    private func labels(g: Iso, width: CGFloat) -> [Tag] {
        var result: [Tag] = []
        var used: [Bool: [CGFloat]] = [true: [], false: []]
        for (index, room) in rooms.enumerated() where index < plan.count {
            let count = min(room.devices.count, 3)
            guard count > 0 else { continue }
            let s = spot(0, in: plan[index], of: count)
            let base = g.point(s.0, s.1)
            let anchor = CGPoint(x: base.x, y: base.y - g.scale * 1.3)
            let trailing = anchor.x > width / 2
            // Labels sit in the empty corners above the plan, stacked per side, never over a floor.
            let textY = CGFloat(used[trailing, default: []].count) * 40
            used[trailing, default: []].append(textY)
            let endX = trailing ? width - 62 : 62
            result.append(Tag(id: room.name, title: room.name, state: state(for: room), online: room.lit,
                              anchor: anchor, end: CGPoint(x: endX, y: textY + 34), textY: textY, trailing: trailing))
        }
        return result
    }

    private func state(for room: Room) -> String {
        let on = room.devices.filter(\.online).count
        if on == room.devices.count { return on == 1 ? "On" : "\(on) displays on" }
        if on > 0 { return "\(on) of \(room.devices.count) on" }
        return DisplayGlyph.offline(room.devices)
    }
}

/// A small screen on a speaker base, the shape of Adam's display. No lens, so it never reads as a camera.
struct DisplayGlyph: View {
    var online: Bool

    var body: some View {
        Canvas { context, size in
            Self.draw(in: CGRect(origin: .zero, size: size), online: online, context: &context)
        }
        .aspectRatio(1.3, contentMode: .fit)
        .accessibilityHidden(true)
    }

    static func draw(in rect: CGRect, online: Bool, context: inout GraphicsContext) {
        let screen = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.74)
        let corner = screen.height * 0.16
        let edge = Color.appInk.opacity(online ? 0.75 : 0.5)
        context.fill(Path(roundedRect: screen, cornerRadius: corner, style: .continuous),
                     with: .color(online ? Color.appSuccess.opacity(0.22) : Color.appSurface2))
        context.stroke(Path(roundedRect: screen.insetBy(dx: 0.5, dy: 0.5), cornerRadius: corner, style: .continuous),
                       with: .color(edge), lineWidth: 1)
        if online {
            let inset = screen.width * 0.16
            for (n, share) in [0.5, 0.32].enumerated() {
                let bar = CGRect(x: screen.minX + inset, y: screen.minY + screen.height * (0.34 + CGFloat(n) * 0.2),
                                 width: (screen.width - inset * 2) * share, height: max(1.5, screen.height * 0.08))
                context.fill(Path(roundedRect: bar, cornerRadius: bar.height / 2), with: .color(Color.appInk.opacity(0.7)))
            }
        }
        var base = Path()
        base.move(to: CGPoint(x: rect.midX - rect.width * 0.22, y: screen.maxY))
        base.addLine(to: CGPoint(x: rect.midX + rect.width * 0.22, y: screen.maxY))
        base.addLine(to: CGPoint(x: rect.midX + rect.width * 0.3, y: rect.maxY))
        base.addLine(to: CGPoint(x: rect.midX - rect.width * 0.3, y: rect.maxY))
        base.closeSubpath()
        context.fill(base, with: .color(Color.appInk.opacity(online ? 0.4 : 0.26)))
    }

    /// "Off since 20:55", "Off since Mon", or "Never connected" when it has never connected.
    static func offline(_ devices: [HomeModel.Device]) -> String {
        let seen = devices.compactMap { $0.lastSeenAt.flatMap(DisplayTimestampParser.date(from:)) }.max()
        guard let seen else { return "Never connected" }
        let when = Calendar.current.isDateInToday(seen) ? seen.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) : seen.formatted(.dateTime.weekday(.wide))
        return "Off since \(when)"
    }
}
