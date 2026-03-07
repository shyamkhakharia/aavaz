import CoreGraphics
import Foundation
import QuartzCore

@MainActor
final class HotkeyMonitor {
    var onDoubleTap: (() -> Void)?
    var onCancel: (() -> Void)?
    var onStatusChange: ((String) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
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
        guard eventTap == nil else {
            onStatusChange?("Hotkey active")
            return
        }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: context
        ) else {
            print("[Aavaz] ERROR: Failed to create event tap — Accessibility permission not granted")
            onStatusChange?("No Accessibility permission")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        print("[Aavaz] Event tap created — listening for keyCode \(triggerKeyCode)")
        onStatusChange?("Ready — double-tap \(ShortcutRecorder.keyName(for: triggerKeyCode))")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
        }
        detector.reset()
    }

    fileprivate func reEnableTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            print("[Aavaz] Re-enabled event tap after timeout")
        }
    }

    fileprivate func handleKeyInfo(keyCode: UInt16, eventType: CGEventType, flags: CGEventFlags) {
        // Log flagsChanged events for debugging
        if eventType == .flagsChanged {
            let mask = Self.modifierMask(for: keyCode)
            let isDown = flags.contains(mask)
            print("[Aavaz] flagsChanged keyCode=\(keyCode) isDown=\(isDown) trigger=\(triggerKeyCode) state=\(detector.state)")
        }

        // Escape cancels recording
        if keyCode == 53 && eventType == .keyDown {
            onCancel?()
            return
        }

        // For modifier keys, use flagsChanged and check the appropriate mask
        let isKeyDown: Bool
        if eventType == .flagsChanged {
            let mask = Self.modifierMask(for: keyCode)
            isKeyDown = flags.contains(mask)
        } else {
            isKeyDown = eventType == .keyDown
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

    private static func modifierMask(for keyCode: UInt16) -> CGEventFlags {
        switch keyCode {
        case 56, 60:  return .maskShift
        case 59, 62:  return .maskControl
        case 58, 61:  return .maskAlternate
        case 55, 54:  return .maskCommand
        case 57:      return .maskAlphaShift
        case 63:      return .maskSecondaryFn
        default:      return CGEventFlags(rawValue: 0)
        }
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    // Re-enable tap if macOS disabled it
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated {
            monitor.reEnableTap()
        }
        return Unmanaged.passUnretained(event)
    }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let eventType = event.type
    let flags = event.flags

    MainActor.assumeIsolated {
        monitor.handleKeyInfo(keyCode: keyCode, eventType: eventType, flags: flags)
    }

    return Unmanaged.passUnretained(event)
}
