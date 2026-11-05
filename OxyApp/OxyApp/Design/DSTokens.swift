import SwiftUI
import UIKit

/// Design tokens. The values come from `DESIGN.md`; change them there first.

enum DSKey {
    static let theme = "ds_theme"
    static let accent = "ds_accent"
    static let haptics = "ds_haptics"
}

enum DSTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

}

/// The person's appearance choices. Observable, so every screen restyles at once without being rebuilt.
@Observable
final class DSAppearance {
    static let shared = DSAppearance()

    var theme: DSTheme
    var accent: DSAccent
    var haptics: Bool

    private init() {
        let defaults = UserDefaults.standard
        theme = DSTheme(rawValue: defaults.string(forKey: DSKey.theme) ?? "") ?? .system
        accent = DSAccent(rawValue: defaults.string(forKey: DSKey.accent) ?? "") ?? .graphite
        haptics = defaults.object(forKey: DSKey.haptics) as? Bool ?? true
    }

    func choose(theme: DSTheme) {
        self.theme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: DSKey.theme)
    }

    func choose(accent: DSAccent) {
        self.accent = accent
        UserDefaults.standard.set(accent.rawValue, forKey: DSKey.accent)
    }

    func setHaptics(_ on: Bool) {
        haptics = on
        UserDefaults.standard.set(on, forKey: DSKey.haptics)
    }
}

enum DSAccent: String, CaseIterable, Identifiable {
    case graphite, blue, green, orange, teal, rose

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var light: UInt32 {
        switch self {
        case .graphite: return 0x1a1b1e
        case .blue: return 0x2f6fed
        case .green: return 0x1f8a5b
        case .orange: return 0xd9702a
        case .teal: return 0x17858f
        case .rose: return 0xc6475f
        }
    }

    var dark: UInt32 {
        switch self {
        case .graphite: return 0xeceef0
        case .blue: return 0x6b95ff
        case .green: return 0x45b887
        case .orange: return 0xf08a46
        case .teal: return 0x3fb3be
        case .rose: return 0xee7289
        }
    }

    /// Text colour on top of the accent in dark mode. In light mode it is always white.
    var darkInk: UInt32 {
        switch self {
        case .graphite: return 0x111213
        case .blue: return 0x0a1020
        case .green: return 0x06150f
        case .orange: return 0x1a0d03
        case .teal: return 0x04161a
        case .rose: return 0x1c060b
        }
    }

    static var current: DSAccent { DSAppearance.shared.accent }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

enum DS {
    static func color(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    static let bg = color(light: 0xf5f5f6, dark: 0x0d0e10)
    static let card = color(light: 0xffffff, dark: 0x17181b)
    static let fill = color(light: 0xf5f5f6, dark: 0x0d0e10)
    static let ink = color(light: 0x111213, dark: 0xf2f3f4)
    static let muted = color(light: 0x6b6f76, dark: 0x8d9199)
    static let line = color(light: 0xe4e5e8, dark: 0x26282c)
    static let warn = color(light: 0xb45309, dark: 0xf0a23b)
    static let danger = color(light: 0xc2362f, dark: 0xf06a62)

    static var accent: Color {
        let a = DSAccent.current
        return color(light: a.light, dark: a.dark)
    }

    static var accentInk: Color {
        let a = DSAccent.current
        return color(light: 0xffffff, dark: a.darkInk)
    }

    enum Radius {
        static let card: CGFloat = 18
        static let item: CGFloat = 12
        static let button: CGFloat = 12
        static let small: CGFloat = 9
    }

    enum Space {
        static let edge: CGFloat = 16
        static let rowGap: CGFloat = 6
    }
}

extension Font {
    /// The one place the typeface is chosen: Geist, in the three weights the design uses.
    /// Sizes scale with the person's text size setting.
    static func ds(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = "Geist-SemiBold"
        case .medium: name = "Geist-Medium"
        default: name = "Geist-Regular"
        }
        return .custom(name, size: size)
    }
}
