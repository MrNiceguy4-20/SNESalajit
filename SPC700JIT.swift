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

        // JIT chain loop: run up to N blocks back-to-back if we get a valid nextPC hint.
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

                // 0xFFFF => bail-out; interpreter should resume.
                if nextPC == 0xFFFF { break }

                // Chaining hint: ensure CPU PC matches and keep going.
                cpu.pc = nextPC
                chain += 1
            }
        }

        if remaining > 0 {
            interpreter.step(cpu: cpu, apu: apu, cycles: remaining)
        }
    }
}

// MARK: - C-ABI trampoline used by JIT blocks

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

    // Limit the amount of work done in one trampoline call so the runner can chain blocks.
    let maxInsns = 32
    var insns = 0

    @inline(__always)
    func isIO(_ addr: u16) -> Bool {
        // APU IO window lives at $00F0-$00FF
        (addr & 0xFFF0) == 0x00F0
    }

    @inline(__always)
    func dpAddr(_ off: u8) -> u16 { cpu.dpBase() | u16(off) }

    @inline(__always)
    func dpXAddr(_ off: u8) -> u16 {
        // DP+X wraps within low 8 bits before adding DP base.
        let a = (u16(off) &+ u16(cpu.x)) & 0x00FF
        return cpu.dpBase() | a
    }

    @inline(__always)
    func indXAddr(_ dp: u8) -> u16 {
        // (dp+X): indexed-indirect pointer in DP, wrap within 0x00FF for pointer fetch.
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
        // Operand encoding: (bit<<13) | addr13
        let lo = u16(cpu.fetch8(apu))
        let hi = u16(cpu.fetch8(apu))
        let word = lo | (hi << 8)
        let bit = Int((word >> 13) & 0x07)
        let addr = u16(word & 0x1FFF)
        return (addr, bit)
    }
    @inline(__always)
    func indYAddr(_ dp: u8) -> u16 {
        // (dp)+Y: indirect pointer in DP then add Y (16-bit).
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

        case 0x00: // NOP
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            remaining -= 2

        case 0xE8: // MOV A,#imm
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = cpu.fetch8(apu)
            cpu.updateNZ(cpu.a)
            remaining -= 2

        case 0xCD: // MOV X,#imm
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.x = cpu.fetch8(apu)
            cpu.updateNZ(cpu.x)
            remaining -= 2

        case 0x8D: // MOV Y,#imm
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.y = cpu.fetch8(apu)
            cpu.updateNZ(cpu.y)
            remaining -= 2

        case 0xE4: // MOV A,dp
            if remaining < 3 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = apu.read8(addr)
            cpu.updateNZ(cpu.a)
            remaining -= 3

        case 0xC4: // MOV dp,A
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            apu.write8(addr, cpu.a)
            remaining -= 4

        case 0xBC: // INC A
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a &+= 1
            cpu.updateNZ(cpu.a)
            remaining -= 2

        case 0x9C: // DEC A
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a &-= 1
            cpu.updateNZ(cpu.a)
            remaining -= 2

        // ----- Phase 6.15 additions: control-flow branches (BRA/BEQ/BNE + BCC/BCS/BPL/BMI/BVC/BVS) -----
        // Branch timing: not taken = 2, taken = 4.
        case 0x2F: // BRA rel
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
            remaining -= 4

        case 0xF0: // BEQ rel
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            if cpu.flag(SPC700.Z) {
                if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 4
            } else {
                if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 2
            }

        case 0xD0: // BNE rel
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            if !cpu.flag(SPC700.Z) {
                if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 4
            } else {
                if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 2
            }



        case 0x90: // BCC rel
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            if !cpu.flag(SPC700.C) {
                if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 4
            } else {
                if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 2
            }

        case 0xB0: // BCS rel
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            if cpu.flag(SPC700.C) {
                if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 4
            } else {
                if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 2
            }

        case 0x10: // BPL rel
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            if !cpu.flag(SPC700.N) {
                if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 4
            } else {
                if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 2
            }

        case 0x30: // BMI rel
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            if cpu.flag(SPC700.N) {
                if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 4
            } else {
                if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 2
            }

        case 0x50: // BVC rel
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            if !cpu.flag(SPC700.V) {
                if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 4
            } else {
                if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 2
            }

        case 0x70: // BVS rel
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            if cpu.flag(SPC700.V) {
                if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 4
            } else {
                if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 2
            }
        case 0xF4: // MOV A,dp+X
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpXAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = apu.read8(addr)
            cpu.updateNZ(cpu.a)
            remaining -= 4

        case 0xD4: // MOV dp+X,A
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpXAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            apu.write8(addr, cpu.a)
            remaining -= 5

        case 0x28: // AND A,#imm
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a &= cpu.fetch8(apu)
            cpu.updateNZ(cpu.a)
            remaining -= 2

        case 0x08: // OR A,#imm
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a |= cpu.fetch8(apu)
            cpu.updateNZ(cpu.a)
            remaining -= 2

        case 0x48: // EOR A,#imm
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a ^= cpu.fetch8(apu)
            cpu.updateNZ(cpu.a)
            remaining -= 2

        case 0x68: // CMP A,#imm
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = cpu.fetch8(apu)
            cpu.cmp(cpu.a, v)
            remaining -= 2

        case 0x60: // CLRC
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.setFlag(SPC700.C, false)
            remaining -= 2

        case 0x80: // SETC
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.setFlag(SPC700.C, true)
            remaining -= 2

        case 0x20: // CLRP
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.setFlag(SPC700.P, false)
            remaining -= 2

        case 0x40: // SETP
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.setFlag(SPC700.P, true)
            remaining -= 2

        case 0xC0: // DI
            if remaining < 3 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.setFlag(SPC700.I, false)
            remaining -= 3

        case 0xA0: // EI
            if remaining < 3 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.setFlag(SPC700.I, true)
            remaining -= 3

        // DP / DP+X ALU hotset
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

        // (dp+X) / (dp)+Y indirect hotset
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

        // Stores + INC/DEC dp / dp+X
        case 0xCB: // MOV dp,Y
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            apu.write8(addr, cpu.y)
            remaining -= 4

        case 0xDB: // MOV dp+X,Y
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpXAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            apu.write8(addr, cpu.y)
            remaining -= 5

        case 0xD8: // MOV dp,X
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            apu.write8(addr, cpu.x)
            remaining -= 4

        case 0x8F: // MOV dp,#imm
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let imm = cpu.fetch8(apu)
            let off = cpu.fetch8(apu)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            apu.write8(addr, imm)
            remaining -= 5

        case 0xAB: // INC dp
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = apu.read8(addr) &+ 1
            apu.write8(addr, v)
            cpu.updateNZ(v)
            remaining -= 4

        case 0xBB: // INC dp+X
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpXAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = apu.read8(addr) &+ 1
            apu.write8(addr, v)
            cpu.updateNZ(v)
            remaining -= 5

        case 0x8B: // DEC dp
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = apu.read8(addr) &- 1
            apu.write8(addr, v)
            cpu.updateNZ(v)
            remaining -= 4

        case 0x9B: // DEC dp+X
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpXAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = apu.read8(addr) &- 1
            apu.write8(addr, v)
            cpu.updateNZ(v)
            remaining -= 5


        // ----- Phase 6.10 additions: ASL/LSR/ROL/ROR -----

        case 0x1C: // ASL A
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = cpu.asl(cpu.a)
            remaining -= 2

        case 0x5C: // LSR A
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = cpu.lsr(cpu.a)
            remaining -= 2

        case 0x3C: // ROL A
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = cpu.rol(cpu.a)
            remaining -= 2

        case 0x7C: // ROR A
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


        // ----- Phase 6.11 additions: XCN + MUL/DIV -----

        case 0x9F: // XCN A
            if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.xcnA()
            remaining -= 2

        case 0xCF: // MUL YA
            if remaining < 9 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.mulYA()
            remaining -= 9

        case 0x9E: // DIV YA,X
            // If X==0, bail to interpreter to preserve any edge behavior.
            if cpu.x == 0 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            if remaining < 12 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.divYAByX()
            remaining -= 12




        // ----- Phase 6.19 additions: DAA/DAS -----

        case 0xDF: // DAA
            if remaining < 3 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.daaA()
            remaining -= 3

        case 0xBE: // DAS
            if remaining < 3 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.dasA()
            remaining -= 3

        // ----- Phase 6.12 additions: Absolute-address hotset (MOV + ALU) -----

        case 0xE5: // MOV A,abs
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let addr = cpu.fetch16(apu)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = apu.read8(addr)
            cpu.updateNZ(cpu.a)
            remaining -= 4

        case 0xC5: // MOV abs,A
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let addr = cpu.fetch16(apu)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            apu.write8(addr, cpu.a)
            remaining -= 5

        case 0xE9: // MOV X,abs
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let addr = cpu.fetch16(apu)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.x = apu.read8(addr)
            cpu.updateNZ(cpu.x)
            remaining -= 4

        case 0xC9: // MOV abs,X
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let addr = cpu.fetch16(apu)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            apu.write8(addr, cpu.x)
            remaining -= 5

        case 0xF5: // MOV A,abs+X
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let baseAddr = cpu.fetch16(apu)
            let addr = baseAddr &+ u16(cpu.x)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = apu.read8(addr)
            cpu.updateNZ(cpu.a)
            remaining -= 5

        case 0xF6: // MOV A,abs+Y
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let baseAddr = cpu.fetch16(apu)
            let addr = baseAddr &+ u16(cpu.y)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = apu.read8(addr)
            cpu.updateNZ(cpu.a)
            remaining -= 5

        // ALU A,abs (OR/AND/EOR/CMP/ADC/SBC)
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


        // ----- Phase 6.14 additions: ALU A,abs+X + MOV Y,abs / MOV abs,Y -----

        case 0x15, 0x35, 0x55, 0x75, 0x95, 0xB5:
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let baseAddr = cpu.fetch16(apu)
            let addr = baseAddr &+ u16(cpu.x)
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

        case 0xEC: // MOV Y,abs
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let addr = cpu.fetch16(apu)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.y = apu.read8(addr)
            cpu.updateNZ(cpu.y)
            remaining -= 4

        case 0xCC: // MOV abs,Y
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let addr = cpu.fetch16(apu)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            apu.write8(addr, cpu.y)
            remaining -= 5


        // ----- Phase 6.16 additions: JMP/CALL/RET -----

        case 0x5F: // JMP abs
            if remaining < 3 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let addr = cpu.fetch16(apu)
            cpu.pc = addr
            remaining -= 3

        case 0x3F: // CALL abs
            if remaining < 8 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let addr = cpu.fetch16(apu)
            // Return address is the PC after operand fetch.
            cpu.push16(apu, cpu.pc)
            cpu.pc = addr
            remaining -= 8

        case 0x6F: // RET
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.pc = cpu.pop16(apu)
            remaining -= 5



        case 0x1F: // JMP (abs+X)
            // target = *(abs + X), little-endian
            if remaining < 6 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let baseAddr = cpu.fetch16(apu)
            let ptr = baseAddr &+ u16(cpu.x)
            let ptrHi = ptr &+ 1
            if isIO(ptr) || isIO(ptrHi) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let lo = u16(apu.read8(ptr))
            let hi = u16(apu.read8(ptrHi))
            cpu.pc = lo | (hi << 8)
            remaining -= 6

        case 0x7F: // RETI
            // Pop PSW then PC (matches interrupt push order used by interpreter/core).
            if remaining < 6 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.psw = cpu.pop8(apu)
            cpu.pc = cpu.pop16(apu)
            remaining -= 6

        case 0xBA: // MOVW YA,dp
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let (loAddr, hiAddr) = dpWordAddrs(off)
            if isIO(loAddr) || isIO(hiAddr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.setYA(readDP16(off))
            remaining -= 5

        case 0xDA: // MOVW dp,YA
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let (loAddr, hiAddr) = dpWordAddrs(off)
            if isIO(loAddr) || isIO(hiAddr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            writeDP16(off, cpu.getYA())
            remaining -= 5

        case 0x7A: // ADDW YA,dp
            if remaining < 6 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let (loAddr, hiAddr) = dpWordAddrs(off)
            if isIO(loAddr) || isIO(hiAddr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let m = readDP16(off)
            let a = cpu.getYA()
            let sum = u32(a) + u32(m)
            let res = u16(truncatingIfNeeded: sum)
            cpu.setFlag(SPC700.C, sum > 0xFFFF)
            cpu.setFlag(SPC700.Z, res == 0)
            cpu.setFlag(SPC700.N, (res & 0x8000) != 0)
            let ov = (~(u32(a) ^ u32(m)) & (u32(a) ^ u32(res)) & 0x8000) != 0
            cpu.setFlag(SPC700.V, ov)
            let hc = ((u32(a & 0x0FFF) + u32(m & 0x0FFF)) > 0x0FFF)
            cpu.setFlag(SPC700.H, hc)
            cpu.setYA(res)
            remaining -= 6

        case 0x9A: // SUBW YA,dp
            if remaining < 6 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let (loAddr, hiAddr) = dpWordAddrs(off)
            if isIO(loAddr) || isIO(hiAddr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let m = readDP16(off)
            let a = cpu.getYA()
            let diff32 = i32(bitPattern: u32(a)) - i32(bitPattern: u32(m))
            let res = u16(truncatingIfNeeded: diff32)
            cpu.setFlag(SPC700.C, a >= m)
            cpu.setFlag(SPC700.Z, res == 0)
            cpu.setFlag(SPC700.N, (res & 0x8000) != 0)
            let ov = ((u32(a) ^ u32(m)) & (u32(a) ^ u32(res)) & 0x8000) != 0
            cpu.setFlag(SPC700.V, ov)
            let hb = (a & 0x0FFF) >= (m & 0x0FFF)
            cpu.setFlag(SPC700.H, hb)
            cpu.setYA(res)
            remaining -= 6

        case 0x3A: // INCW dp
            if remaining < 6 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let (loAddr, hiAddr) = dpWordAddrs(off)
            if isIO(loAddr) || isIO(hiAddr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = readDP16(off) &+ 1
            writeDP16(off, v)
            cpu.setFlag(SPC700.Z, v == 0)
            cpu.setFlag(SPC700.N, (v & 0x8000) != 0)
            remaining -= 6

        case 0x1A: // DECW dp
            if remaining < 6 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let (loAddr, hiAddr) = dpWordAddrs(off)
            if isIO(loAddr) || isIO(hiAddr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = readDP16(off) &- 1
            writeDP16(off, v)
            cpu.setFlag(SPC700.Z, v == 0)
            cpu.setFlag(SPC700.N, (v & 0x8000) != 0)
            remaining -= 6


        // ----- Phase 6.21 additions: Stack ops (PUSH/POP A/X/Y/PSW) -----

        case 0x2D: // PUSH A
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.push8(apu, cpu.a)
            remaining -= 4

        case 0x4D: // PUSH X
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.push8(apu, cpu.x)
            remaining -= 4

        case 0x6D: // PUSH Y
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.push8(apu, cpu.y)
            remaining -= 4

        case 0x0D: // PUSH PSW
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.push8(apu, cpu.psw)
            remaining -= 4

        case 0xAE: // POP A
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.a = cpu.pop8(apu)
            cpu.updateNZ(cpu.a)
            remaining -= 4

        case 0xCE: // POP X
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.x = cpu.pop8(apu)
            cpu.updateNZ(cpu.x)
            remaining -= 4

        case 0xEE: // POP Y
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.y = cpu.pop8(apu)
            cpu.updateNZ(cpu.y)
            remaining -= 4

        case 0x8E: // POP PSW
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            cpu.psw = cpu.pop8(apu)
            remaining -= 4


        // ----- Phase 6.22 additions: PCALL + TCALL -----

        case 0x4F: // PCALL dp
            if remaining < 6 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let dp = cpu.fetch8(apu)
            cpu.push16(apu, cpu.pc)
            cpu.pc = 0xFF00 | u16(dp)
            remaining -= 6

        case 0x01, 0x11, 0x21, 0x31, 0x41, 0x51, 0x61, 0x71,
             0x81, 0x91, 0xA1, 0xB1, 0xC1, 0xD1, 0xE1, 0xF1: // TCALL n
            if remaining < 8 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let n = Int((op >> 4) & 0x0F)
            let vec = u16(0xFFC0 + (n << 1))
            let lo = u16(apu.read8(vec))
            let hi = u16(apu.read8(vec &+ 1))
            let target = lo | (hi << 8)
            cpu.push16(apu, cpu.pc)
            cpu.pc = target
            remaining -= 8


        // ----- Phase 6.23 additions: SET1/CLR1 dp.bit + safe bail for BRK/SLEEP/STOP -----

        // SET1 dp.bit (bit index encoded in opcode)
        case 0x02, 0x22, 0x42, 0x62, 0x82, 0xA2, 0xC2, 0xE2:
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let bit = Int((op >> 5) & 0x07)
            let mask: u8 = u8(1 << bit)
            let v = apu.read8(addr) | mask
            apu.write8(addr, v)
            remaining -= 4

        // CLR1 dp.bit (bit index encoded in opcode)
        case 0x12, 0x32, 0x52, 0x72, 0x92, 0xB2, 0xD2, 0xF2:
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let off = cpu.fetch8(apu)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let bit = Int((op >> 5) & 0x07)
            let mask: u8 = u8(1 << bit)
            let v = apu.read8(addr) & ~mask
            apu.write8(addr, v)
            remaining -= 4

        case 0x0F: // BRK
            cpu.pc = opPC
            return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining)

        case 0xEF: // SLEEP
            cpu.pc = opPC
            return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining)

        case 0xFF: // STOP
            cpu.pc = opPC
            return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining)


        // ----- Phase 6.24 additions: TSET1/TCLR1 abs -----

        case 0x0E: // TSET1 abs
            if remaining < 6 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let addr = cpu.fetch16(apu)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let m = apu.read8(addr)
            cpu.setFlag(SPC700.Z, (cpu.a & m) == 0)
            apu.write8(addr, m | cpu.a)
            remaining -= 6

        case 0x4E: // TCLR1 abs
            if remaining < 6 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let addr = cpu.fetch16(apu)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let m = apu.read8(addr)
            cpu.setFlag(SPC700.Z, (cpu.a & m) == 0)
            apu.write8(addr, m & ~cpu.a)
            remaining -= 6


        // ----- Phase 6.25 additions: BBC/BBS dp.bit,rel -----
        // Timing: not taken = 5 cycles, taken = 7 cycles.

        // BBS dp.bit,rel (branch if bit set)
        case  0x83, 0xA3, 0xC3, 0xE3:
            // Fetch dp + rel regardless; decide branch after testing bit.
            let off = cpu.fetch8(apu)
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let bit = Int((op >> 5) & 0x07)
            let mask: u8 = u8(1 << bit)
            let v = apu.read8(addr)
            if (v & mask) != 0 {
                if remaining < 7 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 7
            } else {
                if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 5
            }

        // BBC dp.bit,rel (branch if bit clear)
        case  0x93, 0xB3, 0xD3, 0xF3:
            let off = cpu.fetch8(apu)
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let bit = Int((op >> 5) & 0x07)
            let mask: u8 = u8(1 << bit)
            let v = apu.read8(addr)
            if (v & mask) == 0 {
                if remaining < 7 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 7
            } else {
                if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 5
            }

        case 0x2E: // CBNE dp,rel
            let off = cpu.fetch8(apu)
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = apu.read8(addr)
            if cpu.a != v {
                if remaining < 7 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 7
            } else {
                if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 5
            }

        case 0xDE: // CBNE dp+X,rel
            let off = cpu.fetch8(apu)
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            let addr = dpXAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = apu.read8(addr)
            if cpu.a != v {
                if remaining < 7 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 7
            } else {
                if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 5
            }

        case 0x6E: // DBNZ dp,rel
            let off = cpu.fetch8(apu)
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            var v = apu.read8(addr)
            v &-= 1
            apu.write8(addr, v)
            if v != 0 {
                if remaining < 7 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 7
            } else {
                if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 5
            }

        case 0xFE: // DBNZ Y,rel
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            cpu.y &-= 1
            cpu.updateNZ(cpu.y)
            if cpu.y != 0 {
                if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 4
            } else {
                if remaining < 2 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 2
            }

        // Direct-page bit test and branch: BBC/BBS dp.bit,rel
        case 0x03, 0x23, 0x43, 0x63, 0x13, 0x33, 0x53, 0x73:
            let off = cpu.fetch8(apu)
            let rel = Int(Int8(bitPattern: cpu.fetch8(apu)))
            let bit = Int((op >> 5) & 0x07)
            let addr = dpAddr(off)
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = apu.read8(addr)
            let bitSet = ((v >> bit) & 1) != 0
            let isBBS = (op & 0x10) != 0
            let take = isBBS ? bitSet : !bitSet
            if take {
                if remaining < 7 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                cpu.pc = u16(truncatingIfNeeded: Int32(cpu.pc) + Int32(rel))
                remaining -= 7
            } else {
                if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
                remaining -= 5
            }

        case 0x0A, 0x2A, 0x4A, 0x6A, 0x8A: // OR1/AND1/EOR1 C,mem.bit variants
            let (addr, bit) = absBitOperand()
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = apu.read8(addr)
            let b = ((v >> bit) & 1) != 0
            let inv = (op == 0x2A || op == 0x6A)
            let bitVal = inv ? !b : b

            // Match interpreter cycle costs:
            // OR1  (0x0A/0x2A) = 5
            // AND1 (0x4A/0x6A) = 4
            // EOR1 (0x8A)      = 5
            let needed: Int = (op == 0x4A || op == 0x6A) ? 4 : 5
            if remaining < needed { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }

            if op == 0x0A || op == 0x2A {
                let c = cpu.flag(SPC700.C) || bitVal
                cpu.setFlag(SPC700.C, c)
            } else if op == 0x4A || op == 0x6A {
                let c = cpu.flag(SPC700.C) && bitVal
                cpu.setFlag(SPC700.C, c)
            } else { // 0x8A
                let c = cpu.flag(SPC700.C) != bitVal
                cpu.setFlag(SPC700.C, c)
            }
            remaining -= needed

        case 0xEA: // NOT1 mem.bit
            if remaining < 5 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let (addr, bit) = absBitOperand()
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            var v = apu.read8(addr)
            v ^= (1 << bit)
            apu.write8(addr, v)
            remaining -= 5

        case 0xAA: // MOV1 C,mem.bit
            if remaining < 4 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let (addr, bit) = absBitOperand()
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let v = apu.read8(addr)
            cpu.setFlag(SPC700.C, ((v >> bit) & 1) != 0)
            remaining -= 4

        case 0xCA: // MOV1 mem.bit,C
            if remaining < 6 { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            let (addr, bit) = absBitOperand()
            if isIO(addr) { cpu.pc = opPC; return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining) }
            var v = apu.read8(addr)
            let c = cpu.flag(SPC700.C)
            v = c ? (v | (1 << bit)) : (v & ~(1 << bit))
            apu.write8(addr, v)
            remaining -= 6

                default:
                    cpu.pc = opPC
                    return spc700jit_pack(nextPC: 0xFFFF, remaining: remaining)
                }

                insns &+= 1
            }

            // Clean block end: provide chaining hint.
            return spc700jit_pack(nextPC: cpu.pc, remaining: remaining)
        }

