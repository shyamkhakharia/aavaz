import AppKit

/// Shared design tokens matching the website's CSS variables.
/// Keeps the app and site visually cohesive.
enum DesignTokens {
    // MARK: - Colors

    static let accent = NSColor(red: 0x6E / 255.0, green: 0x6A / 255.0, blue: 0xE8 / 255.0, alpha: 1.0)
    static let accentLight = NSColor(red: 0x8B / 255.0, green: 0x88 / 255.0, blue: 0xEF / 255.0, alpha: 1.0)

    static let bg = NSColor(red: 0x0A / 255.0, green: 0x0A / 255.0, blue: 0x0B / 255.0, alpha: 1.0)
    static let bgCard = NSColor(red: 0x11 / 255.0, green: 0x11 / 255.0, blue: 0x13 / 255.0, alpha: 1.0)
    static let bgCardHover = NSColor(red: 0x18 / 255.0, green: 0x18 / 255.0, blue: 0x1B / 255.0, alpha: 1.0)

    static let text = NSColor(red: 0xED / 255.0, green: 0xED / 255.0, blue: 0xEF / 255.0, alpha: 1.0)
    static let textSecondary = NSColor(red: 0x8B / 255.0, green: 0x8B / 255.0, blue: 0x8E / 255.0, alpha: 1.0)
    static let textTertiary = NSColor(red: 0x56 / 255.0, green: 0x56 / 255.0, blue: 0x5A / 255.0, alpha: 1.0)

    static let border = NSColor(white: 1.0, alpha: 0.06)
    static let borderHover = NSColor(white: 1.0, alpha: 0.10)

    // MARK: - Radii

    static let radiusLarge: CGFloat = 16
    static let radiusSmall: CGFloat = 10

    // MARK: - Fonts

    static func heading(size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    static func body(size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .regular)
    }

    static func label(size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .medium)
    }
}
