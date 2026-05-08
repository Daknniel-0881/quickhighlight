import Foundation

/// Small state machine for "tap once to arm, press again to activate" modifier-key input.
///
/// The overlay keeps its original hold-to-show feel: the second key-down activates, and the
/// matching key-up deactivates. A long first hold does not count as a tap, which keeps normal
/// Option-key shortcuts from arming the magnifier accidentally.
struct ModifierDoubleTapGate {
    let doubleTapInterval: TimeInterval
    let maximumFirstTapDuration: TimeInterval

    private var physicalIsDown = false
    private var firstDownAt: TimeInterval?
    private var armedUntil: TimeInterval?
    private var isActive = false

    init(doubleTapInterval: TimeInterval = 0.45, maximumFirstTapDuration: TimeInterval = 0.35) {
        self.doubleTapInterval = doubleTapInterval
        self.maximumFirstTapDuration = maximumFirstTapDuration
    }

    /// Returns `true` / `false` only when the public activation state should change.
    mutating func handle(isDown: Bool, now: TimeInterval) -> Bool? {
        if let deadline = armedUntil, now > deadline {
            armedUntil = nil
        }

        guard isDown != physicalIsDown else { return nil }
        physicalIsDown = isDown

        if isDown {
            firstDownAt = now
            if let deadline = armedUntil, now <= deadline {
                armedUntil = nil
                isActive = true
                return true
            }
            return nil
        }

        defer { firstDownAt = nil }
        if isActive {
            isActive = false
            armedUntil = nil
            return false
        }

        if let downAt = firstDownAt, now - downAt <= maximumFirstTapDuration {
            armedUntil = now + doubleTapInterval
        } else {
            armedUntil = nil
        }
        return nil
    }

    /// Clears state. If the gate was active, callers should publish the returned `false`.
    mutating func reset() -> Bool? {
        let shouldDeactivate = isActive
        physicalIsDown = false
        firstDownAt = nil
        armedUntil = nil
        isActive = false
        return shouldDeactivate ? false : nil
    }
}
