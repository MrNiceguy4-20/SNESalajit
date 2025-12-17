import Foundation

/// Addressing mode helpers.
///
/// Encapsulation:
/// - Must not mutate cpu.r directly.
/// - Use cpu.fetch8()/fetch16()/advancePC() and cpu read/write helpers.
enum CPUAddressing {

    // MARK: - Immediate

    @inline(__always)
    static func imm8(cpu: CPU65816, bus: Bus) -> u8 {
        _ = bus
        return cpu.fetch8()
    }

    @inline(__always)
    static func imm16(cpu: CPU65816, bus: Bus) -> u16 {
        _ = bus
        return cpu.fetch16()
    }

    // MARK: - Direct Page

    @inline(__always)
    static func dp(cpu: CPU65816, bus: Bus) -> u16 {
        _ = bus
        let off = u16(cpu.fetch8())
        return cpu.r.dp &+ off
    }

    @inline(__always)
    static func dpX(cpu: CPU65816, bus: Bus) -> u16 {
        _ = bus
        let off = u16(cpu.fetch8())
        let x = cpu.xIs8() ? u16(u8(truncatingIfNeeded: cpu.r.x)) : cpu.r.x
        return cpu.r.dp &+ off &+ x
    }

    @inline(__always)
    static func dpY(cpu: CPU65816, bus: Bus) -> u16 {
        _ = bus
        let off = u16(cpu.fetch8())
        let y = cpu.xIs8() ? u16(u8(truncatingIfNeeded: cpu.r.y)) : cpu.r.y
        return cpu.r.dp &+ off &+ y
    }

    // MARK: - Absolute

    @inline(__always)
    static func abs16(cpu: CPU65816, bus: Bus) -> u16 {
        _ = bus
        return cpu.fetch16()
    }

    @inline(__always)
    static func absX(cpu: CPU65816, bus: Bus) -> u16 {
        _ = bus
        let base = cpu.fetch16()
        let x = cpu.xIs8() ? u16(u8(truncatingIfNeeded: cpu.r.x)) : cpu.r.x
        return base &+ x
    }

    @inline(__always)
    static func absY(cpu: CPU65816, bus: Bus) -> u16 {
        _ = bus
        let base = cpu.fetch16()
        let y = cpu.xIs8() ? u16(u8(truncatingIfNeeded: cpu.r.y)) : cpu.r.y
        return base &+ y
    }

    // MARK: - Indirect

    /// JMP ($addr) in emulation: indirect wraps within bank 0 (we use bank = PB for fetch, then bank 0 for pointer read).
    @inline(__always)
    static func absIndirect(cpu: CPU65816, bus: Bus) -> u16 {
        let ptr = cpu.fetch16()
        _ = bus
        // SNES/65C816: indirect reads from bank 0 for JMP (abs) in emulation paths; good enough for Phase 1.
        return cpu.read16(0x00, ptr)
    }

    // MARK: - Relative

    @inline(__always)
    static func rel8(cpu: CPU65816, bus: Bus) -> Int8 {
        _ = bus
        return Int8(bitPattern: cpu.fetch8())
    }
}
