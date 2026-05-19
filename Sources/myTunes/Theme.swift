import SwiftUI

enum Theme {
    static let navy = Color(red: 26/255, green: 50/255, blue: 99/255)
    static let slate = Color(red: 84/255, green: 119/255, blue: 146/255)
    static let amber = Color(red: 250/255, green: 185/255, blue: 91/255)
    static let cream = Color(red: 232/255, green: 226/255, blue: 219/255)
    static let coffee = Color(red: 78/255, green: 52/255, blue: 36/255)

    static let darkBg = Color(red: 10/255, green: 20/255, blue: 40/255)

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? amber : coffee
    }

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkBg : cream
    }

    static func panel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? navy.opacity(0.85) : Color.white.opacity(0.5)
    }

    static func barBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? navy : Color.white.opacity(0.7)
    }

    static func text(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? cream : navy
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        slate
    }

    static func hover(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : navy.opacity(0.08)
    }
}
