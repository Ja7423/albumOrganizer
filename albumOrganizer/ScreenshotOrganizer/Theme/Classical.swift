import SwiftUI
import UIKit

/// Classical design-system tokens, ported from `project/_ds/classical-…/styles.css`.
/// The system is light-only; the app forces the light color scheme.
enum Palette {
    static let bg = Color(hex: 0xF3F2F2)
    static let surface = Color(hex: 0xEAE9E9)
    static let text = Color(hex: 0x201F1D)
    static let accent = Color(hex: 0xB68235)
    /// `color-mix(in srgb, #201f1d 16%, transparent)`
    static let divider = Color(hex: 0x201F1D).opacity(0.16)

    static let neutral100 = Color(hex: 0xF8F4F4)
    static let neutral200 = Color(hex: 0xEAE7E7)
    static let neutral300 = Color(hex: 0xD7D3D3)
    static let neutral400 = Color(hex: 0xBAB6B6)
    static let neutral500 = Color(hex: 0x9B9797)
    static let neutral600 = Color(hex: 0x7D7979)
    static let neutral700 = Color(hex: 0x605D5D)
    static let neutral800 = Color(hex: 0x444141)
    static let neutral900 = Color(hex: 0x2D2B2B)

    static let accent100 = Color(hex: 0xFFF3E4)
    static let accent200 = Color(hex: 0xFFE3BF)
    static let accent300 = Color(hex: 0xFACB8D)
    static let accent400 = Color(hex: 0xE1AD66)
    static let accent500 = Color(hex: 0xC28D41)
    static let accent600 = Color(hex: 0xA06F24)
    static let accent700 = Color(hex: 0x7D5411)
    static let accent800 = Color(hex: 0x5A3B0A)
    static let accent900 = Color(hex: 0x3A270D)
}

/// `--space-*`: density 1.15× is baked in.
enum Space {
    static let s1: CGFloat = 4.6
    static let s2: CGFloat = 9.2
    static let s3: CGFloat = 13.8
    static let s4: CGFloat = 18.4
    static let s6: CGFloat = 27.6
    static let s8: CGFloat = 36.8
}

enum Radius {
    static let sm: CGFloat = 2
    static let md: CGFloat = 4
    static let lg: CGFloat = 7
}

enum Shadow {
    /// `--shadow-md`: 0 3px 10px ink 16%
    static let mdColor = Palette.neutral900.opacity(0.16)
    /// `--shadow-lg`: 0 12px 32px ink 22%
    static let lgColor = Palette.neutral900.opacity(0.22)
}

extension View {
    func shadowMD() -> some View { shadow(color: Shadow.mdColor, radius: 5, x: 0, y: 3) }
    func shadowLG() -> some View { shadow(color: Shadow.lgColor, radius: 16, x: 0, y: 12) }
}

/// The design pairs Cormorant Garamond (headings) and Lora (body) with Noto Serif TC
/// for Chinese. Each Latin face cascades to Noto Serif TC so mixed text stays serif.
enum Typeface {
    enum Weight { case regular, semibold }

    /// `--app-head`: Cormorant Garamond semibold over Noto Serif TC.
    static func head(_ size: CGFloat, _ weight: Weight = .semibold) -> Font {
        font(latin: weight == .semibold ? "CormorantGaramond-SemiBold" : "CormorantGaramond-Regular", weight: weight, size: size)
    }

    /// `--app-font`: Lora over Noto Serif TC.
    static func body(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        font(latin: weight == .semibold ? "Lora-SemiBold" : "Lora-Regular", weight: weight, size: size)
    }

    /// Recognized text renders in the system face, as in the prototype.
    static func system(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func uiBody(_ size: CGFloat, _ weight: Weight = .regular) -> UIFont {
        uiFont(latin: weight == .semibold ? "Lora-SemiBold" : "Lora-Regular", weight: weight, size: size)
    }

    private static func font(latin: String, weight: Weight, size: CGFloat) -> Font {
        Font(uiFont(latin: latin, weight: weight, size: size) as CTFont)
    }

    private static func uiFont(latin: String, weight: Weight, size: CGFloat) -> UIFont {
        let cjk = weight == .semibold ? "NotoSerifTC-SemiBold" : "NotoSerifTC-Regular"
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: latin,
            .cascadeList: [UIFontDescriptor(fontAttributes: [.name: cjk])]
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
