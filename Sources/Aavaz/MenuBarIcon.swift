import AppKit

/// Menubar icon states.
/// Idle: SF Symbol waveform (template).
/// Recording: animated thin waveform bars matching the SF Symbol weight.
/// Transcribing: circular dot spinner.
/// Error: dimmed waveform with a small warning dot.
enum MenuBarIcon {
    /// Brand accent color matching the website (#6E6AE8).
    static let accentColor = NSColor(red: 0x6E / 255.0, green: 0x6A / 255.0, blue: 0xE8 / 255.0, alpha: 1.0)

    static func idle() -> NSImage {
        let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Aavaz")!
        image.isTemplate = true
        return image
    }

    /// Dimmed waveform with a small amber dot in the bottom-right corner.
    /// Subtle — doesn't scream error, just signals "needs attention".
    static func error() -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Dimmed waveform
            if let sym = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                let configured = sym.withSymbolConfiguration(config) ?? sym
                let symSize = configured.size
                let x = (rect.width - symSize.width) / 2 - 1
                let y = (rect.height - symSize.height) / 2
                configured.draw(in: NSRect(x: x, y: y, width: symSize.width, height: symSize.height),
                               from: .zero, operation: .sourceOver, fraction: 0.25)
            }

            // Small amber warning dot — bottom right
            let dotSize: CGFloat = 5.0
            let dotRect = NSRect(
                x: rect.maxX - dotSize - 1.5,
                y: rect.minY + 2.0,
                width: dotSize, height: dotSize
            )
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Recording (thin waveform bars to match SF Symbol weight)

    private static let barCount = 7
    private static let barPatterns: [[CGFloat]] = [
        [0.25, 0.50, 0.80, 1.00, 0.70, 0.40, 0.20],
        [0.40, 0.70, 0.55, 0.85, 1.00, 0.60, 0.30],
        [0.30, 0.90, 0.70, 0.50, 0.80, 1.00, 0.45],
        [0.50, 0.40, 1.00, 0.70, 0.55, 0.75, 0.60],
        [0.60, 0.80, 0.45, 0.90, 0.65, 0.35, 0.85],
        [0.35, 0.65, 0.90, 0.40, 1.00, 0.55, 0.50],
        [0.70, 0.35, 0.60, 0.80, 0.45, 0.90, 0.40],
        [0.45, 0.55, 0.75, 0.60, 0.35, 0.80, 0.70],
    ]
    static let recordingFrameCount = barPatterns.count

    static func recording(frame: Int) -> NSImage {
        let pattern = barPatterns[frame % barPatterns.count]
        let size = NSSize(width: 18, height: 18)

        let image = NSImage(size: size, flipped: false) { rect in
            let barWidth: CGFloat = 1.2       // thin like SF Symbol strokes
            let gap: CGFloat = 1.2
            let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
            let startX = (rect.width - totalWidth) / 2
            let maxHeight: CGFloat = 12.0
            let baseY = (rect.height - maxHeight) / 2

            accentColor.setFill()

            for i in 0..<barCount {
                let height = max(2.0, pattern[i] * maxHeight)
                let x = startX + CGFloat(i) * (barWidth + gap)
                let y = baseY + (maxHeight - height) / 2
                let barRect = NSRect(x: x, y: y, width: barWidth, height: height)
                NSBezierPath(roundedRect: barRect, xRadius: 0.6, yRadius: 0.6).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Transcribing (spinning dots)

    static let transcribingFrameCount = 8

    static func transcribing(frame: Int) -> NSImage {
        let angle = CGFloat(frame % transcribingFrameCount) * (360.0 / CGFloat(transcribingFrameCount))
        let size = NSSize(width: 18, height: 18)

        let image = NSImage(size: size, flipped: false) { rect in
            let cx = rect.midX
            let cy = rect.midY
            let radius: CGFloat = 5.5
            let dotCount = 8

            for i in 0..<dotCount {
                let dotAngle = CGFloat(i) * (360.0 / CGFloat(dotCount)) + angle
                let rad = dotAngle * .pi / 180.0
                let x = cx + radius * cos(rad)
                let y = cy + radius * sin(rad)

                let alpha = CGFloat(dotCount - i) / CGFloat(dotCount)
                accentColor.withAlphaComponent(alpha * 0.85 + 0.15).setFill()

                let dotSize: CGFloat = i == 0 ? 2.5 : 2.0
                let dotRect = NSRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                NSBezierPath(ovalIn: dotRect).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
