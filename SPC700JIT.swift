import Foundation

final class SPC700JIT {

    typealias BlockFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32) -> UInt64

    private let mem = JITExecutableMemory()
    private let asm = X64Assembler()

    private var blocks: [u16: UnsafeRawPointer] = [:]

    var enabled: Bool = false

    func reset() {
        blocks.removeAll(keepingCapacity: true)
        mem.reset()
    }

    private func compileBlock(startPC: u16) -> UnsafeRawPointer? {
        var code: [UInt8] = []
        code += asm.movRCX_RDX()
        code += asm.movRDX(imm64: UInt64(startPC))
        code += asm.movRAX(imm64: UInt64(UInt(bitPattern: spc700jit_execHotBlock_ptr)))
        code += asm.callRAX()
        code += asm.ret()
        return mem.append(code)
    }

    private func getBlock(pc: u16) -> UnsafeRawPointer? {
        if let b = blocks[pc] { return b }
        guard let b = compileBlock(startPC: pc) else { return nil }
        blocks[pc] = b
        return b
    }

    @inline(__always)
    private func unpackRemaining(_ packed: UInt64) -> Int {
        Int(Int32(bitPattern: UInt32(truncatingIfNeeded: packed)))
    }

    @inline(__always)
    private func unpackNextPC(_ packed: UInt64) -> u16 {
        u16(truncatingIfNeeded: UInt32(truncatingIfNeeded: packed >> 32))
    }

    func run(cpu: SPC700, apu: APU, interpreter: SPC700Interpreter, cycles: Int) {
        guard cycles > 0 else { return }
        if cpu.halted { return }

        var remaining = cycles

        if enabled {
            var chain = 0
            let maxChain = 16

            while remaining > 0, chain < maxChain, !cpu.halted {
                guard let entry = getBlock(pc: cpu.pc) else { break }
                let fn = unsafeBitCast(entry, to: BlockFn.self)
                let packed = fn(Unmanaged.passUnretained(cpu).toOpaque(),
                                Unmanaged.passUnretained(apu).toOpaque(),
                                Int32(remaining))

                let nextPC = unpackNextPC(packed)
                remaining = unpackRemaining(packed)

                if nextPC == 0xFFFF { break }

                cpu.pc = nextPC
                chain += 1
            }
        }

        if remaining > 0 {
            interpreter.step(cpu: cpu, apu: apu, cycles: remaining)
        }
    }
}

private let spc700jit_execHotBlock_ptr: UnsafeMutableRawPointer = {
    unsafeBitCast(
        spc700jit_execHotBlock as (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, u16, Int32) -> UInt64),
        to: UnsafeMutableRawPointer.self
    )
}()

@inline(__always)
private func spc700jit_pack(nextPC: u16, remaining: Int) -> UInt64 {
    let rem = UInt32(bitPattern: Int32(remaining))
    return (UInt64(nextPC) << 32) | UInt64(rem)
}

