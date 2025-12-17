import Foundation

/// Simple SNES controller (joypad) shift-register model.
///
/// We expose just enough for Phase 2 bring-up:
/// - $4016 write bit0: strobe (latch)
/// - $4016 read: serial data for pad1 (bit0)
/// - $4017 read: serial data for pad2 (bit0)
///
/// Button order (LSB-first) matches typical SNES docs:
/// B, Y, Select, Start, Up, Down, Left, Right, A, X, L, R, 1, 1, 1, 1
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
        var w: u16 = 0
        // LSB-first order
        func set(_ bit: Int, _ on: Bool) {
            if on { w |= (1 << bit) }
        }
        set(0, b)
        set(1, y)
        set(2, select)
        set(3, start)
        set(4, up)
        set(5, down)
        set(6, left)
        set(7, right)
        set(8, a)
        set(9, x)
        set(10, l)
        set(11, r)
        // Bits 12-15 are typically 1s.
        w |= 0xF000
        return w
    }
}

/// Internal joypad serial I/O state.
final class JoypadIO {
    // Public controller state (can be wired to UI later).
    var port1 = ControllerState()
    var port2 = ControllerState()

    // $4016 strobe bit (when high, continuously latch).
    private var strobeHigh: Bool = false

    // Shift registers (LSB is next output).
    private var shift1: u16 = 0xFFFF
    private var shift2: u16 = 0xFFFF

    func reset() {
        strobeHigh = false
        shift1 = 0xFFFF
        shift2 = 0xFFFF
    }

    /// Latch current controller state into shift registers.
    func latch() {
        shift1 = port1.toShiftWord()
        shift2 = port2.toShiftWord()
    }

    /// Write to $4016 (strobe).
    func writeStrobe(_ value: u8) {
        let newHigh = (value & 0x01) != 0
        // Latch on rising edge, and also keep latched while high.
        if newHigh && !strobeHigh {
            latch()
        }
        strobeHigh = newHigh
        if strobeHigh {
            latch()
        }
    }

    /// Read $4016 (pad 1). Returns bit0 only; other bits are 0.
    func read4016() -> u8 {
        if strobeHigh {
            latch()
        }
        let bit = u8(shift1 & 0x0001)
        if !strobeHigh {
            shift1 = (shift1 >> 1) | 0x8000
        }
        return bit
    }

    /// Read $4017 (pad 2). Returns bit0 only; other bits are 0.
    func read4017() -> u8 {
        if strobeHigh {
            latch()
        }
        let bit = u8(shift2 & 0x0001)
        if !strobeHigh {
            shift2 = (shift2 >> 1) | 0x8000
        }
        return bit
    }
}
