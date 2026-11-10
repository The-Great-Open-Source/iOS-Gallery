import SwiftUI
import UIKit

/// Design tokens for Good Gallery: "Dark Editorial Luxury + Native Apple Minimalism".
enum GG {
    enum Palette {
        static let background    = Color(light: 0xF6F2EA, dark: 0x101010)
        static let surface       = Color(light: 0xEDE7DC, dark: 0x191919)
        static let elevated      = Color(light: 0xFFFFFF, dark: 0x22211F)
        static let accent        = Color(light: 0x9A7547, dark: 0xD6B48D)
        static let text          = Color(light: 0x1B1A18, dark: 0xF5F0E8)
        static let secondaryText = Color(light: 0x6B655E, dark: 0xA7A19A)
        static let separator     = Color(light: 0xD9D2C6, dark: 0x33312E)
        /// Text/icons that sit on top of the accent colour.
        static let onAccent      = Color(hex: 0x16120D)
    }

    enum Radius {
        static let card: CGFloat = 20
        static let tile: CGFloat = 8
        static let control: CGFloat = 14
    }

    enum Spacing {
        static let page: CGFloat = 20
        static let grid: CGFloat = 2
    }

    enum Typography {
        /// Elegant serif for branding and editorial headings only.
        static func editorial(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }
        static let caption = Font.system(.caption, design: .default)
        static let eyebrow = Font.system(size: 11, weight: .semibold).smallCaps()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// User-selectable appearance. Dark is the default for the initial release.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "System"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

enum Haptics {
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