@_cdecl("spc700jit_execHotBlock")
func spc700jit_execHotBlock(
    _ cpuPtr: UnsafeMutableRawPointer?,
    _ apuPtr: UnsafeMutableRawPointer?,
    _ startPC: u16,
    _ cycles: Int32
) -> UInt64 {
    guard let cpuPtr, let apuPtr else { return spc700jit_pack(nextPC: 0xFFFF, remaining: Int(cycles)) }
    let cpu = Unmanaged<SPC700>.fromOpaque(cpuPtr).takeUnretainedValue()
    let apu = Unmanaged<APU>.fromOpaque(apuPtr).takeUnretainedValue()

    if cpu.halted { return spc700jit_pack(nextPC: 0xFFFF, remaining: Int(cycles)) }
    if cpu.pc != startPC { return spc700jit_pack(nextPC: 0xFFFF, remaining: Int(cycles)) }

    var remaining = Int(cycles)
    let maxInsns = 32
    var insns = 0

    @inline(__always)
    func isIO(_ addr: u16) -> Bool {
        (addr & 0xFFF0) == 0x00F0
    }

    @inline(__always)
    func dpAddr(_ off: u8) -> u16 { cpu.dpBase() | u16(off) }

    @inline(__always)
    func dpXAddr(_ off: u8) -> u16 {
        let a = (u16(off) &+ u16(cpu.x)) & 0x00FF
        return cpu.dpBase() | a
    }

    @inline(__always)
    func indXAddr(_ dp: u8) -> u16 {
        let p = (u16(dp) &+ u16(cpu.x)) & 0x00FF
        let loAddr = cpu.dpBase() | p
        let hiAddr = cpu.dpBase() | ((p &+ 1) & 0x00FF)
        if isIO(loAddr) || isIO(hiAddr) { return 0xFFFF }
        let lo = u16(apu.read8(loAddr))
        let hi = u16(apu.read8(hiAddr))
        return lo | (hi << 8)
    }

    @inline(__always)
    func dpWordAddrs(_ off: u8) -> (u16, u16) {
        let p = u16(off)
        let loAddr = cpu.dpBase() | p
        let hiAddr = cpu.dpBase() | ((p &+ 1) & 0x00FF)
        return (loAddr, hiAddr)
    }

    @inline(__always)
    func readDP16(_ off: u8) -> u16 {
        let (loAddr, hiAddr) = dpWordAddrs(off)
        let lo = u16(apu.read8(loAddr))
        let hi = u16(apu.read8(hiAddr))
        return lo | (hi << 8)
    }

    @inline(__always)
    func writeDP16(_ off: u8, _ v: u16) {
        let (loAddr, hiAddr) = dpWordAddrs(off)
        apu.write8(loAddr, u8(truncatingIfNeeded: v))
        apu.write8(hiAddr, u8(truncatingIfNeeded: v >> 8))
    }
    
    @inline(__always)
    func absBitOperand() -> (u16, Int) {
        let lo = u16(cpu.fetch8(apu))
        let hi = u16(cpu.fetch8(apu))
        let word = lo | (hi << 8)
        let bit = Int((word >> 13) & 0x07)
        let addr = u16(word & 0x1FFF)
        return (addr, bit)
    }

    @inline(__always)
    func indYAddr(_ dp: u8) -> u16 {
        let p = u16(dp)
        let loAddr = cpu.dpBase() | p
        let hiAddr = cpu.dpBase() | ((p &+ 1) & 0x00FF)
        if isIO(loAddr) || isIO(hiAddr) { return 0xFFFF }
        let lo = u16(apu.read8(loAddr))
        let hi = u16(apu.read8(hiAddr))
        let base = lo | (hi << 8)
        return base &+ u16(cpu.y)
    }

    while remaining > 0, insns < maxInsns {
        let opPC = cpu.pc
        let op = cpu.fetch8(apu)

        switch op {
        case 0x00:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            remaining -= 2
        case 0xE8:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = cpu.fetch8(apu)
            cpu.updateNZ(cpu.a)
            remaining -= 2
        case 0xCD:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.x = cpu.fetch8(apu)
            cpu.updateNZ(cpu.x)
            remaining -= 2
        case 0x8D:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.y = cpu.fetch8(apu)
            cpu.updateNZ(cpu.y)
            remaining -= 2
        case 0xE4:
            if remaining < 3 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = apu.read8(addr)
            cpu.updateNZ(cpu.a)
            remaining -= 3
        case 0xC4:
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            apu.write8(addr, cpu.a)
            remaining -= 4
        case 0xBC:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a &+= 1
            cpu.updateNZ(cpu.a)
            remaining -= 2
        case 0x9C:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a &-= 1
            cpu.updateNZ(cpu.a)
            remaining -= 2
        case 0x2F:
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
            remaining -= 4
        case 0xF0:
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            if cpu.flag(SPC700.Z) {
                if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 4
            } else {
                if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 2
            }
        case 0xD0:
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            if !cpu.flag(SPC700.Z) {
                if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 4
            } else {
                if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 2
            }
        case 0x90:
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            if !cpu.flag(SPC700.C) {
                if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 4
            } else {
                if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 2
            }
        case 0xB0:
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            if cpu.flag(SPC700.C) {
                if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 4
            } else {
                if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 2
            }
        case 0x10:
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            if !cpu.flag(SPC700.N) {
                if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 4
            } else {
                if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 2
            }
        case 0x30:
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            if cpu.flag(SPC700.N) {
                if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 4
            } else {
                if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 2
            }
        case 0x50:
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            if !cpu.flag(SPC700.V) {
                if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 4
            } else {
                if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 2
            }
        case 0x70:
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            if cpu.flag(SPC700.V) {
                if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 4
            } else {
                if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 2
            }
        case 0xF4:
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpXAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = apu.read8(addr)
            cpu.updateNZ(cpu.a)
            remaining -= 4
        case 0xD4:
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpXAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            apu.write8(addr, cpu.a)
            remaining -= 5
        case 0x28:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a &= cpu.fetch8(apu)
            cpu.updateNZ(cpu.a)
            remaining -= 2
        case 0x08:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a |= cpu.fetch8(apu)
            cpu.updateNZ(cpu.a)
            remaining -= 2
        case 0x48:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a ^= cpu.fetch8(apu)
            cpu.updateNZ(cpu.a)
            remaining -= 2
        case 0x68:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = cpu.fetch8(apu)
            cpu.cmp(cpu.a, v)
            remaining -= 2
        case 0x60:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.setFlag(SPC700.C, false)
            remaining -= 2
        case 0x80:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.setFlag(SPC700.C, true)
            remaining -= 2
        case 0x20:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.setFlag(SPC700.P, false)
            remaining -= 2
        case 0x40:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.setFlag(SPC700.P, true)
            remaining -= 2
        case 0xC0:
            if remaining < 3 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.setFlag(SPC700.I, false)
            remaining -= 3
        case 0xA0:
            if remaining < 3 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.setFlag(SPC700.I, true)
            remaining -= 3
        case 0x04, 0x24, 0x44, 0x64, 0x84, 0xA4:
            if remaining < 3 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let m = apu.read8(addr)
            switch op {
            case 0x04: cpu.a |= m; cpu.updateNZ(cpu.a)
            case 0x24: cpu.a &= m; cpu.updateNZ(cpu.a)
            case 0x44: cpu.a ^= m; cpu.updateNZ(cpu.a)
            case 0x64: cpu.cmp(cpu.a, m)
            case 0x84: cpu.adc(m)
            default:   cpu.sbc(m)
            }
            remaining -= 3
        case 0x14, 0x34, 0x54, 0x74, 0x94, 0xB4:
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpXAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let m = apu.read8(addr)
            switch op {
            case 0x14: cpu.a |= m; cpu.updateNZ(cpu.a)
            case 0x34: cpu.a &= m; cpu.updateNZ(cpu.a)
            case 0x54: cpu.a ^= m; cpu.updateNZ(cpu.a)
            case 0x74: cpu.cmp(cpu.a, m)
            case 0x94: cpu.adc(m)
            default:   cpu.sbc(m)
            }
            remaining -= 4
        case 0xE7, 0xF7:
            if remaining < 6 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let dp = cpu.fetch8(apu)
            let addr = (op == 0xE7) ? indXAddr(dp) : indYAddr(dp)
            if addr == 0xFFFF || isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = apu.read8(addr)
            cpu.updateNZ(cpu.a)
            remaining -= 6
        case 0x07, 0x27, 0x47, 0x67, 0x87, 0xA7:
            if remaining < 6 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let dp = cpu.fetch8(apu)
            let addr = indXAddr(dp)
            if addr == 0xFFFF || isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let m = apu.read8(addr)
            switch op {
            case 0x07: cpu.a |= m; cpu.updateNZ(cpu.a)
            case 0x27: cpu.a &= m; cpu.updateNZ(cpu.a)
            case 0x47: cpu.a ^= m; cpu.updateNZ(cpu.a)
            case 0x67: cpu.cmp(cpu.a, m)
            case 0x87: cpu.adc(m)
            default:   cpu.sbc(m)
            }
            remaining -= 6
        case 0x17, 0x37, 0x57, 0x77, 0x97, 0xB7:
            if remaining < 6 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let dp = cpu.fetch8(apu)
            let addr = indYAddr(dp)
            if addr == 0xFFFF || isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let m = apu.read8(addr)
            switch op {
            case 0x17: cpu.a |= m; cpu.updateNZ(cpu.a)
            case 0x37: cpu.a &= m; cpu.updateNZ(cpu.a)
            case 0x57: cpu.a ^= m; cpu.updateNZ(cpu.a)
            case 0x77: cpu.cmp(cpu.a, m)
            case 0x97: cpu.adc(m)
            default:   cpu.sbc(m)
            }
            remaining -= 6
        case 0xCB:
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            apu.write8(addr, cpu.y)
            remaining -= 4
        case 0xDB:
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpXAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            apu.write8(addr, cpu.y)
            remaining -= 5
        case 0xD8:
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            apu.write8(addr, cpu.x)
            remaining -= 4
        case 0x8F:
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let imm = cpu.fetch8(apu)
            let off = cpu.fetch8(apu)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            apu.write8(addr, imm)
            remaining -= 5
        case 0xAB:
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = apu.read8(addr) &+ 1
            apu.write8(addr, v)
            cpu.updateNZ(v)
            remaining -= 4
        case 0xBB:
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpXAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = apu.read8(addr) &+ 1
            apu.write8(addr, v)
            cpu.updateNZ(v)
            remaining -= 5
        case 0x8B:
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = apu.read8(addr) &- 1
            apu.write8(addr, v)
            cpu.updateNZ(v)
            remaining -= 4
        case 0x9B:
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpXAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = apu.read8(addr) &- 1
            apu.write8(addr, v)
            cpu.updateNZ(v)
            remaining -= 5
        case 0x1C:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = cpu.asl(cpu.a)
            remaining -= 2
        case 0x5C:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = cpu.lsr(cpu.a)
            remaining -= 2
        case 0x3C:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = cpu.rol(cpu.a)
            remaining -= 2
        case 0x7C:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = cpu.ror(cpu.a)
            remaining -= 2
        case 0x0B, 0x4B, 0x2B, 0x6B:
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            var v = apu.read8(addr)
            switch op {
            case 0x0B: v = cpu.asl(v)
            case 0x4B: v = cpu.lsr(v)
            case 0x2B: v = cpu.rol(v)
            default:   v = cpu.ror(v)
            }
            apu.write8(addr, v)
            remaining -= 5
        case 0x1B, 0x5B, 0x3B, 0x7B:
            if remaining < 6 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpXAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            var v = apu.read8(addr)
            switch op {
            case 0x1B: v = cpu.asl(v)
            case 0x5B: v = cpu.lsr(v)
            case 0x3B: v = cpu.rol(v)
            default:   v = cpu.ror(v)
            }
            apu.write8(addr, v)
            remaining -= 6
        case 0x9F:
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.xcnA()
            remaining -= 2
        case 0xCF:
            if remaining < 9 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.mulYA()
            remaining -= 9
        case 0x9E:
            if cpu.x == 0 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            if remaining < 12 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.divYAByX()
            remaining -= 12
        case 0xDF:
            if remaining < 3 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.daaA()
            remaining -= 3
        case 0xBE:
            if remaining < 3 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.dasA()
            remaining -= 3
        case 0xE5:
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let addr = cpu.fetch16(apu)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = apu.read8(addr)
            cpu.updateNZ(cpu.a)
            remaining -= 4
        case 0xC5:
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let addr = cpu.fetch16(apu)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            apu.write8(addr, cpu.a)
            remaining -= 5
        case 0x05, 0x25, 0x45, 0x65, 0x85, 0xA5:
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let addr = cpu.fetch16(apu)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let m = apu.read8(addr)
            switch op {
            case 0x05: cpu.a |= m; cpu.updateNZ(cpu.a)
            case 0x25: cpu.a &= m; cpu.updateNZ(cpu.a)
            case 0x45: cpu.a ^= m; cpu.updateNZ(cpu.a)
            case 0x65: cpu.cmp(cpu.a, m)
            case 0x85: cpu.adc(m)
            default:   cpu.sbc(m)
            }
            remaining -= 4
        case 0x15, 0x35, 0x55, 0x75, 0x95, 0xB5:
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let addr = cpu.fetch16(apu) &+ u16(cpu.x)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let m = apu.read8(addr)
            switch op {
            case 0x15: cpu.a |= m; cpu.updateNZ(cpu.a)
            case 0x35: cpu.a &= m; cpu.updateNZ(cpu.a)
            case 0x55: cpu.a ^= m; cpu.updateNZ(cpu.a)
            case 0x75: cpu.cmp(cpu.a, m)
            case 0x95: cpu.adc(m)
            default:   cpu.sbc(m)
            }
            remaining -= 5
        case 0x16, 0x36, 0x56, 0x76, 0x96, 0xB6:
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let addr = cpu.fetch16(apu) &+ u16(cpu.y)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let m = apu.read8(addr)
            switch op {
            case 0x16: cpu.a |= m; cpu.updateNZ(cpu.a)
            case 0x36: cpu.a &= m; cpu.updateNZ(cpu.a)
            case 0x56: cpu.a ^= m; cpu.updateNZ(cpu.a)
            case 0x76: cpu.cmp(cpu.a, m)
            case 0x96: cpu.adc(m)
            default:   cpu.sbc(m)
            }
            remaining -= 5
        case 0x0C, 0x4C, 0x2C, 0x6C:
            if remaining < 6 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let addr = cpu.fetch16(apu)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            var v = apu.read8(addr)
            switch op {
            case 0x0C: v = cpu.asl(v)
            case 0x4C: v = cpu.lsr(v)
            case 0x2C: v = cpu.rol(v)
            default:   v = cpu.ror(v)
            }
            apu.write8(addr, v)
            remaining -= 6
        case 0xBA:
            if remaining < 3 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let addr = readDP16(cpu.fetch8(apu))
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = apu.read8(addr)
            cpu.updateNZ(cpu.a)
            remaining -= 3
        case 0xDA:
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = readDP16(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            apu.write8(addr, cpu.a)
            remaining -= 5
        case 0x02:
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let (addr, bit) = absBitOperand()
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            var v = apu.read8(addr)
            v |= (1 << bit)
            apu.write8(addr, v)
            remaining -= 4
        case 0x22:
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let (addr, bit) = absBitOperand()
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            var v = apu.read8(addr)
            v &= ~(1 << bit)
            apu.write8(addr, v)
            remaining -= 4
        case 0x42:
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let (addr, bit) = absBitOperand()
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            var v = apu.read8(addr)
            v ^= (1 << bit)
            apu.write8(addr, v)
            remaining -= 5
        case 0xAA:
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let (addr, bit) = absBitOperand()
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = apu.read8(addr)
            cpu.setFlag(SPC700.C, ((v >> bit) & 1) != 0)
            remaining -= 4
        case 0xCA:
            if remaining < 6 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let (addr, bit) = absBitOperand()
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            var v = apu.read8(addr)
            let c = cpu.flag(SPC700.C)
            v = c ? (v | (1 << bit)) : (v & ~(1 << bit))
            apu.write8(addr, v)
            remaining -= 6
        default:
            return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining)
        }
        insns += 1
    }

    return spc700jit_pack(nextPC: cpu.pc, remaining: remaining)
}
