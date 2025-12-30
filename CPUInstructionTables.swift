import Foundation

enum CPUInstructionTables {

    @inline(__always)
    static func execute(opcode: u8, cpu: CPU65816, bus: Bus) -> Int {
        switch opcode {

        case 0xEA: return 2
        case 0x42: _ = cpu.fetch8(); return 2
        case 0x78: cpu.setFlag(.irqDis, true); return 2
        case 0x58: cpu.setFlag(.irqDis, false); return 2
        case 0x18: cpu.setFlag(.carry, false); return 2
        case 0x38: cpu.setFlag(.carry, true); return 2
        case 0xD8: cpu.setFlag(.decimal, false); return 2
        case 0xF8: cpu.setFlag(.decimal, true); return 2
        case 0xC2: cpu.rep(cpu.fetch8()); return 3
        case 0xE2: cpu.sep(cpu.fetch8()); return 3
        case 0xB8: cpu.setFlag(.overflow, false); return 2
        case 0xFB: cpu.xce(); return 2
        case 0xCB: cpu.wai(); return 3
        case 0xDB: cpu.stp(); return 3

        case 0x00: cpu.serviceInterrupt(.brk); return 7
        case 0x02: cpu.serviceInterrupt(.cop); return 7
        case 0x40:
            let p = cpu.pull8()
            cpu.setPFromPull(p)
            let pcl = cpu.pull8()
            let pch = cpu.pull8()
            cpu.setPC(make16(pcl, pch))
            if !cpu.r.emulationMode {
                cpu.setPB(cpu.pull8())
                return 7
            }
            return 6

        case 0x48:
            cpu.aIs8() ? cpu.push8(cpu.a8()) : cpu.push16(cpu.r.a)
            return 3
        case 0x68:
            if cpu.aIs8() { let v = cpu.pull8(); cpu.setA8(v); cpu.updateNZ8(v) }
            else { let v = cpu.pull16(); cpu.setA(v); cpu.updateNZ16(v) }
            return 4
        case 0xDA:
            cpu.xIs8() ? cpu.push8(cpu.x8()) : cpu.push16(cpu.r.x)
            return 3
        case 0xFA:
            if cpu.xIs8() { let v = cpu.pull8(); cpu.setX8(v); cpu.updateNZ8(v) }
            else { let v = cpu.pull16(); cpu.setX(v); cpu.updateNZ16(v) }
            return 4
        case 0x5A:
            cpu.xIs8() ? cpu.push8(cpu.y8()) : cpu.push16(cpu.r.y)
            return 3
        case 0x7A:
            if cpu.xIs8() { let v = cpu.pull8(); cpu.setY8(v); cpu.updateNZ8(v) }
            else { let v = cpu.pull16(); cpu.setY(v); cpu.updateNZ16(v) }
            return 4
        case 0x08: cpu.push8(cpu.pForPush(brk: false)); return 3
        case 0x28: cpu.setPFromPull(cpu.pull8()); return 4
        case 0x0B: cpu.push16(cpu.r.dp); return 4
        case 0x2B: cpu.setDP(cpu.pull16()); cpu.updateNZ16(cpu.r.dp); return 5
        case 0x8B: cpu.push8(cpu.r.db); return 3
        case 0x4B: cpu.push8(cpu.r.pb); return 3
        case 0xAB:
            let v = cpu.pull8()
            cpu.setDB(v)
            cpu.updateNZ8(v)
            return 4
        case 0xF4: cpu.push16(cpu.fetch16()); return 5
        case 0xD4: cpu.push16(CPUAddressing.dp(cpu: cpu, bus: bus)); return 4
        case 0x62: cpu.push16(cpu.r.pc &+ 1 &+ u16(bitPattern: Int16(CPUAddressing.rel16(cpu: cpu, bus: bus)))); return 4

        case 0xAA:
            if cpu.xIs8() { let v = cpu.a8(); cpu.setX8(v); cpu.updateNZ8(v) }
            else { let v = cpu.aIs8() ? u16(cpu.a8()) : cpu.r.a; cpu.setX(v); cpu.updateNZ16(v) }
            return 2
        case 0x8A:
            if cpu.aIs8() { let v = cpu.x8(); cpu.setA8(v); cpu.updateNZ8(v) }
            else { let v = cpu.xIs8() ? u16(cpu.x8()) : cpu.r.x; cpu.setA(v); cpu.updateNZ16(v) }
            return 2
        case 0x5B: cpu.setDP(cpu.r.a); cpu.updateNZ16(cpu.r.dp); return 2
        case 0x1B:
            let val = cpu.r.a
            cpu.setSP(cpu.r.emulationMode ? (0x0100 | (val & 0x00FF)) : val)
            cpu.updateNZ16(val)
            return 2
        case 0x7B: cpu.setA(cpu.r.dp); cpu.updateNZ16(cpu.r.a); return 2
        case 0x3B: cpu.setA(cpu.r.sp); cpu.updateNZ16(cpu.r.a); return 2
        case 0xA8:
            if cpu.xIs8() { let v = cpu.a8(); cpu.setY8(v); cpu.updateNZ8(v) }
            else { let v = cpu.aIs8() ? u16(cpu.a8()) : cpu.r.a; cpu.setY(v); cpu.updateNZ16(v) }
            return 2
        case 0x98:
            if cpu.aIs8() { let v = cpu.y8(); cpu.setA8(v); cpu.updateNZ8(v) }
            else { let v = cpu.xIs8() ? u16(cpu.y8()) : cpu.r.y; cpu.setA(v); cpu.updateNZ16(v) }
            return 2
        case 0xBB:
            if cpu.xIs8() { let v = cpu.y8(); cpu.setX8(v); cpu.updateNZ8(v) }
            else { let v = cpu.r.y; cpu.setX(v); cpu.updateNZ16(v) }
            return 2
        case 0xBA:
            if cpu.xIs8() { let v = u8(truncatingIfNeeded: cpu.r.sp); cpu.setX8(v); cpu.updateNZ8(v) }
            else { cpu.setX(cpu.r.sp); cpu.updateNZ16(cpu.r.sp) }
            return 2
        case 0x9A:
            cpu.xIs8() ? cpu.setSPLo(cpu.x8()) : cpu.setSP(cpu.r.x)
            return 2
        case 0x9B:
            if cpu.xIs8() { let v = cpu.x8(); cpu.setY8(v); cpu.updateNZ8(v) }
            else { let v = cpu.r.x; cpu.setY(v); cpu.updateNZ16(v) }
            return 2

        case 0x54, 0x44: return blockMove(cpu: cpu, bus: bus, opcode: opcode)

        case 0xE8:
            if cpu.xIs8() { let v = cpu.x8() &+ 1; cpu.setX8(v); cpu.updateNZ8(v) }
            else { let v = cpu.r.x &+ 1; cpu.setX(v); cpu.updateNZ16(v) }
            return 2
        case 0xC8:
            if cpu.xIs8() { let v = cpu.y8() &+ 1; cpu.setY8(v); cpu.updateNZ8(v) }
            else { let v = cpu.r.y &+ 1; cpu.setY(v); cpu.updateNZ16(v) }
            return 2
        case 0xCA:
            if cpu.xIs8() { let v = cpu.x8() &- 1; cpu.setX8(v); cpu.updateNZ8(v) }
            else { let v = cpu.r.x &- 1; cpu.setX(v); cpu.updateNZ16(v) }
            return 2
        case 0x88:
            if cpu.xIs8() { let v = cpu.y8() &- 1; cpu.setY8(v); cpu.updateNZ8(v) }
            else { let v = cpu.r.y &- 1; cpu.setY(v); cpu.updateNZ16(v) }
            return 2
        case 0x1A:
            if cpu.aIs8() { let v = cpu.a8() &+ 1; cpu.setA8(v); cpu.updateNZ8(v) }
            else { let v = cpu.r.a &+ 1; cpu.setA(v); cpu.updateNZ16(v) }
            return 2
        case 0x3A:
            if cpu.aIs8() { let v = cpu.a8() &- 1; cpu.setA8(v); cpu.updateNZ8(v) }
            else { let v = cpu.r.a &- 1; cpu.setA(v); cpu.updateNZ16(v) }
            return 2
        case 0x0A:
            if cpu.aIs8() {
                let v = cpu.a8(); let res = v &<< 1; cpu.setA8(res); cpu.setFlag(.carry, (v & 0x80) != 0); cpu.updateNZ8(res)
            } else {
                let v = cpu.r.a; let res = v &<< 1; cpu.setA(res); cpu.setFlag(.carry, (v & 0x8000) != 0); cpu.updateNZ16(res)
            }
            return 2
        case 0x2A:
            if cpu.aIs8() {
                let v = cpu.a8(); let res = (v &<< 1) | (cpu.flag(.carry) ? 1 : 0); cpu.setA8(res); cpu.setFlag(.carry, (v & 0x80) != 0); cpu.updateNZ8(res)
            } else {
                let v = cpu.r.a; let res = (v &<< 1) | (cpu.flag(.carry) ? 1 : 0); cpu.setA(res); cpu.setFlag(.carry, (v & 0x8000) != 0); cpu.updateNZ16(res)
            }
            return 2
        case 0x4A:
            if cpu.aIs8() {
                let v = cpu.a8(); let res = v >> 1; cpu.setA8(res); cpu.setFlag(.carry, (v & 0x01) != 0); cpu.updateNZ8(res)
            } else {
                let v = cpu.r.a; let res = v >> 1; cpu.setA(res); cpu.setFlag(.carry, (v & 0x0001) != 0); cpu.updateNZ16(res)
            }
            return 2
        case 0x6A:
            if cpu.aIs8() {
                let v = cpu.a8(); let res = (v >> 1) | (cpu.flag(.carry) ? 0x80 : 0); cpu.setA8(res); cpu.setFlag(.carry, (v & 0x01) != 0); cpu.updateNZ8(res)
            } else {
                let v = cpu.r.a; let res = (v >> 1) | (cpu.flag(.carry) ? 0x8000 : 0); cpu.setA(res); cpu.setFlag(.carry, (v & 0x0001) != 0); cpu.updateNZ16(res)
            }
            return 2

        case 0x09:
            if cpu.aIs8() { ora(cpu: cpu, value8: CPUAddressing.imm8(cpu: cpu, bus: bus), value16: 0); return 2 }
            else { ora(cpu: cpu, value8: 0, value16: CPUAddressing.imm16(cpu: cpu, bus: bus)); return 3 }
        case 0x05: // ORA dp
            let extra = cpu.dpLowBytePenalty()
            return ora_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 3 + extra)
        case 0x07: let t = CPUAddressing.dpIndirectLong(cpu: cpu, bus: bus); return ora_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 6)
        case 0x11: return ora_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.dpIndirectY(cpu: cpu, bus: bus), cycles: 6)
        case 0x17: let t = CPUAddressing.dpIndirectLongY(cpu: cpu, bus: bus); return ora_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 6)
        case 0x0F: let t = CPUAddressing.absLong(cpu: cpu, bus: bus); return ora_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 5)
        case 0x12: return ora_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.dpIndirect(cpu: cpu, bus: bus), cycles: 5)
        case 0x13:
            let eff = cpu.read16(0x00, cpu.r.sp &+ u16(cpu.fetch8())) &+ cpu.r.y
            return ora_mem(cpu: cpu, bank: cpu.r.db, addr: eff, cycles: 7)
        case 0x15: return ora_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 4)
        case 0x1F: let t = CPUAddressing.absLongX(cpu: cpu, bus: bus); return ora_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 5)
        case 0x01: return ora_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.dpIndirectX(cpu: cpu, bus: bus), cycles: 6)
        case 0x03: return ora_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.stackRelative(cpu: cpu, bus: bus), cycles: 4)
        case 0x0D: return ora_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 4)
        case 0x1D:
            let base = CPUAddressing.abs16(cpu: cpu, bus: bus)
            let eff = base &+ cpu.r.x
            let extra = cpu.pageCrossed(base, eff) ? 1 : 0
            return ora_mem(cpu: cpu, bank: cpu.r.db, addr: eff, cycles: 4 + extra)
        case 0x19: return ora_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absY(cpu: cpu, bus: bus), cycles: 4)

        case 0x29:
            if cpu.aIs8() { and(cpu: cpu, value8: CPUAddressing.imm8(cpu: cpu, bus: bus), value16: 0); return 2 }
            else { and(cpu: cpu, value8: 0, value16: CPUAddressing.imm16(cpu: cpu, bus: bus)); return 3 }
        case 0x25: return and_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 3)
        case 0x27: let t = CPUAddressing.dpIndirectLong(cpu: cpu, bus: bus); return and_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 6)
        case 0x31: return and_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.dpIndirectY(cpu: cpu, bus: bus), cycles: 6)
        case 0x37: let t = CPUAddressing.dpIndirectLongY(cpu: cpu, bus: bus); return and_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 6)
        case 0x23:
            let eff = cpu.read16(0x00, cpu.r.sp &+ u16(cpu.fetch8())) &+ cpu.r.y
            return and_mem(cpu: cpu, bank: cpu.r.db, addr: eff, cycles: 7)
        case 0x2F:
            let t = CPUAddressing.absLong(cpu: cpu, bus: bus)
            return and_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 5)
        case 0x3F:
            let t = CPUAddressing.absLongX(cpu: cpu, bus: bus)
            return and_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 5)
        case 0x32: return and_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.dpIndirect(cpu: cpu, bus: bus), cycles: 5)
        case 0x33:
            let eff = cpu.read16(0x00, cpu.r.sp &+ u16(cpu.fetch8())) &+ cpu.r.y
            return and_mem(cpu: cpu, bank: cpu.r.db, addr: eff, cycles: 7)
        case 0x35: return and_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 4)
        case 0x2D: return and_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 4)
        case 0x3D: return and_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 4)
        case 0x21: return and_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.dpIndirectX(cpu: cpu, bus: bus), cycles: 6)
        case 0x39: return and_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absY(cpu: cpu, bus: bus), cycles: 4)

        case 0x49:
            if cpu.aIs8() { eor(cpu: cpu, value8: CPUAddressing.imm8(cpu: cpu, bus: bus), value16: 0); return 2 }
            else { eor(cpu: cpu, value8: 0, value16: CPUAddressing.imm16(cpu: cpu, bus: bus)); return 3 }
        case 0x41: return eor_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.dpIndirectX(cpu: cpu, bus: bus), cycles: 6)
        case 0x45: return eor_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 3)
        case 0x55: return eor_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 4)
        case 0x4D: return eor_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 4)
        case 0x5D: return eor_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 4)
        case 0x59: return eor_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absY(cpu: cpu, bus: bus), cycles: 4)
        case 0x43: return eor_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.stackRelative(cpu: cpu, bus: bus), cycles: 4)
        case 0x47: let t = CPUAddressing.dpIndirectLong(cpu: cpu, bus: bus); return eor_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 6)
        case 0x51: return eor_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.dpIndirectY(cpu: cpu, bus: bus), cycles: 6)
        case 0x52: return eor_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.dpIndirect(cpu: cpu, bus: bus), cycles: 5)
        case 0x53: let eff = cpu.read16(0x00, cpu.r.sp &+ u16(cpu.fetch8())) &+ cpu.r.y; return eor_mem(cpu: cpu, bank: cpu.r.db, addr: eff, cycles: 7)
        case 0x4F: let t = CPUAddressing.absLong(cpu: cpu, bus: bus); return eor_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 5)
        case 0x5F: let t = CPUAddressing.absLongX(cpu: cpu, bus: bus); return eor_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 5)
        case 0x57: let t = CPUAddressing.dpIndirectLongY(cpu: cpu, bus: bus); return eor_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 6)

        case 0x89:
            if cpu.aIs8() { bitImmediate(cpu: cpu, value8: CPUAddressing.imm8(cpu: cpu, bus: bus), value16: 0); return 2 }
            else { bitImmediate(cpu: cpu, value8: 0, value16: CPUAddressing.imm16(cpu: cpu, bus: bus)); return 3 }
        case 0x24: return bit_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 3)
        case 0x34: return bit_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 4)
        case 0x2C: return bit_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 4)
        case 0x3C: return bit_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 4)

        case 0x69:
            if cpu.aIs8() { adc(cpu: cpu, value8: CPUAddressing.imm8(cpu: cpu, bus: bus), value16: 0); return 2 }
            else { adc(cpu: cpu, value8: 0, value16: CPUAddressing.imm16(cpu: cpu, bus: bus)); return 3 }
        case 0x65: return adc_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 3)
        case 0x61: return adc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.dpIndirectX(cpu: cpu, bus: bus), cycles: 6)
        case 0x63: return adc_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.stackRelative(cpu: cpu, bus: bus), cycles: 4)
        case 0x67: let t = CPUAddressing.dpIndirectLong(cpu: cpu, bus: bus); return adc_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 6)
        case 0x71: return adc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.dpIndirectY(cpu: cpu, bus: bus), cycles: 6)
        case 0x72: return adc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.dpIndirect(cpu: cpu, bus: bus), cycles: 5)
        case 0x73:
            let eff = cpu.read16(0x00, cpu.r.sp &+ u16(cpu.fetch8())) &+ cpu.r.y
            return adc_mem(cpu: cpu, bank: cpu.r.db, addr: eff, cycles: 7)
        case 0x75: return adc_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 4)
        case 0x6D: return adc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 4)
        case 0x7D: return adc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 4)
        case 0x79: return adc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absY(cpu: cpu, bus: bus), cycles: 4)
        case 0x6F: let t = CPUAddressing.absLong(cpu: cpu, bus: bus); return adc_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 5)
        case 0x7F: let t = CPUAddressing.absLongX(cpu: cpu, bus: bus); return adc_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 5)
        case 0x77: let t = CPUAddressing.dpIndirectLongY(cpu: cpu, bus: bus); return adc_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 6)

        case 0xE9, 0xEB:
            if cpu.aIs8() { sbc(cpu: cpu, value8: CPUAddressing.imm8(cpu: cpu, bus: bus), value16: 0); return 2 }
            else { sbc(cpu: cpu, value8: 0, value16: CPUAddressing.imm16(cpu: cpu, bus: bus)); return 3 }
        case 0xE5: return sbc_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 3)
        case 0xE1: return sbc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.dpIndirectX(cpu: cpu, bus: bus), cycles: 6)
        case 0xE3: return sbc_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.stackRelative(cpu: cpu, bus: bus), cycles: 4)
        case 0xE7: let t = CPUAddressing.dpIndirectLong(cpu: cpu, bus: bus); return sbc_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 6)
        case 0xF1: return sbc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.dpIndirectY(cpu: cpu, bus: bus), cycles: 6)
        case 0xF2: return sbc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.dpIndirect(cpu: cpu, bus: bus), cycles: 5)
        case 0xF3: let eff = cpu.read16(0x00, cpu.r.sp &+ u16(cpu.fetch8())) &+ cpu.r.y; return sbc_mem(cpu: cpu, bank: cpu.r.db, addr: eff, cycles: 7)
        case 0xF5: return sbc_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 4)
        case 0xED: return sbc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 4)
        case 0xFD: return sbc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 4)
        case 0xF9: return sbc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absY(cpu: cpu, bus: bus), cycles: 4)
        case 0xEF: let t = CPUAddressing.absLong(cpu: cpu, bus: bus); return sbc_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 5)
        case 0xFF: let t = CPUAddressing.absLongX(cpu: cpu, bus: bus); return sbc_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 5)
        case 0xF7: let t = CPUAddressing.dpIndirectLongY(cpu: cpu, bus: bus); return sbc_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 6)

        case 0xC9:
            if cpu.aIs8() { cmpA(cpu: cpu, value8: CPUAddressing.imm8(cpu: cpu, bus: bus), value16: 0); return 2 }
            else { cmpA(cpu: cpu, value8: 0, value16: CPUAddressing.imm16(cpu: cpu, bus: bus)); return 3 }
        case 0xC5: return cmpA_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 3)
        case 0xD5: return cmpA_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 4)
        case 0xCD: return cmpA_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 4)
        case 0xDD: return cmpA_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 4)
        case 0xD9: return cmpA_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absY(cpu: cpu, bus: bus), cycles: 4)
        case 0xD2: return cmpA_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.dpIndirect(cpu: cpu, bus: bus), cycles: 5)
        case 0xC1: return cmpA_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.dpIndirectX(cpu: cpu, bus: bus), cycles: 6)
        case 0xC3: return cmpA_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.stackRelative(cpu: cpu, bus: bus), cycles: 4)
        case 0xC7: let t = CPUAddressing.dpIndirectLong(cpu: cpu, bus: bus); return cmpA_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 6)
        case 0xD1: return cmpA_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.dpIndirectY(cpu: cpu, bus: bus), cycles: 6)
        case 0xD3: let eff = cpu.read16(0x00, cpu.r.sp &+ u16(cpu.fetch8())) &+ cpu.r.y; return cmpA_mem(cpu: cpu, bank: cpu.r.db, addr: eff, cycles: 7)
        case 0xCF: let t = CPUAddressing.absLong(cpu: cpu, bus: bus); return cmpA_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 5)
        case 0xDF: let t = CPUAddressing.absLongX(cpu: cpu, bus: bus); return cmpA_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 5)
        case 0xD7: let t = CPUAddressing.dpIndirectLongY(cpu: cpu, bus: bus); return cmpA_mem(cpu: cpu, bank: t.bank, addr: t.addr, cycles: 6)

        case 0xE0:
            if cpu.xIs8() { cmpX(cpu: cpu, value8: CPUAddressing.imm8(cpu: cpu, bus: bus), value16: 0); return 2 }
            else { cmpX(cpu: cpu, value8: 0, value16: CPUAddressing.imm16(cpu: cpu, bus: bus)); return 3 }
        case 0xE4: return cmpX_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 3)
        case 0xEC: return cmpX_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 4)

        case 0xC0:
            if cpu.xIs8() { cmpY(cpu: cpu, value8: CPUAddressing.imm8(cpu: cpu, bus: bus), value16: 0); return 2 }
            else { cmpY(cpu: cpu, value8: 0, value16: CPUAddressing.imm16(cpu: cpu, bus: bus)); return 3 }
        case 0xC4: return cmpY_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 3)
        case 0xCC: return cmpY_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 4)

        case 0x06: return asl_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 5)
        case 0x16: return asl_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 6)
        case 0x0E: return asl_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 6)
        case 0x1E: return asl_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 7)
        case 0x26: return rol_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 5)
        case 0x36: return rol_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 6)
        case 0x2E: return rol_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 6)
        case 0x3E: return rol_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 7)
        case 0x46: return lsr_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 5)
        case 0x56: return lsr_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 6)
        case 0x4E: return lsr_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 6)
        case 0x5E: return lsr_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 7)
        case 0x66: return ror_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 5)
        case 0x76: return ror_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 6)
        case 0x6E: return ror_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 6)
        case 0x7E: return ror_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 7)

        case 0x04: return tsb_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 5)
        case 0x0C: return tsb_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 6)
        case 0x14: return trb_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 5)
        case 0x1C: return trb_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 6)

        case 0xE6: return inc_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 5)
        case 0xF6: return inc_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 6)
        case 0xEE: return inc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 6)
        case 0xFE: return inc_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 7)
        case 0xC6: return dec_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dp(cpu: cpu, bus: bus), cycles: 5)
        case 0xD6: return dec_mem(cpu: cpu, bank: 0x00, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), cycles: 6)
        case 0xCE: return dec_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), cycles: 6)
        case 0xDE: return dec_mem(cpu: cpu, bank: cpu.r.db, addr: CPUAddressing.absX(cpu: cpu, bus: bus), cycles: 7)

        case 0xA9:
            if cpu.aIs8() { let v = CPUAddressing.imm8(cpu: cpu, bus: bus); cpu.setA8(v); cpu.updateNZ8(v); return 2 }
            else { let v = CPUAddressing.imm16(cpu: cpu, bus: bus); cpu.setA(v); cpu.updateNZ16(v); return 3 }
        case 0xA2:
            if cpu.xIs8() { let v = CPUAddressing.imm8(cpu: cpu, bus: bus); cpu.setX8(v); cpu.updateNZ8(v); return 2 }
            else { let v = CPUAddressing.imm16(cpu: cpu, bus: bus); cpu.setX(v); cpu.updateNZ16(v); return 3 }
        case 0xA0:
            if cpu.xIs8() { let v = CPUAddressing.imm8(cpu: cpu, bus: bus); cpu.setY8(v); cpu.updateNZ8(v); return 2 }
            else { let v = CPUAddressing.imm16(cpu: cpu, bus: bus); cpu.setY(v); cpu.updateNZ16(v); return 3 }
        case 0xA5: return lda_mem(cpu: cpu, addr: CPUAddressing.dp(cpu: cpu, bus: bus), bank: 0x00, cycles: 3)
        case 0xB5: return lda_mem(cpu: cpu, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), bank: 0x00, cycles: 4)
        case 0xA1: return lda_mem(cpu: cpu, addr: CPUAddressing.dpIndirectX(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 6)
        case 0xB2: return lda_mem(cpu: cpu, addr: CPUAddressing.dpIndirect(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 5)
        case 0xB7: let t = CPUAddressing.dpIndirectLongY(cpu: cpu, bus: bus); return lda_mem(cpu: cpu, addr: t.addr, bank: t.bank, cycles: 6)
        case 0xB1: return lda_mem(cpu: cpu, addr: CPUAddressing.dpIndirectY(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 6)
        case 0xB3:
            let eff = cpu.read16(0x00, cpu.r.sp &+ u16(cpu.fetch8())) &+ cpu.r.y
            return lda_mem(cpu: cpu, addr: eff, bank: cpu.r.db, cycles: 7)
        case 0xA3: return lda_mem(cpu: cpu, addr: CPUAddressing.stackRelative(cpu: cpu, bus: bus), bank: 0x00, cycles: 4)
        case 0xA7: let t = CPUAddressing.dpIndirectLong(cpu: cpu, bus: bus); return lda_mem(cpu: cpu, addr: t.addr, bank: t.bank, cycles: 6)
        case 0xAF: let t = CPUAddressing.absLong(cpu: cpu, bus: bus); return lda_mem(cpu: cpu, addr: t.addr, bank: t.bank, cycles: 5)
        case 0xAD: return lda_mem(cpu: cpu, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)
        case 0xBD: return lda_mem(cpu: cpu, addr: CPUAddressing.absX(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)
        case 0xB9: return lda_mem(cpu: cpu, addr: CPUAddressing.absY(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)
        case 0xBF: let t = CPUAddressing.absLongX(cpu: cpu, bus: bus); return lda_mem(cpu: cpu, addr: t.addr, bank: t.bank, cycles: 5)

        case 0xA6: return ldx_mem(cpu: cpu, addr: CPUAddressing.dp(cpu: cpu, bus: bus), bank: 0x00, cycles: 3)
        case 0xB6: return ldx_mem(cpu: cpu, addr: CPUAddressing.dpY(cpu: cpu, bus: bus), bank: 0x00, cycles: 4)
        case 0xAE: return ldx_mem(cpu: cpu, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)
        case 0xBE: return ldx_mem(cpu: cpu, addr: CPUAddressing.absY(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)
        case 0xA4: return ldy_mem(cpu: cpu, addr: CPUAddressing.dp(cpu: cpu, bus: bus), bank: 0x00, cycles: 3)
        case 0xB4: return ldy_mem(cpu: cpu, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), bank: 0x00, cycles: 4)
        case 0xAC: return ldy_mem(cpu: cpu, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)
        case 0xBC: return ldy_mem(cpu: cpu, addr: CPUAddressing.absX(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)

        case 0x85: return sta_mem(cpu: cpu, addr: CPUAddressing.dp(cpu: cpu, bus: bus), bank: 0x00, cycles: 3)
        case 0x95: return sta_mem(cpu: cpu, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), bank: 0x00, cycles: 4)
        case 0x81: return sta_mem(cpu: cpu, addr: CPUAddressing.dpIndirectX(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 6)
        case 0x92: return sta_mem(cpu: cpu, addr: CPUAddressing.dpIndirect(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 5)
        case 0x93:
            let offset = u16(cpu.fetch8())
            let ptr = cpu.r.sp &+ offset
            let eff = cpu.read16(0x00, ptr) &+ cpu.r.y
            return sta_mem(cpu: cpu, addr: eff, bank: cpu.r.db, cycles: 7)
        case 0x91: return sta_mem(cpu: cpu, addr: CPUAddressing.dpIndirectY(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 6)
        case 0x83: return sta_mem(cpu: cpu, addr: CPUAddressing.stackRelative(cpu: cpu, bus: bus), bank: 0x00, cycles: 4)
        case 0x87: let t = CPUAddressing.dpIndirectLong(cpu: cpu, bus: bus); return sta_mem(cpu: cpu, addr: t.addr, bank: t.bank, cycles: 6)
        case 0x97: let t = CPUAddressing.dpIndirectLongY(cpu: cpu, bus: bus); return sta_mem(cpu: cpu, addr: t.addr, bank: t.bank, cycles: 6)
        case 0x8D: return sta_mem(cpu: cpu, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)
        case 0x9D: return sta_mem(cpu: cpu, addr: CPUAddressing.absX(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 5)
        case 0x99: return sta_mem(cpu: cpu, addr: CPUAddressing.absY(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 5)
        case 0x9F: let t = CPUAddressing.absLongX(cpu: cpu, bus: bus); return sta_mem(cpu: cpu, addr: t.addr, bank: t.bank, cycles: 5)
        case 0x8F: let t = CPUAddressing.absLong(cpu: cpu, bus: bus); return sta_mem(cpu: cpu, addr: t.addr, bank: t.bank, cycles: 5)

        case 0x86: return stx_mem(cpu: cpu, addr: CPUAddressing.dp(cpu: cpu, bus: bus), bank: 0x00, cycles: 3)
        case 0x8E: return stx_mem(cpu: cpu, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)
        case 0x96: return stx_mem(cpu: cpu, addr: CPUAddressing.dpY(cpu: cpu, bus: bus), bank: 0x00, cycles: 4)
        case 0x84: return sty_mem(cpu: cpu, addr: CPUAddressing.dp(cpu: cpu, bus: bus), bank: 0x00, cycles: 3)
        case 0x94: return sty_mem(cpu: cpu, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), bank: 0x00, cycles: 4)
        case 0x8C: return sty_mem(cpu: cpu, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)

        case 0x64: return stz_mem(cpu: cpu, addr: CPUAddressing.dp(cpu: cpu, bus: bus), bank: 0x00, cycles: 3)
        case 0x74: return stz_mem(cpu: cpu, addr: CPUAddressing.dpX(cpu: cpu, bus: bus), bank: 0x00, cycles: 4)
        case 0x9C: return stz_mem(cpu: cpu, addr: CPUAddressing.abs16(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 4)
        case 0x9E: return stz_mem(cpu: cpu, addr: CPUAddressing.absX(cpu: cpu, bus: bus), bank: cpu.r.db, cycles: 5)

        case 0x4C: cpu.setPC(CPUAddressing.abs16(cpu: cpu, bus: bus)); return 3
        case 0x6C: cpu.setPC(CPUAddressing.absIndirect(cpu: cpu, bus: bus)); return 5
        case 0x7C:
            let ptr = cpu.fetch16() &+ cpu.r.x
            let target = make16(cpu.read8(cpu.r.pb, ptr), cpu.read8(cpu.r.pb, ptr &+ 1))
            cpu.setPC(target); return 6
        case 0x5C:
            let lo = cpu.fetch8(); let hi = cpu.fetch8(); cpu.setPB(cpu.fetch8()); cpu.setPC(make16(lo, hi)); return 4
        case 0xDC:
            let ptr = cpu.fetch16()
            let target = make16(cpu.read8(0x00, ptr), cpu.read8(0x00, ptr &+ 1))
            cpu.setPB(cpu.read8(0x00, ptr &+ 2)); cpu.setPC(target); return 6
        case 0x20:
            let target = CPUAddressing.abs16(cpu: cpu, bus: bus)
            cpu.push16(cpu.r.pc &- 1); cpu.setPC(target); return 6
        case 0xFC:
            let ptr = cpu.fetch16() &+ cpu.r.x
            let target = make16(cpu.read8(cpu.r.pb, ptr), cpu.read8(cpu.r.pb, ptr &+ 1))
            let ret = cpu.r.pc &- 1
            cpu.push8(hi8(ret)); cpu.push8(lo8(ret)); cpu.setPC(target); return 8
        case 0x22:
            let target = CPUAddressing.absLong(cpu: cpu, bus: bus)
            cpu.push8(cpu.r.pb); cpu.push16(cpu.r.pc &- 1); cpu.setPB(target.bank); cpu.setPC(target.addr); return 8
        case 0x6B:
            let ret = cpu.pull16(); cpu.setPB(cpu.pull8()); cpu.setPC(ret &+ 1); return 6
        case 0x82:
            cpu.setPC(cpu.r.pc &+ u16(bitPattern: Int16(CPUAddressing.rel16(cpu: cpu, bus: bus)))); return 4
        case 0x60: cpu.setPC(cpu.pull16() &+ 1); return 6
        case 0x80:
            cpu.setPC(cpu.r.pc &+ u16(bitPattern: Int16(CPUAddressing.rel8(cpu: cpu, bus: bus)))); return 3
        case 0xF0: return branch(cpu: cpu, bus: bus, cond: cpu.flag(.zero))
        case 0xD0: return branch(cpu: cpu, bus: bus, cond: !cpu.flag(.zero))
        case 0x10: return branch(cpu: cpu, bus: bus, cond: !cpu.flag(.negative))
        case 0x30: return branch(cpu: cpu, bus: bus, cond: cpu.flag(.negative))
        case 0x90: return branch(cpu: cpu, bus: bus, cond: !cpu.flag(.carry))
        case 0xB0: return branch(cpu: cpu, bus: bus, cond: cpu.flag(.carry))
        case 0x50: return branch(cpu: cpu, bus: bus, cond: !cpu.flag(.overflow))
        case 0x70: return branch(cpu: cpu, bus: bus, cond: cpu.flag(.overflow))

        default:
            return 2
        }
    }

    @inline(__always)
    private static func blockMove(cpu: CPU65816, bus: Bus, opcode: u8) -> Int {
        let destBank = cpu.fetch8()
        let srcBank = cpu.fetch8()
        let value = cpu.read8(srcBank, cpu.r.x)
        cpu.write8(destBank, cpu.r.y, value)
        if opcode == 0x54 { cpu.setX(cpu.r.x &+ 1); cpu.setY(cpu.r.y &+ 1) }
        else { cpu.setX(cpu.r.x &- 1); cpu.setY(cpu.r.y &- 1) }
        let newA = cpu.r.a &- 1
        cpu.setA(newA)
        if newA != 0xFFFF {
        cpu.setPC(cpu.r.pc &- 3)
    }
        cpu.setDB(destBank)
          return 7
    }

    @inline(__always)
    private static func asl_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr); let res = v &<< 1; cpu.write8(bank, addr, res)
            cpu.setFlag(.carry, (v & 0x80) != 0); cpu.updateNZ8(res)
        } else {
            let v = cpu.read16(bank, addr); let res = v &<< 1
            cpu.write8(bank, addr, lo8(res)); cpu.write8(bank, addr &+ 1, hi8(res))
            cpu.setFlag(.carry, (v & 0x8000) != 0); cpu.updateNZ16(res)
        }
        return cycles
    }

    @inline(__always)
    private static func lsr_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr); let res = v >> 1; cpu.write8(bank, addr, res)
            cpu.setFlag(.carry, (v & 0x01) != 0); cpu.updateNZ8(res)
        } else {
            let v = cpu.read16(bank, addr); let res = v >> 1
            cpu.write8(bank, addr, lo8(res)); cpu.write8(bank, addr &+ 1, hi8(res))
            cpu.setFlag(.carry, (v & 0x0001) != 0); cpu.updateNZ16(res)
        }
        return cycles
    }

    @inline(__always)
    private static func rol_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        let carry: u16 = cpu.flag(.carry) ? 1 : 0
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr); let res = (v &<< 1) | u8(carry); cpu.write8(bank, addr, res)
            cpu.setFlag(.carry, (v & 0x80) != 0); cpu.updateNZ8(res)
        } else {
            let v = cpu.read16(bank, addr); let res = (v &<< 1) | carry
            cpu.write8(bank, addr, lo8(res)); cpu.write8(bank, addr &+ 1, hi8(res))
            cpu.setFlag(.carry, (v & 0x8000) != 0); cpu.updateNZ16(res)
        }
        return cycles
    }

    @inline(__always)
    private static func ror_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr); let res = (v >> 1) | (cpu.flag(.carry) ? 0x80 : 0); cpu.write8(bank, addr, res)
            cpu.setFlag(.carry, (v & 0x01) != 0); cpu.updateNZ8(res)
        } else {
            let v = cpu.read16(bank, addr); let res = (v >> 1) | (cpu.flag(.carry) ? 0x8000 : 0)
            cpu.write8(bank, addr, lo8(res)); cpu.write8(bank, addr &+ 1, hi8(res))
            cpu.setFlag(.carry, (v & 0x0001) != 0); cpu.updateNZ16(res)
        }
        return cycles
    }

    @inline(__always)
    private static func stz_mem(cpu: CPU65816, addr: u16, bank: u8, cycles: Int) -> Int {
        if cpu.aIs8() { cpu.write8(bank, addr, 0) }
        else { cpu.write8(bank, addr, 0); cpu.write8(bank, addr &+ 1, 0) }
        return cycles
    }

    @inline(__always)
    private static func tsb_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let m = cpu.read8(bank, addr); let a = cpu.a8()
            cpu.setFlag(.zero, (m & a) == 0); cpu.write8(bank, addr, m | a)
        } else {
            let m = cpu.read16(bank, addr); let a = cpu.r.a
            cpu.setFlag(.zero, (m & a) == 0); cpu.write16(bank, addr, m | a)
        }
        return cycles
    }

    @inline(__always)
    private static func trb_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let m = cpu.read8(bank, addr); let a = cpu.a8()
            cpu.setFlag(.zero, (m & a) == 0); cpu.write8(bank, addr, m & ~a)
        } else {
            let m = cpu.read16(bank, addr); let a = cpu.r.a
            cpu.setFlag(.zero, (m & a) == 0); cpu.write16(bank, addr, m & ~a)
        }
        return cycles
    }

    @inline(__always)
    private static func branch(cpu: CPU65816, bus: Bus, cond: Bool) -> Int {
        let rel = CPUAddressing.rel8(cpu: cpu, bus: bus)
        if cond { cpu.setPC(cpu.r.pc &+ u16(bitPattern: Int16(rel))); return 3 }
        return 2
    }

    @inline(__always)
    private static func ora(cpu: CPU65816, value8: u8, value16: u16) {
        if cpu.aIs8() { let res = cpu.a8() | value8; cpu.setA8(res); cpu.updateNZ8(res) }
        else { let res = cpu.r.a | value16; cpu.setA(res); cpu.updateNZ16(res) }
    }

    @inline(__always)
    private static func ora_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() { ora(cpu: cpu, value8: cpu.read8(bank, addr), value16: 0) }
        else { ora(cpu: cpu, value8: 0, value16: cpu.read16(bank, addr)) }
        return cycles
    }

    @inline(__always)
    private static func and(cpu: CPU65816, value8: u8, value16: u16) {
        if cpu.aIs8() { let res = cpu.a8() & value8; cpu.setA8(res); cpu.updateNZ8(res) }
        else { let res = cpu.r.a & value16; cpu.setA(res); cpu.updateNZ16(res) }
    }

    @inline(__always)
    private static func and_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() { and(cpu: cpu, value8: cpu.read8(bank, addr), value16: 0) }
        else { and(cpu: cpu, value8: 0, value16: cpu.read16(bank, addr)) }
        return cycles
    }

    @inline(__always)
    private static func eor(cpu: CPU65816, value8: u8, value16: u16) {
        if cpu.aIs8() { let res = cpu.a8() ^ value8; cpu.setA8(res); cpu.updateNZ8(res) }
        else { let res = cpu.r.a ^ value16; cpu.setA(res); cpu.updateNZ16(res) }
    }

    @inline(__always)
    private static func eor_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() { eor(cpu: cpu, value8: cpu.read8(bank, addr), value16: 0) }
        else { eor(cpu: cpu, value8: 0, value16: cpu.read16(bank, addr)) }
        return cycles
    }

    @inline(__always)
        private static func adc(cpu: CPU65816, value8: u8, value16: u16) {
            if cpu.aIs8() {
                let a = cpu.a8()
                let m = value8
                let carry: u16 = cpu.flag(.carry) ? 1 : 0
                
                let resultBinary = u16(a) &+ u16(m) &+ carry
                cpu.setFlag(.overflow, (~(u16(a) ^ u16(m)) & (u16(a) ^ resultBinary) & 0x0080) != 0)
                cpu.updateNZ8(u8(truncatingIfNeeded: resultBinary))
                
                if cpu.flag(.decimal) {
                    var al = (a & 0x0F) &+ (m & 0x0F) &+ u8(carry)
                    if al > 9 { al &+= 6 }
                    var ah = (a & 0xF0) &+ (m & 0xF0) &+ (al > 0x0F ? 0x10 : 0)
                    
                    
                    if ah > 0x90 { ah &+= 0x60 }
                    
                    cpu.setFlag(.carry, ah > 0xFF)
                    cpu.setA8(u8(truncatingIfNeeded: (al & 0x0F) | (ah & 0xF0)))
                } else {
                    cpu.setFlag(.carry, resultBinary > 0xFF)
                    cpu.setA8(u8(truncatingIfNeeded: resultBinary))
                }
            } else {
                let a = cpu.r.a
                let m = value16
                let carry: u32 = cpu.flag(.carry) ? 1 : 0
                
                let resultBinary = u32(a) &+ u32(m) &+ carry
                cpu.setFlag(.overflow, (~(u32(a) ^ u32(m)) & (u32(a) ^ resultBinary) & 0x8000) != 0)
                cpu.updateNZ16(u16(truncatingIfNeeded: resultBinary))
                
                if cpu.flag(.decimal) {
                    var al = (a & 0x000F) &+ (m & 0x000F) &+ u16(carry)
                    if al > 9 { al &+= 6 }
                    var ah = (a & 0x00F0) &+ (m & 0x00F0) &+ (al > 0x0F ? 0x10 : 0)
                    if ah > 0x90 { ah &+= 0x60 }
                    
                    var bl = (a & 0x0F00) &+ (m & 0x0F00) &+ (ah > 0xFF ? 0x100 : 0)
                    if bl > 0x900 { bl &+= 0x600 }
                    var bh = (a & 0xF000) &+ (m & 0xF000) &+ (bl > 0xF00 ? 0x1000 : 0)
                    if bh > 0x9000 { bh &+= 0x6000 }
                    
                    cpu.setFlag(.carry, bh > 0xFFFF)
                    
                    let resultBCD = (al & 0x000F) | (ah & 0x00F0) | (bl & 0x0F00) | (bh & 0xF000)
                    cpu.setA(u16(truncatingIfNeeded: resultBCD))
                } else {
                    cpu.setFlag(.carry, resultBinary > 0xFFFF)
                    cpu.setA(u16(truncatingIfNeeded: resultBinary))
                }
            }
        }

    @inline(__always)
    private static func adc_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() { adc(cpu: cpu, value8: cpu.read8(bank, addr), value16: 0) }
        else { adc(cpu: cpu, value8: 0, value16: cpu.read16(bank, addr)) }
        return cycles
    }

    @inline(__always)
        private static func sbc(cpu: CPU65816, value8: u8, value16: u16) {
            if cpu.aIs8() {
                let a = cpu.a8()
                let m = value8
                let carry: Int = cpu.flag(.carry) ? 1 : 0
                let notM = ~m
                let binaryRes = Int(a) + Int(notM) + carry
                
                cpu.updateNZ8(u8(truncatingIfNeeded: binaryRes))

                let overflow = ((Int(a) ^ binaryRes) & (Int(notM) ^ binaryRes) & 0x80) != 0
                cpu.setFlag(.overflow, overflow)
                
                if cpu.flag(.decimal) {
                    let temp = Int(a) - Int(m) - (1 - carry)
                    var result = temp
                    if (a & 0x0F) < (m & 0x0F) + (1 - u8(carry)) {
                       result -= 6
                    }
                    if result < 0 {
                       result -= 0x60
                    }
                    
                    cpu.setFlag(.carry, temp >= 0)
                    cpu.setA8(u8(truncatingIfNeeded: result))
                } else {
                    cpu.setFlag(.carry, binaryRes > 0xFF)
                    cpu.setA8(u8(truncatingIfNeeded: binaryRes))
                }
            } else {
                let a = cpu.r.a
                let m = value16
                let carry: Int = cpu.flag(.carry) ? 1 : 0
                
                let notM = ~m
                let binaryRes = Int(a) + Int(notM) + carry
                
                cpu.updateNZ16(u16(truncatingIfNeeded: binaryRes))
                let overflow = ((Int(a) ^ binaryRes) & (Int(notM) ^ binaryRes) & 0x8000) != 0
                cpu.setFlag(.overflow, overflow)
                
                if cpu.flag(.decimal) {
                    let temp = Int(a) - Int(m) - (1 - carry)
                    var result = temp
                    if (a & 0x0F) < (m & 0x0F) + (1 - u16(carry)) { result -= 6 }
                    if (a & 0xF0) < (m & 0xF0) { result -= 0x60 }
                    if (a & 0x0F00) < (m & 0x0F00) { result -= 0x600 }
                    if (a & 0xF000) < (m & 0xF000) { result -= 0x6000 }
                    
                    cpu.setFlag(.carry, temp >= 0)
                    cpu.setA(u16(truncatingIfNeeded: result))
                } else {
                    cpu.setFlag(.carry, binaryRes > 0xFFFF)
                    cpu.setA(u16(truncatingIfNeeded: binaryRes))
                }
            }
        }

    @inline(__always)
    private static func sbc_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() { sbc(cpu: cpu, value8: cpu.read8(bank, addr), value16: 0) }
        else { sbc(cpu: cpu, value8: 0, value16: cpu.read16(bank, addr)) }
        return cycles
    }

    @inline(__always)
    private static func cmpA(cpu: CPU65816, value8: u8, value16: u16) {
        if cpu.aIs8() {
            let a = cpu.a8(); let m = value8; cpu.setFlag(.carry, a >= m)
            let diff = u8(truncatingIfNeeded: u16(a) &- u16(m)); cpu.updateNZ8(diff)
        } else {
            let a = cpu.r.a; let m = value16; cpu.setFlag(.carry, a >= m)
            let diff = a &- m; cpu.updateNZ16(diff)
        }
    }

    @inline(__always)
    private static func cmpA_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() { cmpA(cpu: cpu, value8: cpu.read8(bank, addr), value16: 0) }
        else { cmpA(cpu: cpu, value8: 0, value16: cpu.read16(bank, addr)) }
        return cycles
    }

    @inline(__always)
    private static func cmpX(cpu: CPU65816, value8: u8, value16: u16) {
        if cpu.xIs8() {
            let x = cpu.x8(); let m = value8; cpu.setFlag(.carry, x >= m)
            let diff = u8(truncatingIfNeeded: u16(x) &- u16(m)); cpu.updateNZ8(diff)
        } else {
            let x = cpu.r.x; let m = value16; cpu.setFlag(.carry, x >= m)
            let diff = x &- m; cpu.updateNZ16(diff)
        }
    }

    @inline(__always)
    private static func cmpX_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.xIs8() { cmpX(cpu: cpu, value8: cpu.read8(bank, addr), value16: 0) }
        else { cmpX(cpu: cpu, value8: 0, value16: cpu.read16(bank, addr)) }
        return cycles
    }

    @inline(__always)
    private static func cmpY(cpu: CPU65816, value8: u8, value16: u16) {
        if cpu.xIs8() {
            let y = cpu.y8(); let m = value8; cpu.setFlag(.carry, y >= m)
            let diff = u8(truncatingIfNeeded: u16(y) &- u16(m)); cpu.updateNZ8(diff)
        } else {
            let y = cpu.r.y; let m = value16; cpu.setFlag(.carry, y >= m)
            let diff = y &- m; cpu.updateNZ16(diff)
        }
    }

    @inline(__always)
    private static func cmpY_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.xIs8() { cmpY(cpu: cpu, value8: cpu.read8(bank, addr), value16: 0) }
        else { cmpY(cpu: cpu, value8: 0, value16: cpu.read16(bank, addr)) }
        return cycles
    }

    @inline(__always)
    private static func inc_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() { let v = cpu.read8(bank, addr) &+ 1; cpu.write8(bank, addr, v); cpu.updateNZ8(v) }
        else { let v = cpu.read16(bank, addr) &+ 1; cpu.write8(bank, addr, lo8(v)); cpu.write8(bank, addr &+ 1, hi8(v)); cpu.updateNZ16(v) }
        return cycles
    }

    @inline(__always)
    private static func dec_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() { let v = cpu.read8(bank, addr) &- 1; cpu.write8(bank, addr, v); cpu.updateNZ8(v) }
        else { let v = cpu.read16(bank, addr) &- 1; cpu.write8(bank, addr, lo8(v)); cpu.write8(bank, addr &+ 1, hi8(v)); cpu.updateNZ16(v) }
        return cycles
    }

    @inline(__always)
    private static func bitImmediate(cpu: CPU65816, value8: u8, value16: u16) {
        cpu.setFlag(.zero, cpu.aIs8() ? (cpu.a8() & value8 == 0) : (cpu.r.a & value16 == 0))
    }

    @inline(__always)
    private static func bit_mem(cpu: CPU65816, bank: u8, addr: u16, cycles: Int) -> Int {
        if cpu.aIs8() {
            let v = cpu.read8(bank, addr); cpu.setFlag(.zero, (cpu.a8() & v) == 0)
            cpu.setFlag(.negative, (v & 0x80) != 0); cpu.setFlag(.overflow, (v & 0x40) != 0)
        } else {
            let v = cpu.read16(bank, addr); cpu.setFlag(.zero, (cpu.r.a & v) == 0)
            cpu.setFlag(.negative, (v & 0x8000) != 0); cpu.setFlag(.overflow, (v & 0x4000) != 0)
        }
        return cycles
    }

    @inline(__always)
    private static func lda_mem(cpu: CPU65816, addr: u16, bank: u8, cycles: Int) -> Int {
        if cpu.aIs8() { let v = cpu.read8(bank, addr); cpu.setA8(v); cpu.updateNZ8(v) }
        else { let v = cpu.read16(bank, addr); cpu.setA(v); cpu.updateNZ16(v) }
        return cycles
    }

    @inline(__always)
    private static func ldx_mem(cpu: CPU65816, addr: u16, bank: u8, cycles: Int) -> Int {
        if cpu.xIs8() { let v = cpu.read8(bank, addr); cpu.setX8(v); cpu.updateNZ8(v) }
        else { let v = cpu.read16(bank, addr); cpu.setX(v); cpu.updateNZ16(v) }
        return cycles
    }

    @inline(__always)
    private static func ldy_mem(cpu: CPU65816, addr: u16, bank: u8, cycles: Int) -> Int {
        if cpu.xIs8() { let v = cpu.read8(bank, addr); cpu.setY8(v); cpu.updateNZ8(v) }
        else { let v = cpu.read16(bank, addr); cpu.setY(v); cpu.updateNZ16(v) }
        return cycles
    }

    @inline(__always)
    private static func sta_mem(cpu: CPU65816, addr: u16, bank: u8, cycles: Int) -> Int {
        if cpu.aIs8() { cpu.write8(bank, addr, cpu.a8()) }
        else { let v = cpu.r.a; cpu.write8(bank, addr, lo8(v)); cpu.write8(bank, addr &+ 1, hi8(v)) }
        return cycles
    }

    @inline(__always)
    private static func stx_mem(cpu: CPU65816, addr: u16, bank: u8, cycles: Int) -> Int {
        if cpu.xIs8() { cpu.write8(bank, addr, cpu.x8()) }
        else { let v = cpu.r.x; cpu.write8(bank, addr, lo8(v)); cpu.write8(bank, addr &+ 1, hi8(v)) }
        return cycles
    }

    @inline(__always)
    private static func sty_mem(cpu: CPU65816, addr: u16, bank: u8, cycles: Int) -> Int {
        if cpu.xIs8() { cpu.write8(bank, addr, cpu.y8()) }
        else { let v = cpu.r.y; cpu.write8(bank, addr, lo8(v)); cpu.write8(bank, addr &+ 1, hi8(v)) }
        return cycles
    }

    @inline(__always) static func mnemonic(opcode: u8) -> String {
        switch opcode {
        case 0xEA: return "NOP"
        case 0x42: return "WDM"
        case 0x04: return "TSB dp"
        case 0x0C: return "TSB abs"
        case 0x14: return "TRB dp"
        case 0x1C: return "TRB abs"
        case 0x78: return "SEI"
        case 0x58: return "CLI"
        case 0x18: return "CLC"
        case 0x38: return "SEC"
        case 0xD8: return "CLD"
        case 0xF8: return "SED"
        case 0xC2: return "REP #imm"
        case 0xE2: return "SEP #imm"
        case 0xFB: return "XCE"
        case 0xCB: return "WAI"
        case 0xDB: return "STP"
        case 0x00: return "BRK"
        case 0x02: return "COP"
        case 0x40: return "RTI"
        case 0x48: return "PHA"
        case 0x68: return "PLA"
        case 0xDA: return "PHX"
        case 0xFA: return "PLX"
        case 0x5A: return "PHY"
        case 0x7A: return "PLY"
        case 0x08: return "PHP"
        case 0x28: return "PLP"
        case 0x0B: return "PHD"
        case 0x2B: return "PLD"
        case 0x8B: return "PHB"
        case 0xAB: return "PLB"
        case 0x4B: return "PHK"
        case 0xAA: return "TAX"
        case 0x8A: return "TXA"
        case 0x5B: return "TCD"
        case 0x1B: return "TCS"
        case 0x7B: return "TDC"
        case 0x3B: return "TSC"
        case 0xA8: return "TAY"
        case 0x98: return "TYA"
        case 0xBA: return "TSX"
        case 0x9A: return "TXS"
        case 0x9B: return "TXY"
        case 0xBB: return "TYX"
        case 0x54: return "MVN"
        case 0x44: return "MVP"
        case 0xE8: return "INX"
        case 0xC8: return "INY"
        case 0xCA: return "DEX"
        case 0x88: return "DEY"
        case 0x1A: return "INC A"
        case 0x3A: return "DEC A"
        case 0x0A: return "ASL A"
        case 0x2A: return "ROL A"
        case 0x4A: return "LSR A"
        case 0x6A: return "ROR A"
        case 0x09: return "ORA #imm"
        case 0x05: return "ORA dp"
        case 0x15: return "ORA dp,X"
        case 0x01: return "ORA (dp,X)"
        case 0x11: return "ORA (dp),Y"
        case 0x12: return "ORA (dp)"
        case 0x07: return "ORA [dp]"
        case 0x17: return "ORA [dp],Y"
        case 0x03: return "ORA sr,S"
        case 0x13: return "ORA (sr,S),Y"
        case 0x0D: return "ORA abs"
        case 0x1D: return "ORA abs,X"
        case 0x19: return "ORA abs,Y"
        case 0x0F: return "ORA long"
        case 0x1F: return "ORA long,X"
        case 0x29: return "AND #imm"
        case 0x25: return "AND dp"
        case 0x35: return "AND dp,X"
        case 0x21: return "AND (dp,X)"
        case 0x31: return "AND (dp),Y"
        case 0x32: return "AND (dp)"
        case 0x27: return "AND [dp]"
        case 0x37: return "AND [dp],Y"
        case 0x23: return "AND sr,S"
        case 0x33: return "AND (sr,S),Y"
        case 0x2D: return "AND abs"
        case 0x3D: return "AND abs,X"
        case 0x39: return "AND abs,Y"
        case 0x2F: return "AND long"
        case 0x3F: return "AND long,X"
        case 0x49: return "EOR #imm"
        case 0x45: return "EOR dp"
        case 0x55: return "EOR dp,X"
        case 0x41: return "EOR (dp,X)"
        case 0x51: return "EOR (dp),Y"
        case 0x52: return "EOR (dp)"
        case 0x47: return "EOR [dp]"
        case 0x57: return "EOR [dp],Y"
        case 0x43: return "EOR sr,S"
        case 0x53: return "EOR (sr,S),Y"
        case 0x4D: return "EOR abs"
        case 0x5D: return "EOR abs,X"
        case 0x59: return "EOR abs,Y"
        case 0x4F: return "EOR long"
        case 0x5F: return "EOR long,X"
        case 0x69: return "ADC #imm"
        case 0x65: return "ADC dp"
        case 0x75: return "ADC dp,X"
        case 0x61: return "ADC (dp,X)"
        case 0x71: return "ADC (dp),Y"
        case 0x72: return "ADC (dp)"
        case 0x67: return "ADC [dp]"
        case 0x77: return "ADC [dp],Y"
        case 0x63: return "ADC sr,S"
        case 0x73: return "ADC (sr,S),Y"
        case 0x6D: return "ADC abs"
        case 0x7D: return "ADC abs,X"
        case 0x79: return "ADC abs,Y"
        case 0x6F: return "ADC long"
        case 0x7F: return "ADC long,X"
        case 0xE9, 0xEB: return "SBC #imm"
        case 0xE5: return "SBC dp"
        case 0xF5: return "SBC dp,X"
        case 0xE1: return "SBC (dp,X)"
        case 0xF1: return "SBC (dp),Y"
        case 0xF2: return "SBC (dp)"
        case 0xE7: return "SBC [dp]"
        case 0xF7: return "SBC [dp],Y"
        case 0xE3: return "SBC sr,S"
        case 0xF3: return "SBC (sr,S),Y"
        case 0xED: return "SBC abs"
        case 0xFD: return "SBC abs,X"
        case 0xF9: return "SBC abs,Y"
        case 0xEF: return "SBC long"
        case 0xFF: return "SBC long,X"
        case 0xC9: return "CMP #imm"
        case 0xC5: return "CMP dp"
        case 0xD5: return "CMP dp,X"
        case 0xC1: return "CMP (dp,X)"
        case 0xD1: return "CMP (dp),Y"
        case 0xD2: return "CMP (dp)"
        case 0xC7: return "CMP [dp]"
        case 0xD7: return "CMP [dp],Y"
        case 0xC3: return "CMP sr,S"
        case 0xD3: return "CMP (sr,S),Y"
        case 0xCD: return "CMP abs"
        case 0xDD: return "CMP abs,X"
        case 0xD9: return "CMP abs,Y"
        case 0xCF: return "CMP long"
        case 0xDF: return "CMP long,X"
        case 0xE0: return "CPX #imm"
        case 0xE4: return "CPX dp"
        case 0xEC: return "CPX abs"
        case 0xC0: return "CPY #imm"
        case 0xC4: return "CPY dp"
        case 0xCC: return "CPY abs"
        case 0x89: return "BIT #imm"
        case 0x24: return "BIT dp"
        case 0x34: return "BIT dp,X"
        case 0x2C: return "BIT abs"
        case 0x3C: return "BIT abs,X"
        case 0xA9: return "LDA #imm"
        case 0xA5: return "LDA dp"
        case 0xB5: return "LDA dp,X"
        case 0xA1: return "LDA (dp,X)"
        case 0xB1: return "LDA (dp),Y"
        case 0xB2: return "LDA (dp)"
        case 0xA7: return "LDA [dp]"
        case 0xB7: return "LDA [dp],Y"
        case 0xA3: return "LDA sr,S"
        case 0xB3: return "LDA (sr,S),Y"
        case 0xAD: return "LDA abs"
        case 0xBD: return "LDA abs,X"
        case 0xB9: return "LDA abs,Y"
        case 0xAF: return "LDA long"
        case 0xBF: return "LDA long,X"
        case 0xA2: return "LDX #imm"
        case 0xA6: return "LDX dp"
        case 0xB6: return "LDX dp,Y"
        case 0xAE: return "LDX abs"
        case 0xBE: return "LDX abs,Y"
        case 0xA0: return "LDY #imm"
        case 0xA4: return "LDY dp"
        case 0xB4: return "LDY dp,X"
        case 0xAC: return "LDY abs"
        case 0xBC: return "LDY abs,X"
        case 0x85: return "STA dp"
        case 0x95: return "STA dp,X"
        case 0x81: return "STA (dp,X)"
        case 0x91: return "STA (dp),Y"
        case 0x92: return "STA (dp)"
        case 0x87: return "STA [dp]"
        case 0x97: return "STA [dp],Y"
        case 0x83: return "STA sr,S"
        case 0x93: return "STA (sr,S),Y"
        case 0x8D: return "STA abs"
        case 0x9D: return "STA abs,X"
        case 0x99: return "STA abs,Y"
        case 0x8F: return "STA long"
        case 0x9F: return "STA long,X"
        case 0x86: return "STX dp"
        case 0x96: return "STX dp,Y"
        case 0x8E: return "STX abs"
        case 0x84: return "STY dp"
        case 0x94: return "STY dp,X"
        case 0x8C: return "STY abs"
        case 0x64: return "STZ dp"
        case 0x74: return "STZ dp,X"
        case 0x9C: return "STZ abs"
        case 0x9E: return "STZ abs,X"
        case 0x4C: return "JMP abs"
        case 0x6C: return "JMP (abs)"
        case 0x7C: return "JMP (abs,X)"
        case 0x5C: return "JML long"
        case 0xDC: return "JML [abs]"
        case 0x20: return "JSR abs"
        case 0xFC: return "JSR (abs,X)"
        case 0x22: return "JSL long"
        case 0x60: return "RTS"
        case 0x6B: return "RTL"
        case 0x80: return "BRA"
        case 0x82: return "BRL"
        case 0xF0: return "BEQ"
        case 0xD0: return "BNE"
        case 0x10: return "BPL"
        case 0x30: return "BMI"
        case 0x90: return "BCC"
        case 0xB0: return "BCS"
        case 0x50: return "BVC"
        case 0x70: return "BVS"
        case 0x06: return "ASL dp"
        case 0x16: return "ASL dp,X"
        case 0x0E: return "ASL abs"
        case 0x1E: return "ASL abs,X"
        case 0x46: return "LSR dp"
        case 0x56: return "LSR dp,X"
        case 0x4E: return "LSR abs"
        case 0x5E: return "LSR abs,X"
        case 0x26: return "ROL dp"
        case 0x36: return "ROL dp,X"
        case 0x2E: return "ROL abs"
        case 0x3E: return "ROL abs,X"
        case 0x66: return "ROR dp"
        case 0x76: return "ROR dp,X"
        case 0x6E: return "ROR abs"
        case 0x7E: return "ROR abs,X"
        case 0xE6: return "INC dp"
        case 0xF6: return "INC dp,X"
        case 0xEE: return "INC abs"
        case 0xFE: return "INC abs,X"
        case 0xC6: return "DEC dp"
        case 0xD6: return "DEC dp,X"
        case 0xCE: return "DEC abs"
        case 0xDE: return "DEC abs,X"
        case 0xF4: return "PEA"
        case 0xD4: return "PEI"
        case 0x62: return "PER"
        case 0xB8: return "CLV"
        default: return String(format: "OP $%02X", Int(opcode))
        }
    }
}
