import Foundation

struct ControllerState: Sendable {
    var a = false
    var b = false
    var x = false
    var y = false
    var l = false
    var r = false
    var start = false
    var select = false
    var up = false
    var down = false
    var left = false
    var right = false
}

extension ControllerState {
    fileprivate func toShiftWord() -> u16 {
        var w: u16 = 0xFFFF

        func setPressed(_ bit: Int, _ pressed: Bool) {
            if pressed { w &= ~(1 << bit) }
        }

        setPressed(0, b)
        setPressed(1, y)
        setPressed(2, select)
        setPressed(3, start)
        setPressed(4, up)
        setPressed(5, down)
        setPressed(6, left)
        setPressed(7, right)
        setPressed(8, a)
        setPressed(9, x)
        setPressed(10, l)
        setPressed(11, r)

        w |= 0xF000
        return w
    }
}

final class JoypadIO {
    var port1 = ControllerState()
    var port2 = ControllerState()

    private var strobeHigh: Bool = false
    private var shift1: u16 = 0xFFFF
    private var shift2: u16 = 0xFFFF

    func reset() {
        strobeHigh = false
        shift1 = 0xFFFF
        shift2 = 0xFFFF
    }

    func latch() {
        shift1 = port1.toShiftWord()
        shift2 = port2.toShiftWord()
    }

    func writeStrobe(_ value: u8) {
        let newHigh = (value & 0x01) != 0
        if newHigh && !strobeHigh { latch() }
        strobeHigh = newHigh
        if strobeHigh { latch() }
    }

    func read4016() -> u8 {
        if strobeHigh { latch() }
        let bit = u8(shift1 & 0x0001)
        if !strobeHigh { shift1 = (shift1 >> 1) | 0x8000 }
        return bit
    }

    func read4017() -> u8 {
        if strobeHigh { latch() }
        let bit = u8(shift2 & 0x0001)
        if !strobeHigh { shift2 = (shift2 >> 1) | 0x8000 }
        return bit
    }

    func latchedWords() -> (u16, u16) {
        (shift1, shift2)
    }
}
