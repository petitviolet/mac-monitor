import AppKit
import SwiftUI

/// ダークの値は、同じ色相からダークの背景に合う段を選んだもの。
enum VizPalette {
    static let surface = dynamic(light: 0xFCFCFB, dark: 0x1A1A19)
    static let accent = dynamic(light: 0x2A78D6, dark: 0x3987E5)
    static let track = dynamic(light: 0xCDE2FB, dark: 0x184F95)
    static let memoryApp = accent
    static let memoryWired = dynamic(light: 0xEB6834, dark: 0xD95926)
    static let memoryCompressed = dynamic(light: 0x1BAF7A, dark: 0x199E70)
    /// 空きは合計の残りを示す領域なので、無彩色にする。
    static let memoryFree = dynamic(light: 0xE1E0D9, dark: 0x383835)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return nsColor(hex: isDark ? dark : light)
        })
    }

    private static func nsColor(hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
