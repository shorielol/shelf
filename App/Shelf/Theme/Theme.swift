import AppKit
import CoreText
import SwiftUI

/// Design tokens. Warm analog hardware under liquid glass: graphite neutrals, one ember accent, brass details.
nonisolated enum Theme {
    static let graphite = Color(red: 0.110, green: 0.106, blue: 0.098)       // #1C1B19
    static let graphiteRaised = Color(red: 0.165, green: 0.157, blue: 0.145) // #2A2825
    static let cream = Color(red: 0.957, green: 0.937, blue: 0.902)          // #F4EFE6
    static let ember = Color(red: 0.910, green: 0.380, blue: 0.227)          // #E8613A
    static let brass = Color(red: 0.851, green: 0.647, blue: 0.357)          // #D9A55B
    static let moss = Color(red: 0.443, green: 0.592, blue: 0.424)           // #71976C

    static let textPrimary = Color.white.opacity(0.96)
    static let textSecondary = Color.white.opacity(0.64)
    static let textTertiary = Color.white.opacity(0.42)
    static let hairline = Color.white.opacity(0.12)

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        /// Matches the system widget corner radius.
        static let widget: CGFloat = 22
        static let card: CGFloat = 14
        static let control: CGFloat = 10
    }

    enum Motion {
        static let standard = Animation.spring(response: 0.35, dampingFraction: 1.0)
        static let lively = Animation.spring(response: 0.32, dampingFraction: 0.78)
        static let press = Animation.spring(response: 0.18, dampingFraction: 1.0)
        static let lift = Animation.spring(response: 0.28, dampingFraction: 0.7)
        static let fade = Animation.easeOut(duration: 0.22)
    }

    enum Typeface {
        /// New York for display headings.
        static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .serif) }
        static func numeral(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .rounded).monospacedDigit() }
        static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
        static let body = Font.system(size: 13)
        static let caption = Font.system(size: 11, weight: .medium)
        static let eyebrow = Font.system(size: 10, weight: .bold).width(.expanded)
        /// Departure Mono, for the click-wheel LCD.
        static func pixel(_ size: CGFloat) -> Font { .custom("Departure Mono", fixedSize: size) }
    }

    /// Registers bundled fonts once at launch.
    static func registerFonts() {
        guard let url = Bundle.main.url(forResource: "DepartureMono-Regular", withExtension: "otf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension View {
    func displayTracking(_ size: CGFloat) -> some View {
        tracking(size >= 28 ? -size * 0.02 : 0)
    }
}
