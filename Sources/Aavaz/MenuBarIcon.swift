import AppKit

/// Menubar icon states.
/// Idle: SF Symbol waveform (template).
/// Recording: animated audio level bars in accent color.
/// Transcribing: circular dot spinner in accent color.
enum MenuBarIcon {
    /// Brand accent color matching the website (#6E6AE8).
    static let accentColor = NSColor(red: 0x6E / 255.0, green: 0x6A / 255.0, blue: 0xE8 / 255.0, alpha: 1.0)

    static func idle() -> NSImage {
        let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Aavaz")!
        image.isTemplate = true
        return image
    }

    // MARK: - Recording (animated audio level bars)

    /// Number of vertical bars in the visualizer.
    private static let barCount = 5
    /// Pre-computed bar height patterns (each is an array of heights for the bars).
    private static let barPatterns: [[CGFloat]] = [
        [0.3, 0.7, 1.0, 0.5, 0.2],
        [0.5, 0.9, 0.6, 0.8, 0.4],
        [0.8, 0.4, 0.7, 1.0, 0.6],
        [0.6, 0.6, 0.9, 0.3, 0.9],
        [0.4, 1.0, 0.5, 0.7, 0.3],
        [0.7, 0.3, 0.8, 0.6, 0.7],
        [0.9, 0.8, 0.3, 0.9, 0.5],
        [0.3, 0.5, 1.0, 0.4, 0.8],
    ]
    static let recordingFrameCount = barPatterns.count

    static func recording(frame: Int) -> NSImage {
        let pattern = barPatterns[frame % barPatterns.count]
        let size = NSSize(width: 18, height: 18)

        let image = NSImage(size: size, flipped: false) { rect in
            let barWidth: CGFloat = 2.0
            let gap: CGFloat = 1.5
            let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
            let startX = (rect.width - totalWidth) / 2
            let maxHeight: CGFloat = 12.0
            let baseY = (rect.height - maxHeight) / 2

            accentColor.setFill()

            for i in 0..<barCount {
                let height = max(2.5, pattern[i] * maxHeight)
                let x = startX + CGFloat(i) * (barWidth + gap)
                let y = baseY + (maxHeight - height) / 2  // center vertically
                let barRect = NSRect(x: x, y: y, width: barWidth, height: height)
                NSBezierPath(roundedRect: barRect, xRadius: 1.0, yRadius: 1.0).fill()
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
