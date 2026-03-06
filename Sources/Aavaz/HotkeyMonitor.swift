import CoreGraphics
import Foundation
import QuartzCore

@MainActor
final class HotkeyMonitor {
    var onDoubleTap: (() -> Void)?
    var onCancel: (() -> Void)?

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
        guard eventTap == nil else { return }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        // Store callback context
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: context
        ) else {
            print("Failed to create event tap. Check Accessibility permissions.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
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

    fileprivate func handleKeyInfo(keyCode: UInt16, eventType: CGEventType, flags: CGEventFlags) {
        // Escape cancels recording
        if keyCode == 53 && eventType == .keyDown {
            onCancel?()
            return
        }

        // For modifier keys (like Right Option), use flagsChanged
        let isKeyDown: Bool
        if eventType == .flagsChanged {
            isKeyDown = flags.contains(.maskAlternate)
        } else {
            isKeyDown = eventType == .keyDown
        }

        let triggered = detector.handleKeyEvent(
            keyCode: keyCode,
            isKeyDown: isKeyDown,
            timestamp: CACurrentMediaTime()
        )

        if triggered {
            onDoubleTap?()
        }
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Handle tap disabled events
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // Re-enable
        return Unmanaged.passUnretained(event)
    }

    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let eventType = event.type
    let flags = event.flags

    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    MainActor.assumeIsolated {
        monitor.handleKeyInfo(keyCode: keyCode, eventType: eventType, flags: flags)
    }

    return Unmanaged.passUnretained(event)
}
