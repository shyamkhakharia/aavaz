import AppKit
import CoreGraphics

@MainActor
final class TextInjector {
    var injectionDelay: TimeInterval = 0.1
    var restoreClipboard: Bool = true

    /// Returns true if text was injected, false if accessibility permission is missing.
    func inject(text: String) async -> Bool {
        let pasteboard = NSPasteboard.general

        // Save current clipboard
        let savedItems: [NSPasteboardItem]?
        if restoreClipboard {
            savedItems = pasteboard.pasteboardItems?.compactMap { item in
                let copy = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) {
                        copy.setData(data, forType: type)
                    }
                }
                return copy
            }
        } else {
            savedItems = nil
        }

        // Set transcription text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Wait for pasteboard to settle
        try? await Task.sleep(for: .milliseconds(Int(injectionDelay * 1000)))

        // Simulate Cmd+V
        let pasted = simulatePaste()

        // Restore clipboard after a short delay
        if pasted, restoreClipboard, let savedItems {
            try? await Task.sleep(for: .milliseconds(200))
            pasteboard.clearContents()
            pasteboard.writeObjects(savedItems)
        }

        return pasted
    }

    /// Returns false if accessibility permission is missing.
    private func simulatePaste() -> Bool {
        // Check accessibility — CGEvent.post silently fails without it
        let trusted = AXIsProcessTrustedWithOptions(nil)
        if !trusted {
            print("[Aavaz] Accessibility permission not granted — can't simulate paste")
            return false
        }

        let source = CGEventSource(stateID: .hidSystemState)

        // Key code 9 = 'v'
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
