import AppKit

/// Menubar icon states using SF Symbols.
/// Idle: waveform — clean audio identity.
/// Recording: waveform.badge.mic — mic badge signals "listening".
/// Transcribing: waveform bouncing up and down.
enum MenuBarIcon {
    /// Brand accent color matching the website (#6E6AE8).
    static let accentColor = NSColor(red: 0x6E / 255.0, green: 0x6A / 255.0, blue: 0xE8 / 255.0, alpha: 1.0)

    static func idle() -> NSImage {
        let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Aavaz")!
        image.isTemplate = true
        return image
    }

    static func recording() -> NSImage {
        let image = NSImage(systemSymbolName: "waveform.badge.mic", accessibilityDescription: "Recording")!
        image.isTemplate = false
        return image
    }

    // Bounce offsets: gentle up-down motion (in points)
    private static let bounceOffsets: [CGFloat] = [0, -1.5, -2.5, -1.5, 0, 1.5, 2.5, 1.5]
    static let frameCount = bounceOffsets.count

    static func transcribing(frame: Int) -> NSImage {
        let offset = bounceOffsets[frame % bounceOffsets.count]

        guard let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Transcribing") else {
            return idle()
        }

        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let configured = symbol.withSymbolConfiguration(config) ?? symbol
        let symSize = configured.size

        // Create a canvas with extra vertical room for the bounce
        let canvasSize = NSSize(width: symSize.width, height: symSize.height + 6)
        let image = NSImage(size: canvasSize, flipped: false) { rect in
            let x = (rect.width - symSize.width) / 2
            let y = (rect.height - symSize.height) / 2 + offset

            NSColor.systemOrange.set()
            configured.draw(in: NSRect(x: x, y: y, width: symSize.width, height: symSize.height),
                           from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        image.isTemplate = false
        return image
    }
}
