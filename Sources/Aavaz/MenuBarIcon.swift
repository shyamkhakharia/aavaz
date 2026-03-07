import AppKit

/// Draws the Aavaz menubar icon — the Devanagari आ rendered from a
/// proper system font, with sound wave arcs for active states.
enum MenuBarIcon {
    static let size = NSSize(width: 20, height: 18)

    /// Brand accent color matching the website (#6E6AE8).
    static let accentColor = NSColor(red: 0x6E / 255.0, green: 0x6A / 255.0, blue: 0xE8 / 255.0, alpha: 1.0)

    static func idle() -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            drawAa(in: rect, color: .black)
            return true
        }
        image.isTemplate = true
        return image
    }

    static func recording() -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            drawAa(in: rect, color: accentColor)
            drawWaves(in: rect, color: accentColor, phase: 1.0)
            return true
        }
        image.isTemplate = false
        return image
    }

    static let frameCount = 4

    static func transcribing(frame: Int) -> NSImage {
        let phases: [CGFloat] = [0.3, 0.6, 1.0, 0.6]
        let phase = phases[frame % phases.count]

        let image = NSImage(size: size, flipped: false) { rect in
            drawAa(in: rect, color: .systemOrange)
            drawWaves(in: rect, color: .systemOrange, phase: phase)
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Drawing

    private static func drawAa(in rect: NSRect, color: NSColor) {
        let fontSize: CGFloat = 15.0
        let font = NSFont(name: "DevanagariSangamMN-Bold", size: fontSize)
            ?? NSFont(name: "DevanagariSangamMN", size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]

        let str = NSAttributedString(string: "आ", attributes: attrs)
        let textSize = str.size()

        // Position: left-aligned with some padding, leave right side for waves
        let x = max(0, (rect.width - 6 - textSize.width) / 2.0)
        let y = (rect.height - textSize.height) / 2.0

        str.draw(at: NSPoint(x: x, y: y))
    }

    private static func drawWaves(in rect: NSRect, color: NSColor, phase: CGFloat) {
        let cy = rect.midY
        let baseX = rect.width - 5.5

        let wave1 = NSBezierPath()
        wave1.lineWidth = 1.2
        wave1.lineCapStyle = .round
        wave1.move(to: NSPoint(x: baseX, y: cy - 2.5 * phase))
        wave1.curve(
            to: NSPoint(x: baseX, y: cy + 2.5 * phase),
            controlPoint1: NSPoint(x: baseX + 2.0 * phase, y: cy - 1.2 * phase),
            controlPoint2: NSPoint(x: baseX + 2.0 * phase, y: cy + 1.2 * phase)
        )
        color.setStroke()
        wave1.stroke()

        guard phase > 0.4 else { return }
        let outerAlpha = (phase - 0.3) / 0.7 * 0.5
        let wave2 = NSBezierPath()
        wave2.lineWidth = 1.0
        wave2.lineCapStyle = .round
        let x2 = baseX + 2.0
        wave2.move(to: NSPoint(x: x2, y: cy - 3.8 * phase))
        wave2.curve(
            to: NSPoint(x: x2, y: cy + 3.8 * phase),
            controlPoint1: NSPoint(x: x2 + 2.5 * phase, y: cy - 2.0 * phase),
            controlPoint2: NSPoint(x: x2 + 2.5 * phase, y: cy + 2.0 * phase)
        )
        color.withAlphaComponent(outerAlpha).setStroke()
        wave2.stroke()
    }
}
