import Foundation

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



        case 0x5B: // TCD
            cpu.setDP(cpu.r.a)
            cpu.updateNZ16(cpu.r.dp)
            return 2

        case 0x1B: // TCS
            let value = cpu.r.a
            if cpu.r.emulationMode {
                cpu.setSP(0x0100 | (value & 0x00FF))
            } else {
                cpu.setSP(value)
            }
            cpu.updateNZ16(value)
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

        // MARK: - Increment/Decrement

        case 0xE8: // INX
            if cpu.xIs8() {
                let v = cpu.x8() &+ 1
                cpu.setX8(v)
                cpu.updateNZ8(v)
            } else {
                let v = cpu.r.x &+ 1
                cpu.setX(v)
                cpu.updateNZ16(v)
            }
            return 2

        case 0xC8: // INY
            if cpu.xIs8() {
                let v = cpu.y8() &+ 1
                cpu.setY8(v)
                cpu.updateNZ8(v)
            } else {
                let v = cpu.r.y &+ 1
                cpu.setY(v)
                cpu.updateNZ16(v)
            }
            return 2

        case 0xCA: // DEX
            if cpu.xIs8() {
                let v = cpu.x8() &- 1
                cpu.setX8(v)
                cpu.updateNZ8(v)
            } else {
                let v = cpu.r.x &- 1
                cpu.setX(v)
                cpu.updateNZ16(v)
            }
            return 2

        case 0x88: // DEY
            if cpu.xIs8() {
                let v = cpu.y8() &- 1
                cpu.setY8(v)
                cpu.updateNZ8(v)
            } else {
                let v = cpu.r.y &- 1
                cpu.setY(v)
                cpu.updateNZ16(v)
            }
            return 2

        case 0x1A: // INC A
            if cpu.aIs8() {
                let v = cpu.a8() &+ 1
                cpu.setA8(v)
                cpu.updateNZ8(v)
            } else {
                let v = cpu.r.a &+ 1
                cpu.setA(v)
                cpu.updateNZ16(v)
            }
            return 2

        case 0x3A: // DEC A
            if cpu.aIs8() {
                let v = cpu.a8() &- 1
                cpu.setA8(v)
                cpu.updateNZ8(v)
            } else {
                let v = cpu.r.a &- 1
                cpu.setA(v)
                cpu.updateNZ16(v)
            }
            return 2



        case 0x0A: // ASL A
            if cpu.aIs8() {
                let v = cpu.a8()
                let res = v &<< 1
                cpu.setA8(res)
                cpu.setFlag(.carry, (v & 0x80) != 0)
                cpu.updateNZ8(res)
            } else {
                let v = cpu.r.a
                let res = v &<< 1
                cpu.setA(res)
                cpu.setFlag(.carry, (v & 0x8000) != 0)
                cpu.updateNZ16(res)
            }
            return 2

        case 0x2A: // ROL A
            if cpu.aIs8() {
                let v = cpu.a8()
                let carryIn: u8 = cpu.flag(.carry) ? 1 : 0
                let res = (v &<< 1) | carryIn
                cpu.setA8(res)
                cpu.setFlag(.carry, (v & 0x80) != 0)
                cpu.updateNZ8(res)
            } else {
                let v = cpu.r.a
                let carryIn: u16 = cpu.flag(.carry) ? 1 : 0
                let res = (v &<< 1) | carryIn
                cpu.setA(res)
                cpu.setFlag(.carry, (v & 0x8000) != 0)
                cpu.updateNZ16(res)
            }
            return 2

        case 0x4A: // LSR A
            if cpu.aIs8() {
                let v = cpu.a8()
                let res = v >> 1
                cpu.setA8(res)
                cpu.setFlag(.carry, (v & 0x01) != 0)
                cpu.updateNZ8(res)
            } else {
                let v = cpu.r.a
                let res = v >> 1
                cpu.setA(res)
                cpu.setFlag(.carry, (v & 0x0001) != 0)
                cpu.updateNZ16(res)
            }
            return 2

        case 0x6A: // ROR A
            if cpu.aIs8() {
                let v = cpu.a8()
                let carryIn: u8 = cpu.flag(.carry) ? 0x80 : 0
                let res = (v >> 1) | carryIn
                cpu.setA8(res)
                cpu.setFlag(.carry, (v & 0x01) != 0)
                cpu.updateNZ8(res)
            } else {
                let v = cpu.r.a
                let carryIn: u16 = cpu.flag(.carry) ? 0x8000 : 0
                let res = (v >> 1) | carryIn
                cpu.setA(res)
                cpu.setFlag(.carry, (v & 0x0001) != 0)
                cpu.updateNZ16(res)
            }
            return 2


        // MARK: - ALU (logic + arithmetic)

        case 0x09: // ORA #imm
            if cpu.aIs8() {
                let v = CPUAddressing.imm8(cpu: cpu, bus: bus)
                ora(cpu: cpu, value8: v, value16: 0)
                return 2
            } else {
                let v = CPUAddressing.imm16(cpu: cpu, bus: bus)
                ora(cpu: cpu, value8: 0, value16: v)
                return 3
            }

        case 0x05: // ORA dp
            return ora_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 3)

        case 0x15: // ORA dp,X
            return ora_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 4)

        case 0x0D: // ORA abs
            return ora_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 4)

        case 0x1D: // ORA abs,X
            return ora_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 4)

        case 0x19: // ORA abs,Y
            return ora_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absY(cpu: cpu, bus: bus), cycles: 4)

        case 0x29: // AND #imm
            if cpu.aIs8() {
                let v = CPUAddressing.imm8(cpu: cpu, bus: bus)
                and(cpu: cpu, value8: v, value16: 0)
                return 2
            } else {
                let v = CPUAddressing.imm16(cpu: cpu, bus: bus)
                and(cpu: cpu, value8: 0, value16: v)
                return 3
            }

        case 0x25: // AND dp
            return and_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 3)

        case 0x35: // AND dp,X
            return and_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 4)

        case 0x2D: // AND abs
            return and_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 4)

        case 0x3D: // AND abs,X
            return and_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 4)

        case 0x39: // AND abs,Y
            return and_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absY(cpu: cpu, bus: bus), cycles: 4)

        case 0x49: // EOR #imm
            if cpu.aIs8() {
                let v = CPUAddressing.imm8(cpu: cpu, bus: bus)
                eor(cpu: cpu, value8: v, value16: 0)
                return 2
            } else {
                let v = CPUAddressing.imm16(cpu: cpu, bus: bus)
                eor(cpu: cpu, value8: 0, value16: v)
                return 3
            }

        case 0x45: // EOR dp
            return eor_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 3)

        case 0x55: // EOR dp,X
            return eor_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 4)

        case 0x4D: // EOR abs
            return eor_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 4)

        case 0x5D: // EOR abs,X
            return eor_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 4)

        case 0x59: // EOR abs,Y
            return eor_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absY(cpu: cpu, bus: bus), cycles: 4)

        case 0x69: // ADC #imm
            if cpu.aIs8() {
                let v = CPUAddressing.imm8(cpu: cpu, bus: bus)
                adc(cpu: cpu, value8: v, value16: 0)
                return 2
            } else {
                let v = CPUAddressing.imm16(cpu: cpu, bus: bus)
                adc(cpu: cpu, value8: 0, value16: v)
                return 3
            }

        case 0x65: // ADC dp
            return adc_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 3)

        case 0x75: // ADC dp,X
            return adc_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 4)

        case 0x6D: // ADC abs
            return adc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 4)

        case 0x7D: // ADC abs,X
            return adc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 4)

        case 0x79: // ADC abs,Y
            return adc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absY(cpu: cpu, bus: bus), cycles: 4)

        case 0xE9, 0xEB: // SBC #imm
            if cpu.aIs8() {
                let v = CPUAddressing.imm8(cpu: cpu, bus: bus)
                sbc(cpu: cpu, value8: v, value16: 0)
                return 2
            } else {
                let v = CPUAddressing.imm16(cpu: cpu, bus: bus)
                sbc(cpu: cpu, value8: 0, value16: v)
                return 3
            }

        case 0xE5: // SBC dp
            return sbc_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 3)

        case 0xF5: // SBC dp,X
            return sbc_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 4)

        case 0xED: // SBC abs
            return sbc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 4)

        case 0xFD: // SBC abs,X
            return sbc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 4)

        case 0xF9: // SBC abs,Y
            return sbc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absY(cpu: cpu, bus: bus), cycles: 4)



        case 0xFF: // SBC long,X
            let target = CPUAddressing.absLongX(cpu: cpu, bus: bus)
            return sbc_mem(cpu: cpu, bank: target.bank, addr: target.addr, cycles: 5)
        case 0xC9: // CMP #imm
            if cpu.aIs8() {
                let v = CPUAddressing.imm8(cpu: cpu, bus: bus)
                cmpA(cpu: cpu, value8: v, value16: 0)
                return 2
            } else {
                let v = CPUAddressing.imm16(cpu: cpu, bus: bus)
                cmpA(cpu: cpu, value8: 0, value16: v)
                return 3
            }

        case 0xC5: // CMP dp
            return cmpA_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 3)

        case 0xD5: // CMP dp,X
            return cmpA_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 4)

        case 0xCD: // CMP abs
            return cmpA_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 4)

        case 0xDD: // CMP abs,X
            return cmpA_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 4)

        case 0xD9: // CMP abs,Y
            return cmpA_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absY(cpu: cpu, bus: bus), cycles: 4)

        case 0xE0: // CPX #imm
            if cpu.xIs8() {
                let v = CPUAddressing.imm8(cpu: cpu, bus: bus)
                cmpX(cpu: cpu, value8: v, value16: 0)
                return 2
            } else {
                let v = CPUAddressing.imm16(cpu: cpu, bus: bus)
                cmpX(cpu: cpu, value8: 0, value16: v)
                return 3
            }

        case 0xE4: // CPX dp
            return cmpX_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 3)

        case 0xEC: // CPX abs
            return cmpX_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 4)

        case 0xC0: // CPY #imm
            if cpu.xIs8() {
                let v = CPUAddressing.imm8(cpu: cpu, bus: bus)
                cmpY(cpu: cpu, value8: v, value16: 0)
                return 2
            } else {
                let v = CPUAddressing.imm16(cpu: cpu, bus: bus)
                cmpY(cpu: cpu, value8: 0, value16: v)
                return 3
            }

        case 0xC4: // CPY dp
            return cmpY_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 3)

        case 0xCC: // CPY abs
            return cmpY_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 4)

        case 0xE6: // INC dp
            return inc_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 5)

        case 0xF6: // INC dp,X
            return inc_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 6)

        case 0xEE: // INC abs
            return inc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 6)

        case 0xFE: // INC abs,X
            return inc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 7)

        case 0xC6: // DEC dp
            return dec_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 5)

        case 0xD6: // DEC dp,X
            return dec_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 6)

        case 0xCE: // DEC abs
            return dec_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 6)

        case 0xDE: // DEC abs,X
            return dec_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 7)

        case 0x89: // BIT #imm
            if cpu.aIs8() {
                let v = CPUAddressing.imm8(cpu: cpu, bus: bus)
                bitImmediate(cpu: cpu, value8: v, value16: 0)
                return 2
            } else {
                let v = CPUAddressing.imm16(cpu: cpu, bus: bus)
                bitImmediate(cpu: cpu, value8: 0, value16: v)
                return 3
            }

        case 0x24: // BIT dp
            return bit_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 3)

        case 0x34: // BIT dp,X
            return bit_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 4)

        case 0x2C: // BIT abs
            return bit_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 4)

        case 0x3C: // BIT abs,X
            return bit_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 4)


        case 0x06: // ASL dp
            return asl_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 5)

        case 0x16: // ASL dp,X
            return asl_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 6)

        case 0x0E: // ASL abs
            return asl_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 6)

        case 0x1E: // ASL abs,X
            return asl_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 7)

        case 0x26: // ROL dp
            return rol_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 5)

        case 0x36: // ROL dp,X
            return rol_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 6)

        case 0x2E: // ROL abs
            return rol_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 6)

        case 0x3E: // ROL abs,X
            return rol_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 7)

        case 0x46: // LSR dp
            return lsr_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 5)

        case 0x56: // LSR dp,X
            return lsr_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 6)

        case 0x4E: // LSR abs
            return lsr_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 6)

        case 0x5E: // LSR abs,X
            return lsr_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 7)

        case 0x66: // ROR dp
            return ror_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 5)

        case 0x76: // ROR dp,X
            return ror_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 6)

        case 0x6E: // ROR abs
            return ror_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 6)

        case 0x7E: // ROR abs,X
            return ror_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 7)


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

        case 0xA1: // LDA (dp,X)
            return lda_mem(cpu: cpu, addr: CPUAddressing.dpIndirectX(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 6)

        case 0xB2: // LDA (dp)
            return lda_mem(cpu: cpu, addr: CPUAddressing.dpIndirect(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 5)

        case 0xB1: // LDA (dp),Y
            return lda_mem(cpu: cpu, addr: CPUAddressing.dpIndirectY(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 6)

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

        case 0x81: // STA (dp,X)
            return sta_mem(cpu: cpu, addr: CPUAddressing.dpIndirectX(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 6)

        case 0x92: // STA (dp)
            return sta_mem(cpu: cpu, addr: CPUAddressing.dpIndirect(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 5)

        case 0x91: // STA (dp),Y
            return sta_mem(cpu: cpu, addr: CPUAddressing.dpIndirectY(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 6)

        case 0x8D: // STA abs
            return sta_mem(cpu: cpu, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)

        case 0x9D: // STA abs,X
            return sta_mem(cpu: cpu, addr: CPUAddressing.absX(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 5)

        case 0x99: // STA abs,Y
            return sta_mem(cpu: cpu, addr: CPUAddressing.absY(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 5)



        case 0x8F: // STA long
            let target = CPUAddressing.absLong(cpu: cpu, bus: bus)
            return sta_mem(cpu: cpu, addr: target.addr, bank: target.bank, cycles: 5)
        case 0x86: // STX dp
            return stx_mem(cpu: cpu, addr: CPUAddressing.dp(cpu: cpu, bus: bus), bank: 0x00, cycles: 3)

        case 0x8E: // STX abs
            return stx_mem(cpu: cpu, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)

        case 0x96: // STX dp,Y
            return stx_mem(cpu: cpu, addr: CPUAddressing.dpY(cpu: cpu, bus: bus), bank: 0x00, cycles: 4)

        case 0x84: // STY dp
            return sty_mem(cpu: cpu, addr: CPUAddressing.dp(cpu: cpu, bus: bus), bank: 0x00, cycles: 3)

        case 0x94: // STY dp,X
            return sty_mem(cpu: cpu, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), bank: 0x00, cycles: 4)

        case 0x8C: // STY abs
            return sty_mem(cpu: cpu, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)


        case 0x64: // STZ dp
            return stz_mem(cpu: cpu, addr: CPUAddressing.dp(cpu: cpu, bus: bus), bank: 0x00, cycles: 3)

        case 0x74: // STZ dp,X
            return stz_mem(cpu: cpu, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), bank: 0x00, cycles: 4)

        case 0x9C: // STZ abs
            return stz_mem(cpu: cpu, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)

        case 0x9E: // STZ abs,X
            return stz_mem(cpu: cpu, addr: CPUAddressing.absX(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 5)


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



        case 0x82: // BRL rel16
            let rel = CPUAddressing.rel16(cpu: cpu, bus: bus)
            cpu.setPC(cpu.r.pc &+ u16(bitPattern: rel))
            return 4
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
#if DEBUG
            print(String(format: "Missing opcode $%02X at %02X:%04X", Int(opcode), Int(cpu.r.pb), Int(cpu.r.pc)))
#endif
            
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

    // MARK: - ALU helpers

    @inline(__always)
    private static func ora(cpu: CPU65816, value8: u8, value16: u16) {
        if cpu.aIs8() {
            let res = cpu.a8() | value8
            cpu.setA8(res)
            cpu.updateNZ8(res)
        } else {
            let res = cpu.r.a | value16
            cpu.setA(res)
            cpu.updateNZ16(res)
        }
    }

    @inline(__always)
    private static func ora_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr)
            ora(cpu: cpu, value8: v, value16: 0)
        } else {
            let v = cpu.read16(bank, addr)
            ora(cpu: cpu, value8: 0, value16: v)
        }
        return cycles
    }

    @inline(__always)
    private static func and(cpu: CPU65816, value8: u8, value16: u16) {
        if cpu.aIs8() {
            let res = cpu.a8() & value8
            cpu.setA8(res)
            cpu.updateNZ8(res)
        } else {
            let res = cpu.r.a & value16
            cpu.setA(res)
            cpu.updateNZ16(res)
        }
    }

    @inline(__always)
    private static func and_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr)
            and(cpu: cpu, value8: v, value16: 0)
        } else {
            let v = cpu.read16(bank, addr)
            and(cpu: cpu, value8: 0, value16: v)
        }
        return cycles
    }

    @inline(__always)
    private static func eor(cpu: CPU65816, value8: u8, value16: u16) {
        if cpu.aIs8() {
            let res = cpu.a8() ^ value8
            cpu.setA8(res)
            cpu.updateNZ8(res)
        } else {
            let res = cpu.r.a ^ value16
            cpu.setA(res)
            cpu.updateNZ16(res)
        }
    }

    @inline(__always)
    private static func eor_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr)
            eor(cpu: cpu, value8: v, value16: 0)
        } else {
            let v = cpu.read16(bank, addr)
            eor(cpu: cpu, value8: 0, value16: v)
        }
        return cycles
    }

    @inline(__always)
    private static func adc(cpu: CPU65816, value8: u8, value16: u16) {
        if cpu.aIs8() {
            let a = cpu.a8()
            let carry: u16 = cpu.flag(.carry) ? 1 : 0
            let result = u16(a) &+ u16(value8) &+ carry
            let res8 = u8(truncatingIfNeeded: result)
            cpu.setA8(res8)
            cpu.setFlag(.carry, result > 0xFF)
            let overflow = (~(a ^ value8) & (a ^ res8) & 0x80) != 0
            cpu.setFlag(.overflow, overflow)
            cpu.updateNZ8(res8)
        } else {
            let a = cpu.r.a
            let carry: u32 = cpu.flag(.carry) ? 1 : 0
            let result = u32(a) &+ u32(value16) &+ carry
            let res16 = u16(truncatingIfNeeded: result)
            cpu.setA(res16)
            cpu.setFlag(.carry, result > 0xFFFF)
            let overflow = (~(a ^ value16) & (a ^ res16) & 0x8000) != 0
            cpu.setFlag(.overflow, overflow)
            cpu.updateNZ16(res16)
        }
    }

    @inline(__always)
    private static func adc_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr)
            adc(cpu: cpu, value8: v, value16: 0)
        } else {
            let v = cpu.read16(bank, addr)
            adc(cpu: cpu, value8: 0, value16: v)
        }
        return cycles
    }

    @inline(__always)
    private static func sbc(cpu: CPU65816, value8: u8, value16: u16) {
        if cpu.aIs8() {
            let a = cpu.a8()
            let carry: Int = cpu.flag(.carry) ? 0 : 1
            let result = Int(a) - Int(value8) - carry
            let res8 = u8(truncatingIfNeeded: result)
            cpu.setA8(res8)
            cpu.setFlag(.carry, result >= 0)
            let overflow = ((a ^ value8) & (a ^ res8) & 0x80) != 0
            cpu.setFlag(.overflow, overflow)
            cpu.updateNZ8(res8)
        } else {
            let a = cpu.r.a
            let carry: Int = cpu.flag(.carry) ? 0 : 1
            let result = Int(a) - Int(value16) - carry
            let res16 = u16(truncatingIfNeeded: result)
            cpu.setA(res16)
            cpu.setFlag(.carry, result >= 0)
            let overflow = ((a ^ value16) & (a ^ res16) & 0x8000) != 0
            cpu.setFlag(.overflow, overflow)
            cpu.updateNZ16(res16)
        }
    }

    @inline(__always)
    private static func sbc_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr)
            sbc(cpu: cpu, value8: v, value16: 0)
        } else {
            let v = cpu.read16(bank, addr)
            sbc(cpu: cpu, value8: 0, value16: v)
        }
        return cycles
    }

    @inline(__always)
    private static func cmpA(cpu: CPU65816, value8: u8, value16: u16) {
        if cpu.aIs8() {
            let a = cpu.a8()
            let result = u16(a) &- u16(value8)
            cpu.setFlag(.carry, a >= value8)
            cpu.updateNZ8(u8(truncatingIfNeeded: result))
        } else {
            let a = cpu.r.a
            let result = a &- value16
            cpu.setFlag(.carry, a >= value16)
            cpu.updateNZ16(result)
        }
    }

    @inline(__always)
    private static func cmpA_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr)
            cmpA(cpu: cpu, value8: v, value16: 0)
        } else {
            let v = cpu.read16(bank, addr)
            cmpA(cpu: cpu, value8: 0, value16: v)
        }
        return cycles
    }

    @inline(__always)
    private static func cmpX(cpu: CPU65816, value8: u8, value16: u16) {
        if cpu.xIs8() {
            let x = cpu.x8()
            let result = u16(x) &- u16(value8)
            cpu.setFlag(.carry, x >= value8)
            cpu.updateNZ8(u8(truncatingIfNeeded: result))
        } else {
            let x = cpu.r.x
            let result = x &- value16
            cpu.setFlag(.carry, x >= value16)
            cpu.updateNZ16(result)
        }
    }

    @inline(__always)
    private static func cmpX_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.xIs8() {
            let v = cpu.read8(bank, addr)
            cmpX(cpu: cpu, value8: v, value16: 0)
        } else {
            let v = cpu.read16(bank, addr)
            cmpX(cpu: cpu, value8: 0, value16: v)
        }
        return cycles
    }

    @inline(__always)
    private static func cmpY(cpu: CPU65816, value8: u8, value16: u16) {
        if cpu.xIs8() {
            let y = cpu.y8()
            let result = u16(y) &- u16(value8)
            cpu.setFlag(.carry, y >= value8)
            cpu.updateNZ8(u8(truncatingIfNeeded: result))
        } else {
            let y = cpu.r.y
            let result = y &- value16
            cpu.setFlag(.carry, y >= value16)
            cpu.updateNZ16(result)
        }
    }

    @inline(__always)
    private static func cmpY_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.xIs8() {
            let v = cpu.read8(bank, addr)
            cmpY(cpu: cpu, value8: v, value16: 0)
        } else {
            let v = cpu.read16(bank, addr)
            cmpY(cpu: cpu, value8: 0, value16: v)
        }
        return cycles
    }

    @inline(__always)
    private static func inc_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr) &+ 1
            cpu.write8(bank, addr, v)
            cpu.updateNZ8(v)
        } else {
            let v = cpu.read16(bank, addr) &+ 1
            cpu.write8(bank, addr, lo8(v))
            cpu.write8(bank, addr &+ 1, hi8(v))
            cpu.updateNZ16(v)
        }
        return cycles
    }

    @inline(__always)
    private static func dec_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr) &- 1
            cpu.write8(bank, addr, v)
            cpu.updateNZ8(v)
        } else {
            let v = cpu.read16(bank, addr) &- 1
            cpu.write8(bank, addr, lo8(v))
            cpu.write8(bank, addr &+ 1, hi8(v))
            cpu.updateNZ16(v)
        }
        return cycles
    }


    @inline(__always)
    private static func asl_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr)
            let res = v &<< 1
            cpu.write8(bank, addr, res)
            cpu.setFlag(.carry, (v & 0x80) != 0)
            cpu.updateNZ8(res)
        } else {
            let v = cpu.read16(bank, addr)
            let res = v &<< 1
            cpu.write8(bank, addr, lo8(res))
            cpu.write8(bank, addr &+ 1, hi8(res))
            cpu.setFlag(.carry, (v & 0x8000) != 0)
            cpu.updateNZ16(res)
        }
        return cycles
    }

    @inline(__always)
    private static func lsr_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr)
            let res = v >> 1
            cpu.write8(bank, addr, res)
            cpu.setFlag(.carry, (v & 0x01) != 0)
            cpu.updateNZ8(res)
        } else {
            let v = cpu.read16(bank, addr)
            let res = v >> 1
            cpu.write8(bank, addr, lo8(res))
            cpu.write8(bank, addr &+ 1, hi8(res))
            cpu.setFlag(.carry, (v & 0x0001) != 0)
            cpu.updateNZ16(res)
        }
        return cycles
    }

    @inline(__always)
    private static func rol_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr)
            let carryIn: u8 = cpu.flag(.carry) ? 1 : 0
            let res = (v &<< 1) | carryIn
            cpu.write8(bank, addr, res)
            cpu.setFlag(.carry, (v & 0x80) != 0)
            cpu.updateNZ8(res)
        } else {
            let v = cpu.read16(bank, addr)
            let carryIn: u16 = cpu.flag(.carry) ? 1 : 0
            let res = (v &<< 1) | carryIn
            cpu.write8(bank, addr, lo8(res))
            cpu.write8(bank, addr &+ 1, hi8(res))
            cpu.setFlag(.carry, (v & 0x8000) != 0)
            cpu.updateNZ16(res)
        }
        return cycles
    }

    @inline(__always)
    private static func ror_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr)
            let carryIn: u8 = cpu.flag(.carry) ? 0x80 : 0
            let res = (v >> 1) | carryIn
            cpu.write8(bank, addr, res)
            cpu.setFlag(.carry, (v & 0x01) != 0)
            cpu.updateNZ8(res)
        } else {
            let v = cpu.read16(bank, addr)
            let carryIn: u16 = cpu.flag(.carry) ? 0x8000 : 0
            let res = (v >> 1) | carryIn
            cpu.write8(bank, addr, lo8(res))
            cpu.write8(bank, addr &+ 1, hi8(res))
            cpu.setFlag(.carry, (v & 0x0001) != 0)
            cpu.updateNZ16(res)
        }
        return cycles
    }

    @inline(__always)
    private static func stz_mem(cpu: CPU65816, addr: u16, bank: u8, cycles: Int) -> Int {
        if cpu.aIs8() {
            cpu.write8(bank, addr, 0)
        } else {
            cpu.write8(bank, addr, 0)
            cpu.write8(bank, addr &+ 1, 0)
        }
        return cycles
    }


    @inline(__always)
    private static func bitImmediate(cpu: CPU65816, value8: u8, value16: u16) {
        if cpu.aIs8() {
            let res = cpu.a8() & value8
            cpu.setFlag(.zero, res == 0)
        } else {
            let res = cpu.r.a & value16
            cpu.setFlag(.zero, res == 0)
        }
    }

    @inline(__always)
    private static func bit_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr)
            let res = cpu.a8() & v
            cpu.setFlag(.zero, res == 0)
            cpu.setFlag(.negative, (v & 0x80) != 0)
            cpu.setFlag(.overflow, (v & 0x40) != 0)
        } else {
            let v = cpu.read16(bank, addr)
            let res = cpu.r.a & v
            cpu.setFlag(.zero, res == 0)
            cpu.setFlag(.negative, (v & 0x8000) != 0)
            cpu.setFlag(.overflow, (v & 0x4000) != 0)
        }
        return cycles
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
