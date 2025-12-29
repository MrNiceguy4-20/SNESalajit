import Foundation

enum CPUAddressing {

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

    @inline(__always)
    static func dpIndirect(cpu: CPU65816, bus: Bus) -> u16 {
        _ = bus
        let off = u16(cpu.fetch8())
        let ptr = cpu.r.dp &+ off
        return cpu.read16(0x00, ptr)
    }

    @inline(__always)
    static func dpIndirectX(cpu: CPU65816, bus: Bus) -> u16 {
        _ = bus
        let off = u16(cpu.fetch8())
        let x = cpu.xIs8() ? u16(u8(truncatingIfNeeded: cpu.r.x)) : cpu.r.x
        let ptr = cpu.r.dp &+ off &+ x
        return cpu.read16(0x00, ptr)
    }

    @inline(__always)
    static func dpIndirectY(cpu: CPU65816, bus: Bus) -> u16 {
        _ = bus
        let off = u16(cpu.fetch8())
        let ptr = cpu.r.dp &+ off
        let base = cpu.read16(0x00, ptr)
        let y = cpu.xIs8() ? u16(u8(truncatingIfNeeded: cpu.r.y)) : cpu.r.y
        return base &+ y
    }

    @inline(__always)
    static func dpIndirectLong(cpu: CPU65816, bus: Bus) -> (addr: u16, bank: u8) {
        _ = bus
        let off = u16(cpu.fetch8())
        let ptr0 = cpu.r.dp &+ off
        let ptr1 = ptr0 &+ 1
        let ptr2 = ptr0 &+ 2

        let lo = cpu.read8(0x00, ptr0)
        let hi = cpu.read8(0x00, ptr1)
        let bank = cpu.read8(0x00, ptr2)

        let addr = u16(lo) | (u16(hi) << 8)
        return (addr, bank)
    }

    @inline(__always)
    static func dpIndirectLongY(cpu: CPU65816, bus: Bus) -> (addr: u16, bank: u8) {
        _ = bus
        let off = u16(cpu.fetch8())
        let ptr0 = cpu.r.dp &+ off
        let ptr1 = ptr0 &+ 1
        let ptr2 = ptr0 &+ 2

        let lo = cpu.read8(0x00, ptr0)
        let hi = cpu.read8(0x00, ptr1)
        let ba = cpu.read8(0x00, ptr2)

        let y = cpu.xIs8() ? u32(u8(truncatingIfNeeded: cpu.r.y)) : u32(cpu.r.y)
        let base24 = (u32(ba) << 16) | (u32(hi) << 8) | u32(lo)
        let final24 = (base24 &+ y) & 0x00FF_FFFF

        return (u16(final24 & 0xFFFF), u8((final24 >> 16) & 0xFF))
    }

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

    @inline(__always)
    static func absIndirect(cpu: CPU65816, bus: Bus) -> u16 {
        let ptr = cpu.fetch16()
        _ = bus
        return cpu.read16(0x00, ptr)
    }

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

    @inline(__always)
    static func stackRelative(cpu: CPU65816, bus: Bus) -> u16 {
        _ = bus
        let off = u16(cpu.fetch8())
        return cpu.r.sp &+ off
    }
}
