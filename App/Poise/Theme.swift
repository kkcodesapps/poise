import SwiftUI
import UIKit

/// Design tokens. Names mirror the design file's variables (`Color.bg.base`, `Spacing.s16`, …).
enum Theme {
    enum Bg {
        static let base = dynamic(light: 0xFAF9F7, dark: 0x121110)
        static let elevated = dynamic(light: 0xFFFFFF, dark: 0x1A1918)
        static let subtle = dynamic(light: 0xF3F2EF, dark: 0x222120)
        static let inset = dynamic(light: 0xE9E7E2, dark: 0x0B0B0A)
        static let bar = base
    }
    enum Border {
        static let subtle = Color.primary.opacity(0.06)
        static let `default` = Color.primary.opacity(0.10)
        static let strong = Color.primary.opacity(0.16)
    }
    enum Text {
        static let primary = dynamic(light: 0x1A1918, dark: 0xF3F2EF)
        static let secondary = dynamic(light: 0x6E6B64, dark: 0xB7B4AC)
        static let tertiary = dynamic(light: 0x918E86, dark: 0x918E86)
        static let onAccent = Color.white
    }
    enum Accent {
        static let `default` = dynamic(light: 0x5468E6, dark: 0x8C9BFF)
        static let subtle = dynamic(light: 0x6E82FF, dark: 0x6E82FF).opacity(0.14)
    }
    enum Status {
        static let good = dynamic(light: 0x2DAA7B, dark: 0x5EE3B0)
        static let goodBg = Color(hex: 0x3FCF98).opacity(0.14)
        static let track = dynamic(light: 0xC9871A, dark: 0xF7C25C)
        static let trackBg = Color(hex: 0xEFA72E).opacity(0.14)
        static let heads = dynamic(light: 0xCC4E42, dark: 0xFF8A7A)
        static let headsBg = Color(hex: 0xF2685A).opacity(0.14)
    }
    enum Money {
        static let `in` = Status.good
        static let pending = Text.tertiary
    }

    enum Spacing {
        static let s4: CGFloat = 4, s8: CGFloat = 8, s12: CGFloat = 12, s16: CGFloat = 16, s20: CGFloat = 20, s24: CGFloat = 24, s32: CGFloat = 32
    }
    enum Radius {
        static let sm: CGFloat = 8, md: CGFloat = 12, lg: CGFloat = 16, xl: CGFloat = 20, xxl: CGFloat = 28
    }

    /// Type ramp. Money numbers use the rounded design.
    enum Font {
        static let displayLG = SwiftUI.Font.system(size: 34, weight: .bold)
        static let titleLG = SwiftUI.Font.system(size: 28, weight: .bold)
        static let titleMD = SwiftUI.Font.system(size: 22, weight: .semibold)
        static let titleSM = SwiftUI.Font.system(size: 20, weight: .semibold)
        static let verdictLG = SwiftUI.Font.system(size: 26, weight: .semibold)
        static let verdictMD = SwiftUI.Font.system(size: 17, weight: .regular)
        static let headline = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 17)
        static let subhead = SwiftUI.Font.system(size: 15)
        static let subheadStrong = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let footnote = SwiftUI.Font.system(size: 13)
        static let caption = SwiftUI.Font.system(size: 12)
        static let captionStrong = SwiftUI.Font.system(size: 12, weight: .medium)
        static let caption2Strong = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let moneyXL = SwiftUI.Font.system(size: 44, weight: .semibold, design: .rounded)
        static let moneyLG = SwiftUI.Font.system(size: 28, weight: .semibold, design: .rounded)
        static let moneyMD = SwiftUI.Font.system(size: 17, weight: .semibold, design: .rounded)
        static let moneySM = SwiftUI.Font.system(size: 15, weight: .medium, design: .rounded)
        static let moneyXS = SwiftUI.Font.system(size: 13, weight: .medium, design: .rounded)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hex: UInt32) { self.init(UIColor(hex: hex)) }
}
