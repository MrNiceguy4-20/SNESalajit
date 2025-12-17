import Foundation

/// Phase 1: minimal opcode decode/execute for bring-up.
/// Returns an approximate cycle count for the executed instruction.
///
/// IMPORTANT:
/// - Do not mutate cpu.r directly (outside of CPU65816).
/// - Use CPU65816 helpers to read/write/fetch/stack/flags.
enum CPUInstructionTables {

    @inline(__always)
    static func execute(opcode: u8, cpu: CPU65816, bus: Bus) -> Int {
        switch opcode {

        // MARK: - Flag/control

        case 0xEA: // NOP
            return 2

        case 0x42: // WDM (2-byte "NOP")
            _ = cpu.fetch8()
            return 2

        case 0x78: // SEI
            cpu.setFlag(.irqDis, true)
            return 2

        case 0x58: // CLI
            cpu.setFlag(.irqDis, false)
            return 2

        case 0x18: // CLC
            cpu.setFlag(.carry, false)
            return 2

        case 0x38: // SEC
            cpu.setFlag(.carry, true)
            return 2

        case 0xD8: // CLD
            cpu.setFlag(.decimal, false)
            return 2

        case 0xF8: // SED
            cpu.setFlag(.decimal, true)
            return 2

        case 0xC2: // REP #imm
            let m = cpu.fetch8()
            cpu.rep(m)
            return 3

        case 0xE2: // SEP #imm
            let m = cpu.fetch8()
            cpu.sep(m)
            return 3

        case 0xFB: // XCE
            cpu.xce()
            return 2

        // MARK: - Interrupts

        case 0x00: // BRK
            // BRK is two bytes; skip signature byte.
            _ = cpu.fetch8()
            cpu.serviceInterrupt(.brk)
            return 7

        case 0x40: // RTI
            let p = cpu.pull8()
            cpu.setPFromPull(p)
            let pcl = cpu.pull8()
            let pch = cpu.pull8()
            cpu.setPC(make16(pcl, pch))
            // Phase 1: assume PB unchanged in emulation.
            return 6

        // MARK: - Stack

        case 0x48: // PHA
            if cpu.aIs8() { cpu.push8(cpu.a8()) }
            else { cpu.push16(cpu.r.a) }
            return 3

        case 0x68: // PLA
            if cpu.aIs8() {
                let v = cpu.pull8()
                cpu.setA8(v)
                cpu.updateNZ8(v)
            } else {
                let v = cpu.pull16()
                cpu.setA(v)
                cpu.updateNZ16(v)
            }
            return 4

        case 0xDA: // PHX
            if cpu.xIs8() { cpu.push8(cpu.x8()) }
            else { cpu.push16(cpu.r.x) }
            return 3

        case 0xFA: // PLX
            if cpu.xIs8() {
                let v = cpu.pull8()
                cpu.setX8(v)
                cpu.updateNZ8(v)
            } else {
                let v = cpu.pull16()
                cpu.setX(v)
                cpu.updateNZ16(v)
            }
            return 4

        case 0x5A: // PHY
            if cpu.xIs8() { cpu.push8(cpu.y8()) }
            else { cpu.push16(cpu.r.y) }
            return 3

        case 0x7A: // PLY
            if cpu.xIs8() {
                let v = cpu.pull8()
                cpu.setY8(v)
                cpu.updateNZ8(v)
            } else {
                let v = cpu.pull16()
                cpu.setY(v)
                cpu.updateNZ16(v)
            }
            return 4

        case 0x08: // PHP
            cpu.push8(cpu.pForPush(brk: false))
            return 3

        case 0x28: // PLP
            let p = cpu.pull8()
            cpu.setPFromPull(p)
            return 4

        // MARK: - Transfers

        case 0xAA: // TAX
            if cpu.xIs8() {
                let v = cpu.a8()
                cpu.setX8(v)
                cpu.updateNZ8(v)
            } else {
                let v = cpu.aIs8() ? u16(cpu.a8()) : cpu.r.a
                cpu.setX(v)
                cpu.updateNZ16(v)
            }
            return 2

        case 0x8A: // TXA
            if cpu.aIs8() {
                let v = cpu.x8()
                cpu.setA8(v)
                cpu.updateNZ8(v)
            } else {
                let v = cpu.xIs8() ? u16(cpu.x8()) : cpu.r.x
                cpu.setA(v)
                cpu.updateNZ16(v)
            }
            return 2

        case 0xA8: // TAY
            if cpu.xIs8() {
                let v = cpu.a8()
                cpu.setY8(v)
                cpu.updateNZ8(v)
            } else {
                let v = cpu.aIs8() ? u16(cpu.a8()) : cpu.r.a
                cpu.setY(v)
                cpu.updateNZ16(v)
            }
            return 2

        case 0x98: // TYA
            if cpu.aIs8() {
                let v = cpu.y8()
                cpu.setA8(v)
                cpu.updateNZ8(v)
            } else {
                let v = cpu.xIs8() ? u16(cpu.y8()) : cpu.r.y
                cpu.setA(v)
                cpu.updateNZ16(v)
            }
            return 2

        case 0xBA: // TSX
            if cpu.xIs8() {
                let v = u8(truncatingIfNeeded: cpu.r.sp)
                cpu.setX8(v)
                cpu.updateNZ8(v)
            } else {
                cpu.setX(cpu.r.sp)
                cpu.updateNZ16(cpu.r.sp)
            }
            return 2

        case 0x9A: // TXS
            if cpu.xIs8() {
                cpu.setSPLo(cpu.x8())
            } else {
                cpu.setSP(cpu.r.x)
            }
            return 2

        // MARK: - Loads

        case 0xA9: // LDA #imm
            if cpu.aIs8() {
                let v = CPUAddressing.imm8(cpu: cpu, bus: bus)
                cpu.setA8(v)
                cpu.updateNZ8(v)
                return 2
            } else {
                let v = CPUAddressing.imm16(cpu: cpu, bus: bus)
                cpu.setA(v)
                cpu.updateNZ16(v)
                return 3
            }

        case 0xA2: // LDX #imm
            if cpu.xIs8() {
                let v = CPUAddressing.imm8(cpu: cpu, bus: bus)
                cpu.setX8(v)
                cpu.updateNZ8(v)
                return 2
            } else {
                let v = CPUAddressing.imm16(cpu: cpu, bus: bus)
                cpu.setX(v)
                cpu.updateNZ16(v)
                return 3
            }

        case 0xA0: // LDY #imm
            if cpu.xIs8() {
                let v = CPUAddressing.imm8(cpu: cpu, bus: bus)
                cpu.setY8(v)
                cpu.updateNZ8(v)
                return 2
            } else {
                let v = CPUAddressing.imm16(cpu: cpu, bus: bus)
                cpu.setY(v)
                cpu.updateNZ16(v)
                return 3
            }

        case 0xA5: // LDA dp
            return lda_mem(cpu: cpu, addr: CPUAddressing.dp(cpu: cpu, bus: bus), bank: 0x00, cycles: 3)

        case 0xB5: // LDA dp,X
            return lda_mem(cpu: cpu, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), bank: 0x00, cycles: 4)

        case 0xAD: // LDA abs
            return lda_mem(cpu: cpu, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)

        case 0xBD: // LDA abs,X
            return lda_mem(cpu: cpu, addr: CPUAddressing.absX(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)

        case 0xB9: // LDA abs,Y
            return lda_mem(cpu: cpu, addr: CPUAddressing.absY(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)

        case 0xA6: // LDX dp
            return ldx_mem(cpu: cpu, addr: CPUAddressing.dp(cpu: cpu, bus: bus), bank: 0x00, cycles: 3)

        case 0xB6: // LDX dp,Y
            return ldx_mem(cpu: cpu, addr: CPUAddressing.dpY(cpu: cpu, bus: bus), bank: 0x00, cycles: 4)

        case 0xAE: // LDX abs
            return ldx_mem(cpu: cpu, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)

        case 0xBE: // LDX abs,Y
            return ldx_mem(cpu: cpu, addr: CPUAddressing.absY(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)

        case 0xA4: // LDY dp
            return ldy_mem(cpu: cpu, addr: CPUAddressing.dp(cpu: cpu, bus: bus), bank: 0x00, cycles: 3)

        case 0xB4: // LDY dp,X
            return ldy_mem(cpu: cpu, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), bank: 0x00, cycles: 4)

        case 0xAC: // LDY abs
            return ldy_mem(cpu: cpu, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)

        case 0xBC: // LDY abs,X
            return ldy_mem(cpu: cpu, addr: CPUAddressing.absX(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)

        // MARK: - Stores

        case 0x85: // STA dp
            return sta_mem(cpu: cpu, addr: CPUAddressing.dp(cpu: cpu, bus: bus), bank: 0x00, cycles: 3)

        case 0x95: // STA dp,X
            return sta_mem(cpu: cpu, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), bank: 0x00, cycles: 4)

        case 0x8D: // STA abs
            return sta_mem(cpu: cpu, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)

        case 0x9D: // STA abs,X
            return sta_mem(cpu: cpu, addr: CPUAddressing.absX(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 5)

        case 0x99: // STA abs,Y
            return sta_mem(cpu: cpu, addr: CPUAddressing.absY(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 5)

        case 0x86: // STX dp
            return stx_mem(cpu: cpu, addr: CPUAddressing.dp(cpu: cpu, bus: bus), bank: 0x00, cycles: 3)

        case 0x8E: // STX abs
            return stx_mem(cpu: cpu, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)

        case 0x84: // STY dp
            return sty_mem(cpu: cpu, addr: CPUAddressing.dp(cpu: cpu, bus: bus), bank: 0x00, cycles: 3)

        case 0x8C: // STY abs
            return sty_mem(cpu: cpu, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)

        // MARK: - Flow control

        case 0x4C: // JMP abs
            let addr = CPUAddressing.abs16(cpu: cpu, bus: bus)
            cpu.setPC(addr)
            return 3

        case 0x6C: // JMP (abs)
            let addr = CPUAddressing.absIndirect(cpu: cpu, bus: bus)
            cpu.setPC(addr)
            return 5

        case 0x20: // JSR abs
            let target = CPUAddressing.abs16(cpu: cpu, bus: bus)
            // Push (PC-1) high then low.
            let ret = cpu.r.pc &- 1
            cpu.push16(ret)
            cpu.setPC(target)
            return 6

        case 0x60: // RTS
            let ret = cpu.pull16()
            cpu.setPC(ret &+ 1)
            return 6

        case 0x80: // BRA rel
            let rel = CPUAddressing.rel8(cpu: cpu, bus: bus)
            cpu.setPC(cpu.r.pc &+ u16(bitPattern: Int16(rel)))
            return 3

        case 0xF0: // BEQ
            return branch(cpu: cpu, bus: bus, cond: cpu.flag(.zero))

        case 0xD0: // BNE
            return branch(cpu: cpu, bus: bus, cond: !cpu.flag(.zero))

        case 0x10: // BPL
            return branch(cpu: cpu, bus: bus, cond: !cpu.flag(.negative))

        case 0x30: // BMI
            return branch(cpu: cpu, bus: bus, cond: cpu.flag(.negative))

        case 0x90: // BCC
            return branch(cpu: cpu, bus: bus, cond: !cpu.flag(.carry))

        case 0xB0: // BCS
            return branch(cpu: cpu, bus: bus, cond: cpu.flag(.carry))

        case 0x50: // BVC
            return branch(cpu: cpu, bus: bus, cond: !cpu.flag(.overflow))

        case 0x70: // BVS
            return branch(cpu: cpu, bus: bus, cond: cpu.flag(.overflow))

        default:
            // Unknown/unimplemented opcode: treat as NOP for now.
            // (Keeps emulator running while we expand the table.)
            return 2
        }
    }

    // MARK: - Helpers

    @inline(__always)
    private static func branch(cpu: CPU65816, bus: Bus, cond: Bool) -> Int {
        let rel = CPUAddressing.rel8(cpu: cpu, bus: bus)
        if cond {
            cpu.setPC(cpu.r.pc &+ u16(bitPattern: Int16(rel)))
            return 3
        } else {
            return 2
        }
    }

    @inline(__always)
    private static func lda_mem(cpu: CPU65816, addr: u16, bank: u8, cycles: Int) -> Int {
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr)
            cpu.setA8(v)
            cpu.updateNZ8(v)
        } else {
            let v = cpu.read16(bank, addr)
            cpu.setA(v)
            cpu.updateNZ16(v)
        }
        return cycles
    }

    @inline(__always)
    private static func ldx_mem(cpu: CPU65816, addr: u16, bank: u8, cycles: Int) -> Int {
        if cpu.xIs8() {
            let v = cpu.read8(bank, addr)
            cpu.setX8(v)
            cpu.updateNZ8(v)
        } else {
            let v = cpu.read16(bank, addr)
            cpu.setX(v)
            cpu.updateNZ16(v)
        }
        return cycles
    }

    @inline(__always)
    private static func ldy_mem(cpu: CPU65816, addr: u16, bank: u8, cycles: Int) -> Int {
        if cpu.xIs8() {
            let v = cpu.read8(bank, addr)
            cpu.setY8(v)
            cpu.updateNZ8(v)
        } else {
            let v = cpu.read16(bank, addr)
            cpu.setY(v)
            cpu.updateNZ16(v)
        }
        return cycles
    }

    @inline(__always)
    private static func sta_mem(cpu: CPU65816, addr: u16, bank: u8, cycles: Int) -> Int {
        if cpu.aIs8() {
            cpu.write8(bank, addr, cpu.a8())
        } else {
            let v = cpu.r.a
            cpu.write8(bank, addr, lo8(v))
            cpu.write8(bank, addr &+ 1, hi8(v))
        }
        return cycles
    }

    @inline(__always)
    private static func stx_mem(cpu: CPU65816, addr: u16, bank: u8, cycles: Int) -> Int {
        if cpu.xIs8() {
            cpu.write8(bank, addr, cpu.x8())
        } else {
            let v = cpu.r.x
            cpu.write8(bank, addr, lo8(v))
            cpu.write8(bank, addr &+ 1, hi8(v))
        }
        return cycles
    }

    @inline(__always)
    private static func sty_mem(cpu: CPU65816, addr: u16, bank: u8, cycles: Int) -> Int {
        if cpu.xIs8() {
            cpu.write8(bank, addr, cpu.y8())
        } else {
            let v = cpu.r.y
            cpu.write8(bank, addr, lo8(v))
            cpu.write8(bank, addr &+ 1, hi8(v))
        }
        return cycles
    }
}
