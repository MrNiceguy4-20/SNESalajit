import Foundation

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

    /// (dp) indirect. Pointer is read from direct page; data is fetched using DB as bank.
    @inline(__always)
    static func dpIndirect(cpu: CPU65816, bus: Bus) -> u16 {
        _ = bus
        let off = u16(cpu.fetch8())
        let ptr = cpu.r.dp &+ off
        return cpu.read16(0x00, ptr)
    }

    /// (dp,X) indirect. Pointer offset is X-indexed within direct page.
    @inline(__always)
    static func dpIndirectX(cpu: CPU65816, bus: Bus) -> u16 {
        _ = bus
        let off = u16(cpu.fetch8())
        let x = cpu.xIs8() ? u16(u8(truncatingIfNeeded: cpu.r.x)) : cpu.r.x
        let ptr = cpu.r.dp &+ off &+ x
        return cpu.read16(0x00, ptr)
    }

    /// (dp),Y indirect. Pointer is read from direct page then Y-indexed.
    @inline(__always)
    static func dpIndirectY(cpu: CPU65816, bus: Bus) -> u16 {
        _ = bus
        let off = u16(cpu.fetch8())
        let ptr = cpu.r.dp &+ off
        let base = cpu.read16(0x00, ptr)
        let y = cpu.xIs8() ? u16(u8(truncatingIfNeeded: cpu.r.y)) : cpu.r.y
        return base &+ y
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
        return cpu.read16(0x00, ptr)
    }

    // MARK: - Long and relative long

    @inline(__always)
    static func absLong(cpu: CPU65816, bus: Bus) -> (addr: u16, bank: u8) {
        _ = bus
        let addr = cpu.fetch16()
        let bank = cpu.fetch8()
        return (addr, bank)
    }

    @inline(__always)
    static func absLongX(cpu: CPU65816, bus: Bus) -> (addr: u16, bank: u8) {
        let base = absLong(cpu: cpu, bus: bus)
        let x = cpu.xIs8() ? u16(u8(truncatingIfNeeded: cpu.r.x)) : cpu.r.x
        return (base.addr &+ x, base.bank)
    }

    // MARK: - Relative

    @inline(__always)
    static func rel8(cpu: CPU65816, bus: Bus) -> Int8 {
        _ = bus
        return Int8(bitPattern: cpu.fetch8())
    }

    @inline(__always)
    static func rel16(cpu: CPU65816, bus: Bus) -> Int16 {
        _ = bus
        return Int16(bitPattern: cpu.fetch16())
    }
}
