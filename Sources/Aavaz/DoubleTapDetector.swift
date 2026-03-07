import Foundation

final class DoubleTapDetector: Sendable {
    enum State: Sendable {
        case idle
        case firstTap
        case armed
    }

    struct Config: Sendable {
        var triggerKeyCode: UInt16 = 60  // Right Shift
        var doubleTapWindow: TimeInterval = 0.4
    }

    nonisolated(unsafe) private(set) var state: State = .idle
    nonisolated(unsafe) private var lastTapTime: TimeInterval = 0
    nonisolated(unsafe) var config = Config()

    func handleKeyEvent(keyCode: UInt16, isKeyDown: Bool, timestamp: TimeInterval) -> Bool {
        // Ignore events for keys we don't care about
        guard keyCode == config.triggerKeyCode else {
            return false
        }

        // Auto-expire stale states based on timestamp
        if state != .idle && (timestamp - lastTapTime) > config.doubleTapWindow * 2 {
            state = .idle
        }

        switch state {
        case .idle:
            if isKeyDown {
                state = .firstTap
                lastTapTime = timestamp
            }
        case .firstTap:
            if !isKeyDown {
                state = .armed
            }
        case .armed:
            if isKeyDown {
                let elapsed = timestamp - lastTapTime
                if elapsed <= config.doubleTapWindow {
                    reset()
                    return true  // Double tap detected
                } else {
                    // Too slow, treat as new first tap
                    state = .firstTap
                    lastTapTime = timestamp
                }
            }
        }
        return false
    }

    func reset() {
        state = .idle
        lastTapTime = 0
    }
}
