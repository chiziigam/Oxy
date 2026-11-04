import SwiftUI

// MARK: - App icons
//
// Glyphs render as SF Symbols (Human Interface Guidelines: system symbols over hand-drawn
// icons), so they match the system's weight, optical sizing and accessibility. A key with no
// system equivalent falls back to its template asset under Assets.xcassets/ic-*.
// Tint with `.foregroundStyle`.

struct AppIcon: View {
    let name: String
    var size: CGFloat
    var weight: Font.Weight

    init(_ name: String, size: CGFloat = 16, weight: Font.Weight = .regular) {
        self.name = name
        self.size = size
        self.weight = weight
    }

    /// Convenience for migrating `Image(systemName:)` call sites — pass the old SF
    /// name and it resolves to the bundled asset. No SF Symbol is ever rendered.
    init(sf: String, size: CGFloat = 16, weight: Font.Weight = .regular) {
        self.init(AppGlyph.map(sf), size: size, weight: weight)
    }

    var body: some View {
        if let symbol = AppGlyph.systemSymbol(for: name) {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .fontWeight(weight)
                .frame(width: size, height: size)
        } else {
            Image("ic-\(name)")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }
}

enum AppGlyph {
    /// Bundled icon key → SF Symbol. Keys not listed keep their bundled asset.
    static func systemSymbol(for key: String) -> String? {
        let map: [String: String] = [
            "alert-circle": "exclamationmark.circle", "alert": "exclamationmark",
            "arrow-right": "arrow.right", "arrow-up-right": "arrow.up.right", "arrow-up": "arrow.up",
            "blinds": "blinds.horizontal.closed", "bolt": "bolt", "box": "shippingbox",
            "bulb": "lightbulb", "calendar": "calendar", "camera": "camera", "car": "car",
            "card": "creditcard", "chat": "bubble.left", "check-circle": "checkmark.circle",
            "check": "checkmark", "chevron-down": "chevron.down", "chevron-left": "chevron.backward",
            "chevron-right": "chevron.forward", "chevron-up": "chevron.up",
            "chevron-updown": "chevron.up.chevron.down", "clock": "clock", "cloud-rain": "cloud.rain",
            "cloud": "cloud", "cube": "cube", "display": "display", "doc": "doc", "dotted": "circle.dotted",
            "edit": "pencil", "envelope": "envelope", "fan": "fan", "history": "clock.arrow.circlepath",
            "list": "list.bullet", "location": "location", "map": "map", "menu": "line.3.horizontal",
            "mic": "mic", "minus": "minus", "moon": "moon", "person-check": "person.crop.circle.badge.checkmark",
            "person": "person", "phone": "phone", "photo": "photo", "pin": "mappin", "play": "play",
            "plus": "plus", "power": "power", "refresh": "arrow.clockwise", "search": "magnifyingglass",
            "shield-check": "checkmark.shield", "sparkles": "sparkles", "stop": "stop.fill", "sun": "sun.max",
            "thermometer": "thermometer.medium", "ticket": "ticket", "trash": "trash", "waveform": "waveform",
            "wifi-alert": "wifi.exclamationmark", "wifi-off": "wifi.slash", "xmark-circle": "xmark.circle.fill",
            "xmark": "xmark", "tab-chat": "bubble.left", "tab-home": "house", "tab-more": "ellipsis",
            "wheel-activity": "clock.arrow.circlepath", "wheel-home": "house", "wheel-memory": "brain",
            "wheel-settings": "gearshape", "wheel-today": "sun.max"
        ]
        return map[key]
    }

    /// Dynamic WeatherKit condition symbols → bundled weather icons.
    static func weather(_ sfName: String) -> String {
        let n = sfName.lowercased()
        if n.contains("rain") || n.contains("drizzle") || n.contains("storm") { return "cloud-rain" }
        if n.contains("snow") || n.contains("sleet") || n.contains("hail") { return "cloud-rain" }
        if n.contains("cloud") || n.contains("fog") || n.contains("haze") { return "cloud" }
        if n.contains("moon") || n.contains("night") || n.contains("stars") { return "moon" }
        return "sun"
    }

