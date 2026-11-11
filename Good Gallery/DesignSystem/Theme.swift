import SwiftUI
import UIKit

/// Design tokens for Good Gallery: "Dark Editorial Luxury + Native Apple Minimalism".
enum GG {
    enum Palette {
        static let background    = Color(uiColor: .systemBackground)
        static let surface       = Color(uiColor: .secondarySystemBackground)
        static let elevated      = Color(uiColor: .tertiarySystemBackground)
        static let grouped       = Color(uiColor: .systemGroupedBackground)
        static let accent        = Color(light: 0x0A66E0, dark: 0x4DA3FF)
        static let text          = Color.primary
        static let secondaryText = Color.secondary
        static let separator     = Color(uiColor: .separator)
        /// Text/icons that sit on top of the accent colour.
        static let onAccent      = Color(hex: 0xFFFFFF)
    }

    enum Radius {
        static let card: CGFloat = 14
        static let tile: CGFloat = 8
        static let control: CGFloat = 14
    }

    enum Spacing {
        static let page: CGFloat = 20
        static let grid: CGFloat = 2
    }

    enum Typography {
        /// Standard system heading (SF Pro). Kept as one helper so sizes stay consistent.
        static func heading(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight)
        }
        static let eyebrow = Font.footnote.weight(.semibold)
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
    case system, dark, light
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
