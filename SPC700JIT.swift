import Foundation

final class SPC700JIT {

    typealias BlockFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32) -> UInt64

    private let mem = JITExecutableMemory()
    private let asm = X64Assembler()

    private var blocks: [u16: UnsafeRawPointer] = [:]

    var enabled: Bool = false

    @inline(__always) func reset() {
        blocks.removeAll(keepingCapacity: true)
        mem.reset()
    }

    @inline(__always) private func compileBlock(startPC: u16) -> UnsafeRawPointer? {
        var code: [UInt8] = []
        code += asm.movRCX_RDX()
        code += asm.movRDX(imm64: UInt64(startPC))
        code += asm.movRAX(imm64: UInt64(UInt(bitPattern: spc700jit_execHotBlock_ptr)))
        code += asm.callRAX()
        code += asm.ret()
        return mem.append(code)
    }

    @inline(__always) private func getBlock(pc: u16) -> UnsafeRawPointer? {
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

    @inline(__always) func run(cpu: SPC700, apu: APU, interpreter: SPC700Interpreter, cycles: Int) {
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

@inline(__always) private let spc700jit_execHotBlock_ptr: UnsafeMutableRawPointer = {
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
@inline(__always) func spc700jit_execHotBlock(
    _ cpuPtr: UnsafeMutableRawPointer?,
    _ apuPtr: UnsafeMutableRawPointer?,
    _ startPC: u16,
    _ cycles: Int32
) -> UInt64 {
    guard let cpuPtr, let apuPtr else { return spc700jit_pack(nextPC: 0xFFFF, remaining: Int(cycles)) }
    let cpu = Unmanaged<SPC700>.fromOpaque(cpuPtr).takeUnretainedValue()
    let apu = Unmanaged<APU>.fromOpaque(apuPtr).takeUnretainedValue()

    if cpu.halted || cpu.pc != startPC { return spc700jit_pack(nextPC: 0xFFFF, remaining: Int(cycles)) }

    var remaining = Int(cycles)
    let maxInsns = 32
    var insns = 0

    @inline(__always) func isIO(_ addr: u16) -> Bool { (addr & 0xFFF0) == 0x00F0 }
    @inline(__always) func dpAddr(_ off: u8) -> u16 { cpu.dpBase() | u16(off) }
    @inline(__always) func dpXAddr(_ off: u8) -> u16 { cpu.dpBase() | ((u16(off) &+ u16(cpu.x)) & 0xFF) }
    
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
    func indXAddr(_ dp: u8) -> u16 {
        let p = (u16(dp) &+ u16(cpu.x)) & 0x00FF
        let (loA, hiA) = (cpu.dpBase() | p, cpu.dpBase() | ((p &+ 1) & 0xFF))
        if isIO(loA) || isIO(hiA) { return 0xFFFF }
        return u16(apu.read8(loA)) | (u16(apu.read8(hiA)) << 8)
    }

    @inline(__always)
    func indYAddr(_ dp: u8) -> u16 {
        let (loA, hiA) = (cpu.dpBase() | u16(dp), cpu.dpBase() | ((u16(dp) &+ 1) & 0xFF))
        if isIO(loA) || isIO(hiA) { return 0xFFFF }
        return (u16(apu.read8(loA)) | (u16(apu.read8(hiA)) << 8)) &+ u16(cpu.y)
    }

    @inline(__always)
    func absBitOperand() -> (u16, Int) {
        let word = cpu.fetch16(apu)
        return (word & 0x1FFF, Int((word >> 13) & 0x07))
    }

    while remaining > 0, insns < maxInsns {
        let opPC = cpu.pc
        let op = cpu.fetch8(apu)
        switch op {
        case 0x00: remaining -= 2
        case 0xE8, 0xCD, 0x8D: // MOV immediate
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = cpu.fetch8(apu)
            if op == 0xE8 { cpu.a = v; cpu.updateNZ(v) }
            else if op == 0xCD { cpu.x = v; cpu.updateNZ(v) }
            else { cpu.y = v; cpu.updateNZ(v) }
            remaining -= 2
        case 0x7A, 0x9A, 0x5A, 0xBA, 0xDA: // 16-bit Word Ops
            let cost = (op == 0x5A) ? 4 : 5
            if remaining < cost { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let val = readDP16(cpu.fetch8(apu)); let ya = cpu.getYA()
            if op == 0x7A { // ADDW
                let sum = Int(ya) + Int(val)
                cpu.setFlag(SPC700.H, ((Int(ya) & 0x0FFF) + (Int(val) & 0x0FFF)) > 0x0FFF)
                cpu.setFlag(SPC700.V, (~(Int(ya) ^ Int(val)) & (Int(ya) ^ sum) & 0x8000) != 0)
                cpu.setFlag(SPC700.C, sum > 0xFFFF); cpu.setYA(u16(sum & 0xFFFF))
            } else if op == 0x9A { // SUBW
                let diff = Int(ya) - Int(val)
                cpu.setFlag(SPC700.H, (Int(ya) & 0x0FFF) >= (Int(val) & 0x0FFF))
                cpu.setFlag(SPC700.V, ((Int(ya) ^ Int(val)) & (Int(ya) ^ diff) & 0x8000) != 0)
                cpu.setFlag(SPC700.C, diff >= 0); cpu.setYA(u16(diff & 0xFFFF))
            } else if op == 0x5A { // CMPW
                let diff = Int(ya) - Int(val)
                cpu.setFlag(SPC700.C, diff >= 0); cpu.setFlag(SPC700.Z, (diff & 0xFFFF) == 0); cpu.setFlag(SPC700.N, (diff & 0x8000) != 0)
            } else if op == 0xBA { cpu.setYA(val) } // MOVW YA, dp
            else { writeDP16(cpu.fetch8(apu), ya) } // MOVW dp, YA
            remaining -= cost
        case 0x1F: // JMP [abs+X]
            if remaining < 6 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let target = 0xFF00 | u16(cpu.fetch8(apu)); cpu.push16(apu, cpu.pc); cpu.pc = target; remaining -= 6
            return spc700jit_pack(nextPC: cpu.pc, remaining: remaining)
        case 0x01, 0x11, 0x21, 0x31, 0x41, 0x51, 0x61, 0x71, 0x81, 0x91, 0xA1, 0xB1, 0xC1, 0xD1, 0xE1, 0xF1: // TCALL
            if remaining < 8 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let vec = 0xFFC0 | (u16(15 - (op >> 4)) << 1)
            let target = u16(apu.read8(vec)) | (u16(apu.read8(vec + 1)) << 8)
            cpu.push16(apu, cpu.pc); cpu.pc = target; remaining -= 8
            return spc700jit_pack(nextPC: cpu.pc, remaining: remaining)
        case 0x2F, 0xF0, 0xD0, 0x90, 0xB0, 0x10, 0x30, 0x50, 0x70: // Branches
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            let cond: Bool
            switch op {
            case 0x2F: cond = true
            case 0xF0: cond = cpu.flag(SPC700.Z)
            case 0xD0: cond = !cpu.flag(SPC700.Z)
            case 0x90: cond = !cpu.flag(SPC700.C)
            case 0xB0: cond = cpu.flag(SPC700.C)
            case 0x10: cond = !cpu.flag(SPC700.N)
            case 0x30: cond = cpu.flag(SPC700.N)
            case 0x50: cond = !cpu.flag(SPC700.V)
            default:   cond = cpu.flag(SPC700.V)
            }
            if cond {
                if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel)); remaining -= 4
                return spc700jit_pack(nextPC: cpu.pc, remaining: remaining)
            } else {
                if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 2
            }
        case 0x0E, 0x4E: // TSET1 / TCLR1
            if remaining < 6 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let addr = cpu.fetch16(apu); if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let m = apu.read8(addr); cpu.updateNZ(cpu.a &- m)
            apu.write8(addr, (op == 0x0E) ? (m | cpu.a) : (m & ~cpu.a)); remaining -= 6
        case 0xCF: // MUL YA
            if remaining < 9 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.mulYA(); remaining -= 9
        case 0x9E: // DIV YA, X
            if remaining < 12 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.divYAByX(); remaining -= 12
        case 0x02, 0x22, 0x42, 0xAA, 0xCA: // Absolute Bit Ops
            let cost = (op == 0xCA) ? 6 : (op == 0x42 ? 5 : 4)
            if remaining < cost { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let (addr, bit) = absBitOperand(); if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            var v = apu.read8(addr)
            if op == 0x02 { v |= (1 << bit); apu.write8(addr, v) }
            else if op == 0x22 { v &= ~(1 << bit); apu.write8(addr, v) }
            else if op == 0x42 { v ^= (1 << bit); apu.write8(addr, v) }
            else if op == 0xAA { cpu.setFlag(SPC700.C, ((v >> bit) & 1) != 0) }
            else { let c = cpu.flag(SPC700.C); v = c ? (v | (1 << bit)) : (v & ~(1 << bit)); apu.write8(addr, v) }
            remaining -= cost
        default: return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining)
        }
        insns += 1
    }
    return spc700jit_pack(nextPC: cpu.pc, remaining: remaining)
}
