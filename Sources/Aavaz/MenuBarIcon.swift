import AppKit

/// Menubar icon states using SF Symbols.
/// Idle: waveform — clean audio identity.
/// Recording: waveform.badge.mic — mic badge signals "listening".
/// Transcribing: animated waveform with pulsing tint.
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

    static let transcribeSymbols = ["waveform.path.ecg", "waveform", "waveform.path.ecg", "waveform"]
    static let frameCount = transcribeSymbols.count

    static func transcribing(frame: Int) -> NSImage {
        let name = transcribeSymbols[frame % transcribeSymbols.count]
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Transcribing")!
        image.isTemplate = false
        return image
    }
}
