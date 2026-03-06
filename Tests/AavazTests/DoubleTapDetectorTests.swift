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

    @Test("Wrong key resets state")
    func wrongKeyResets() {
        let detector = DoubleTapDetector()
        let keyCode = detector.config.triggerKeyCode

        _ = detector.handleKeyEvent(keyCode: keyCode, isKeyDown: true, timestamp: 0.0)
        #expect(detector.state == .firstTap)

        // Different key
        _ = detector.handleKeyEvent(keyCode: 999, isKeyDown: true, timestamp: 0.1)
        #expect(detector.state == .idle)
    }

    @Test("Reset clears state")
    func resetWorks() {
        let detector = DoubleTapDetector()
        let keyCode = detector.config.triggerKeyCode

        _ = detector.handleKeyEvent(keyCode: keyCode, isKeyDown: true, timestamp: 0.0)
        detector.reset()
        #expect(detector.state == .idle)
    }
}
