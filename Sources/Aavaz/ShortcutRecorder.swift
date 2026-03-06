import AppKit
import Carbon.HIToolbox
import CoreGraphics
import QuartzCore

@MainActor
final class ShortcutRecorder {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var eventMonitor: Any?
    var onKeyRecorded: ((UInt16, String) -> Void)?

    func show() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Set Trigger Key"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.center()

        let contentView = NSView(frame: panel.contentView!.bounds)

        let instruction = NSTextField(labelWithString: "Press the key you want to use\nas your trigger key")
        instruction.alignment = .center
        instruction.font = .systemFont(ofSize: 14)
        instruction.textColor = .secondaryLabelColor
        instruction.frame = NSRect(x: 20, y: 90, width: 300, height: 50)
        contentView.addSubview(instruction)

        let keyLabel = NSTextField(labelWithString: "Waiting for keypress…")
        keyLabel.alignment = .center
        keyLabel.font = .monospacedSystemFont(ofSize: 18, weight: .medium)
        keyLabel.frame = NSRect(x: 20, y: 45, width: 300, height: 30)
        contentView.addSubview(keyLabel)
        self.label = keyLabel

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.frame = NSRect(x: 120, y: 10, width: 100, height: 30)
        cancelButton.bezelStyle = .rounded
        contentView.addSubview(cancelButton)

        panel.contentView = contentView
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel

        // Listen for key events
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleEvent(event)
            return nil
        }
    }

    private func handleEvent(_ event: NSEvent) {
        let keyCode = event.keyCode

        // Map keyCode to a human-readable name
        let name = Self.keyName(for: keyCode)
        label?.stringValue = name

        // Small delay so the user sees what they pressed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.onKeyRecorded?(keyCode, name)
            self?.dismiss()
        }
    }

    @objc private func cancel() {
        dismiss()
    }

    private func dismiss() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        panel?.close()
        panel = nil
    }

    static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 56:  return "Left Shift"
        case 60:  return "Right Shift"
        case 59:  return "Left Control"
        case 62:  return "Right Control"
        case 58:  return "Left Option"
        case 61:  return "Right Option"
        case 55:  return "Left Command"
        case 54:  return "Right Command"
        case 57:  return "Caps Lock"
        case 63:  return "Fn / Globe"
        case 36:  return "Return"
        case 48:  return "Tab"
        case 49:  return "Space"
        case 51:  return "Delete"
        case 53:  return "Escape"
        default:
            // Try to get character from key code
            let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            if let data = layoutData {
                let layout = unsafeBitCast(data, to: CFData.self)
                let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<UCKeyboardLayout>.self)
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length: Int = 0
                UCKeyTranslate(
                    keyboardLayout,
                    keyCode,
                    UInt16(kUCKeyActionDown),
                    0, UInt32(LMGetKbdType()),
                    UInt32(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    4, &length, &chars
                )
                if length > 0 {
                    return String(utf16CodeUnits: chars, count: length).uppercased()
                }
            }
            return "Key \(keyCode)"
        }
    }
}
