import AppKit
import Foundation
import QuartzCore

@MainActor
final class HotkeyMonitor {
    var onDoubleTap: (() -> Void)?
    var onCancel: (() -> Void)?
    var onStatusChange: ((String) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let detector = DoubleTapDetector()

    var triggerKeyCode: UInt16 {
        get { detector.config.triggerKeyCode }
        set { detector.config.triggerKeyCode = newValue }
    }

    var doubleTapWindow: TimeInterval {
        get { detector.config.doubleTapWindow }
        set { detector.config.doubleTapWindow = newValue }
    }

    func start() {
        guard globalMonitor == nil else {
            onStatusChange?("Hotkey active")
            return
        }

        let eventMask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]

        // Global monitor catches events when OTHER apps are focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
            // Global monitor callback runs on the main thread
            self?.handleEvent(event)
        }

        // Local monitor catches events when OUR app's menu is open
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.handleEvent(event)
            return event
        }

        if globalMonitor != nil {
            print("[Aavaz] Global key monitor started — listening for keyCode \(triggerKeyCode)")
            onStatusChange?("Ready — double-tap \(ShortcutRecorder.keyName(for: triggerKeyCode))")
        } else {
            print("[Aavaz] ERROR: Failed to create global monitor — Accessibility permission not granted")
            onStatusChange?("No Accessibility permission")
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        detector.reset()
    }

    private func handleEvent(_ event: NSEvent) {
        let keyCode = event.keyCode

        if event.type == .flagsChanged {
            let isDown = Self.isModifierDown(keyCode: keyCode, flags: event.modifierFlags)
            print("[Aavaz] flagsChanged keyCode=\(keyCode) isDown=\(isDown) trigger=\(triggerKeyCode) state=\(detector.state)")
        }

        // Escape cancels recording
        if keyCode == 53 && event.type == .keyDown {
            onCancel?()
            return
        }

        // For modifier keys, use flagsChanged and check the appropriate mask
        let isKeyDown: Bool
        if event.type == .flagsChanged {
            isKeyDown = Self.isModifierDown(keyCode: keyCode, flags: event.modifierFlags)
        } else {
            isKeyDown = event.type == .keyDown
        }

        let triggered = detector.handleKeyEvent(
            keyCode: keyCode,
            isKeyDown: isKeyDown,
            timestamp: CACurrentMediaTime()
        )

        if triggered {
            print("[Aavaz] Double-tap detected!")
            onDoubleTap?()
        }
    }

    private static func isModifierDown(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case 56, 60:  return flags.contains(.shift)
        case 59, 62:  return flags.contains(.control)
        case 58, 61:  return flags.contains(.option)
        case 55, 54:  return flags.contains(.command)
        case 57:      return flags.contains(.capsLock)
        case 63:      return flags.contains(.function)
        default:      return false
        }
    }
}
