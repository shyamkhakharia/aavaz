import AppKit

/// Menubar icon states using SF Symbols.
/// Idle: waveform (template).
/// Recording: waveform bouncing gently in brand accent color.
/// Transcribing: spinning progress indicator.
enum MenuBarIcon {
    /// Brand accent color matching the website (#6E6AE8).
    static let accentColor = NSColor(red: 0x6E / 255.0, green: 0x6A / 255.0, blue: 0xE8 / 255.0, alpha: 1.0)

    static func idle() -> NSImage {
        let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Aavaz")!
        image.isTemplate = true
        return image
    }

    // MARK: - Recording (bouncing waveform in accent color)

    private static let bounceOffsets: [CGFloat] = [0, -1.5, -2.5, -1.5, 0, 1.5, 2.5, 1.5]
    static let recordingFrameCount = bounceOffsets.count

    static func recording(frame: Int) -> NSImage {
        let offset = bounceOffsets[frame % bounceOffsets.count]

        guard let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Recording") else {
            return idle()
        }

        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let configured = symbol.withSymbolConfiguration(config) ?? symbol
        let symSize = configured.size

        let canvasSize = NSSize(width: symSize.width, height: symSize.height + 6)
        let image = NSImage(size: canvasSize, flipped: false) { rect in
            let x = (rect.width - symSize.width) / 2
            let y = (rect.height - symSize.height) / 2 + offset

            accentColor.set()
            configured.draw(in: NSRect(x: x, y: y, width: symSize.width, height: symSize.height),
                           from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Transcribing (spinning progress)

    private static let spinnerAngles: [CGFloat] = [0, 45, 90, 135, 180, 225, 270, 315]
    static let transcribingFrameCount = spinnerAngles.count

    static func transcribing(frame: Int) -> NSImage {
        let angle = spinnerAngles[frame % spinnerAngles.count]
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

                // Fade: the "leading" dot is brightest
                let alpha = CGFloat(dotCount - i) / CGFloat(dotCount)
                accentColor.withAlphaComponent(alpha * 0.9 + 0.1).setFill()

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
