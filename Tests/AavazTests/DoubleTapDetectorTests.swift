import Testing
@testable import Aavaz

@Suite("DoubleTapDetector")
struct DoubleTapDetectorTests {
    @Test("Double tap within window triggers")
    func doubleTapTriggers() {
        let detector = DoubleTapDetector()
        let keyCode = detector.config.triggerKeyCode

        // First tap down
        _ = detector.handleKeyEvent(keyCode: keyCode, isKeyDown: true, timestamp: 0.0)
        #expect(detector.state == .firstTap)

        // First tap up
        _ = detector.handleKeyEvent(keyCode: keyCode, isKeyDown: false, timestamp: 0.05)
        #expect(detector.state == .armed)

        // Second tap down within window
        let triggered = detector.handleKeyEvent(keyCode: keyCode, isKeyDown: true, timestamp: 0.15)
        #expect(triggered)
        #expect(detector.state == .idle)
    }

    @Test("Double tap outside window does not trigger")
    func doubleTapTooSlow() {
        let detector = DoubleTapDetector()
        let keyCode = detector.config.triggerKeyCode

        _ = detector.handleKeyEvent(keyCode: keyCode, isKeyDown: true, timestamp: 0.0)
        _ = detector.handleKeyEvent(keyCode: keyCode, isKeyDown: false, timestamp: 0.05)

        // Second tap outside window
        let triggered = detector.handleKeyEvent(keyCode: keyCode, isKeyDown: true, timestamp: 0.5)
        #expect(!triggered)
        #expect(detector.state == .firstTap)
    }

    @Test("Other keys do not interfere with detection")
    func otherKeysIgnored() {
        let detector = DoubleTapDetector()
        let keyCode = detector.config.triggerKeyCode

        _ = detector.handleKeyEvent(keyCode: keyCode, isKeyDown: true, timestamp: 0.0)
        #expect(detector.state == .firstTap)

        // Other key events should NOT reset state
        _ = detector.handleKeyEvent(keyCode: 999, isKeyDown: true, timestamp: 0.02)
        _ = detector.handleKeyEvent(keyCode: 999, isKeyDown: false, timestamp: 0.03)
        #expect(detector.state == .firstTap)

        // Continue with trigger key — should still work
        _ = detector.handleKeyEvent(keyCode: keyCode, isKeyDown: false, timestamp: 0.05)
        #expect(detector.state == .armed)

        let triggered = detector.handleKeyEvent(keyCode: keyCode, isKeyDown: true, timestamp: 0.15)
        #expect(triggered)
    }

    @Test("Reset clears state")
    func resetWorks() {
        let detector = DoubleTapDetector()
        let keyCode = detector.config.triggerKeyCode

        _ = detector.handleKeyEvent(keyCode: keyCode, isKeyDown: true, timestamp: 0.0)
        detector.reset()
        #expect(detector.state == .idle)
    }

    @Test("Stale state auto-expires")
    func staleStateExpires() {
        let detector = DoubleTapDetector()
        let keyCode = detector.config.triggerKeyCode

        _ = detector.handleKeyEvent(keyCode: keyCode, isKeyDown: true, timestamp: 0.0)
        #expect(detector.state == .firstTap)

        // Much later — should auto-expire
        _ = detector.handleKeyEvent(keyCode: keyCode, isKeyDown: true, timestamp: 5.0)
        #expect(detector.state == .firstTap) // Reset to idle, then immediately set to firstTap
    }
}