    /// Briefing/mission symbols (set as strings by HomeMissionBuilder) → icon keys.
    static func mission(_ sfName: String) -> String {
        switch sfName {
        case "bolt.fill": return "bolt"
        case "checkmark.circle.fill": return "check-circle"
        case "sparkles": return "sparkles"
        case "shippingbox.fill": return "box"
        case "calendar": return "calendar"
        case "envelope.fill": return "envelope"
        case "circle.dotted": return "dotted"
        default: return "sparkles"
        }
    }

    /// Full SF-name → bundled asset key map for migrating call sites. Strip the
    /// `.fill` variants to the same asset. Unknown names fall through to `mission`.
    static func map(_ sf: String) -> String {
        switch sf {
        case "chevron.right": return "chevron-right"
        case "chevron.left": return "chevron-left"
        case "chevron.down": return "chevron-down"
        case "chevron.up": return "chevron-up"
        case "chevron.up.chevron.down": return "chevron-updown"
        case "xmark": return "xmark"
        case "xmark.circle.fill", "xmark.circle": return "xmark-circle"
        case "plus": return "plus"
        case "checkmark": return "check"
        case "checkmark.circle.fill", "checkmark.circle": return "check-circle"
        case "exclamationmark": return "alert"
        case "exclamationmark.circle", "exclamationmark.circle.fill", "exclamationmark.triangle", "exclamationmark.triangle.fill": return "alert-circle"
        case "arrow.up.right": return "arrow-up-right"
        case "arrow.right", "arrow.right.circle.fill": return "arrow-right"
        case "arrow.up": return "arrow-up"
        case "arrow.clockwise", "arrow.triangle.2.circlepath": return "refresh"
        case "clock", "clock.fill": return "clock"
        case "clock.arrow.circlepath": return "history"
        case "square.and.pencil", "pencil": return "edit"
        case "magnifyingglass": return "search"
        case "wifi.slash": return "wifi-off"
        case "wifi.exclamationmark": return "wifi-alert"
        case "waveform": return "waveform"
        case "person.fill", "person", "person.crop.circle", "person.crop.circle.fill": return "person"
        case "person.crop.circle.badge.checkmark": return "person-check"
        case "line.3.horizontal", "line.horizontal.3": return "menu"
        case "car", "car.fill": return "car"
        case "list.bullet", "list.bullet.rectangle": return "list"
        case "map", "map.fill": return "map"
        case "ticket", "ticket.fill": return "ticket"
        case "trash", "trash.fill": return "trash"
        case "calendar": return "calendar"
        case "envelope", "envelope.fill": return "envelope"
        case "bubble.left", "bubble.left.fill", "message", "message.fill": return "chat"
        case "mic", "mic.fill": return "mic"
        case "location", "location.circle.fill", "location.fill": return "location"
        case "mappin", "mappin.circle.fill": return "pin"
        case "creditcard", "creditcard.fill": return "card"
        case "shippingbox", "shippingbox.fill": return "box"
        case "bolt", "bolt.fill": return "bolt"
        case "sparkles": return "sparkles"
        case "sun.max", "sun.max.fill": return "sun"
        case "cloud", "cloud.fill": return "cloud"
        case "photo", "photo.fill": return "photo"
        case "doc", "doc.fill", "doc.text", "doc.text.fill": return "doc"
        case "stop.fill", "stop": return "stop"
        default: return mission(sf)
        }
    }
}

// MARK: - Shared visual chrome

enum GlebChrome {
    static let ink = Color.appInk
    static let muted = Color.appMuted

    static var pastelBlob: some View {
        Color.appBackground
    }
}

// MARK: - Top chrome chips (weather + dual orbs + profile)
