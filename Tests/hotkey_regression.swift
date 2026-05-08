import Foundation

@inline(__always)
func expect(_ condition: Bool, _ message: String) {
    if !condition {
        fatalError(message)
    }
}

@main
struct HotkeyRegression {
    static func main() {
        var gate = ModifierDoubleTapGate(doubleTapInterval: 0.45, maximumFirstTapDuration: 0.35)

        expect(gate.handle(isDown: true, now: 1.00) == nil, "first left Option down should only arm tracking")
        expect(gate.handle(isDown: false, now: 1.08) == nil, "first left Option up should not activate")
        expect(gate.handle(isDown: true, now: 1.24) == true, "second left Option down within interval should activate")
        expect(gate.handle(isDown: false, now: 1.40) == false, "releasing second left Option should deactivate")

        var expired = ModifierDoubleTapGate(doubleTapInterval: 0.45, maximumFirstTapDuration: 0.35)
        _ = expired.handle(isDown: true, now: 2.00)
        _ = expired.handle(isDown: false, now: 2.05)
        expect(expired.handle(isDown: true, now: 2.80) == nil, "second tap after interval should not activate")

        var longHold = ModifierDoubleTapGate(doubleTapInterval: 0.45, maximumFirstTapDuration: 0.35)
        _ = longHold.handle(isDown: true, now: 3.00)
        _ = longHold.handle(isDown: false, now: 3.80)
        expect(longHold.handle(isDown: true, now: 3.90) == nil, "long first hold should not count as a tap")

        var resetWhileActive = ModifierDoubleTapGate(doubleTapInterval: 0.45, maximumFirstTapDuration: 0.35)
        _ = resetWhileActive.handle(isDown: true, now: 4.00)
        _ = resetWhileActive.handle(isDown: false, now: 4.05)
        _ = resetWhileActive.handle(isDown: true, now: 4.10)
        expect(resetWhileActive.reset() == false, "reset while active should request deactivation")
        expect(resetWhileActive.handle(isDown: true, now: 4.20) == nil, "duplicate down after reset should not reactivate")

        print("hotkey regression checks passed")
    }
}
