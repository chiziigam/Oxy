import SwiftUI
import UIKit

extension Color {
    // Legacy aliases. Every `oxy*` name forwards to the one palette in AppTheme.swift, so an old
    // call site can never introduce a second set of colours. New code uses the `app*` roles.
    static var oxyBg: Color { .appBackground }
    static var oxySurface1: Color { .appSurface }
    static var oxySurface2: Color { .appSurface }
    static var oxySurface3: Color { .appSurface2 }
    static var oxySurface4: Color { .appSurface2 }
    static var oxyLine: Color { .appHairline }
    static var oxyLine2: Color { .appHairline }
    static var oxyText: Color { .appInk }
    static var oxySub: Color { .appMuted }
    static var oxyDim: Color { .appMuted }
    static var oxyOnAccent: Color { .appOnAccent }
    static var oxyDefaultStone: Color { .appSurface2 }
    static var oxyStone: Color { .appAccent }
    static var oxyAccent: Color { .appAccent }
    static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    static var oxyGreen: Color { .appSuccess }
    static var oxyRed: Color { .appDanger }
}

#if !DEBUG
/// Release builds log nothing: diagnostic prints include message text and device identifiers.
@inline(__always)
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {}
#endif
