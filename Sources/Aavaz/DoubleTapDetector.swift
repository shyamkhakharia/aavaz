import Foundation

final class DoubleTapDetector: @unchecked Sendable {
    enum State: Sendable {
        case idle
        case firstTap
        case armed
    }

    struct Config: Sendable {
        var triggerKeyCode: UInt16 = 61  // Right Option
        var doubleTapWindow: TimeInterval = 0.4
    }

    private let lock = NSLock()
    private var _state: State = .idle
    private var _lastTapTime: TimeInterval = 0
    private var _config = Config()

    var state: State {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    var config: Config {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _config
        }
        set {
            lock.lock()
            _config = newValue
            lock.unlock()
        }
    }

    func handleKeyEvent(keyCode: UInt16, isKeyDown: Bool, timestamp: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard keyCode == _config.triggerKeyCode else {
            return false
        }

        // Auto-expire stale states based on timestamp
        if _state != .idle && (timestamp - _lastTapTime) > _config.doubleTapWindow * 2 {
            _state = .idle
        }

        switch _state {
        case .idle:
            if isKeyDown {
                _state = .firstTap
                _lastTapTime = timestamp
            }
        case .firstTap:
            if !isKeyDown {
                _state = .armed
            }
        case .armed:
            if isKeyDown {
                let elapsed = timestamp - _lastTapTime
                if elapsed <= _config.doubleTapWindow {
                    _state = .idle
                    _lastTapTime = 0
                    return true  // Double tap detected
                } else {
                    // Too slow, treat as new first tap
                    _state = .firstTap
                    _lastTapTime = timestamp
                }
            }
        }
        return false
    }

    func reset() {
        lock.lock()
        _state = .idle
        _lastTapTime = 0
        lock.unlock()
    }
}
