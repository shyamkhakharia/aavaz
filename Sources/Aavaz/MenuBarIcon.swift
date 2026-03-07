import AppKit

/// Draws the Aavaz logo — a stylized "A" with sound wave arcs — for the menubar.
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 18)

    /// Idle: template image (macOS handles light/dark tinting).
    static func idle() -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            drawA(in: rect)
            drawWaves(in: rect, color: .black, phase: 1.0)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Recording: red logo.
    static func recording() -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let color = NSColor.systemRed
            color.setStroke()
            drawA(in: rect)
            drawWaves(in: rect, color: color, phase: 1.0)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Transcribing animation: pulsing orange waves. `frame` cycles 0..<frameCount
    static let frameCount = 4

    static func transcribing(frame: Int) -> NSImage {
        let phases: [CGFloat] = [0.3, 0.6, 1.0, 0.6]
        let phase = phases[frame % phases.count]
        let color = NSColor.systemOrange

        let image = NSImage(size: size, flipped: false) { rect in
            color.setStroke()
            drawA(in: rect)
            drawWaves(in: rect, color: color, phase: phase)
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Drawing

    private static func drawA(in rect: NSRect) {
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        // "A" — offset left to make room for waves
        let apex = NSPoint(x: 7, y: rect.maxY - 2.5)
        let leftFoot = NSPoint(x: 3.5, y: rect.minY + 2.5)
        let rightFoot = NSPoint(x: 10.5, y: rect.minY + 2.5)

        path.move(to: leftFoot)
        path.line(to: apex)
        path.line(to: rightFoot)

        // Crossbar
        let crossY: CGFloat = rect.minY + 5.5
        path.move(to: NSPoint(x: 5.0, y: crossY))
        path.line(to: NSPoint(x: 9.0, y: crossY))

        path.stroke()
    }

    private static func drawWaves(in rect: NSRect, color: NSColor, phase: CGFloat) {
        let cy = rect.midY

        // Inner arc
        let wave1 = NSBezierPath()
        wave1.lineWidth = 1.3
        wave1.lineCapStyle = .round
        let x1: CGFloat = 12.0
        wave1.move(to: NSPoint(x: x1, y: cy - 3.0 * phase))
        wave1.curve(to: NSPoint(x: x1, y: cy + 3.0 * phase),
                     controlPoint1: NSPoint(x: x1 + 2.5 * phase, y: cy - 1.5 * phase),
                     controlPoint2: NSPoint(x: x1 + 2.5 * phase, y: cy + 1.5 * phase))
        color.setStroke()
        wave1.stroke()

        // Outer arc — fades in with phase
        guard phase > 0.4 else { return }
        let outerAlpha = (phase - 0.3) / 0.7 * 0.6
        let wave2 = NSBezierPath()
        wave2.lineWidth = 1.1
        wave2.lineCapStyle = .round
        let x2: CGFloat = 14.5
        wave2.move(to: NSPoint(x: x2, y: cy - 4.5 * phase))
        wave2.curve(to: NSPoint(x: x2, y: cy + 4.5 * phase),
                     controlPoint1: NSPoint(x: x2 + 3.0 * phase, y: cy - 2.5 * phase),
                     controlPoint2: NSPoint(x: x2 + 3.0 * phase, y: cy + 2.5 * phase))
        color.withAlphaComponent(outerAlpha).setStroke()
        wave2.stroke()
    }
}
