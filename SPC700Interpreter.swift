import Foundation

final class SPC700Interpreter {

    @inline(__always)
    private func dp(_ cpu: SPC700, _ apu: APU) -> u16 {
        let off = u16(cpu.fetch8(apu))
        return cpu.dpBase() | off
    }

    @inline(__always)
    private func dpX(_ cpu: SPC700, _ apu: APU) -> u16 {
        let off = u16(cpu.fetch8(apu))
        let addr = (off &+ u16(cpu.x)) & 0x00FF
        return cpu.dpBase() | addr
    }

    @inline(__always)
    private func dpY(_ cpu: SPC700, _ apu: APU) -> u16 {
        let off = u16(cpu.fetch8(apu))
        let addr = (off &+ u16(cpu.y)) & 0x00FF
        return cpu.dpBase() | addr
    }
    
    @inline(__always)
    private func abs16(_ cpu: SPC700, _ apu: APU) -> u16 {
        cpu.fetch16(apu)
    }

    @inline(__always)
    private func absX(_ cpu: SPC700, _ apu: APU) -> u16 {
        abs16(cpu, apu) &+ u16(cpu.x)
    }

    @inline(__always)
    private func absY(_ cpu: SPC700, _ apu: APU) -> u16 {
        abs16(cpu, apu) &+ u16(cpu.y)
    }

    @inline(__always)
    private func indX(_ cpu: SPC700, _ apu: APU) -> u16 {
        let base = (u16(cpu.fetch8(apu)) &+ u16(cpu.x)) & 0x00FF
        let lo = u16(apu.read8(cpu.dpBase() | base))
        let hi = u16(apu.read8(cpu.dpBase() | ((base &+ 1) & 0x00FF)))
        return lo | (hi << 8)
    }

    @inline(__always)
    private func indY(_ cpu: SPC700, _ apu: APU) -> u16 {
        let base = u16(cpu.fetch8(apu))
        let lo = u16(apu.read8(cpu.dpBase() | base))
        let hi = u16(apu.read8(cpu.dpBase() | ((base &+ 1) & 0x00FF)))
        return (lo | (hi << 8)) &+ u16(cpu.y)
    }

    @inline(__always)
    private func absBitOperand(_ cpu: SPC700, _ apu: APU) -> (addr: u16, bit: Int) {
        let op = cpu.fetch16(apu)
        let bit = Int((op >> 13) & 0x7)
        let addr = op & 0x1FFF
        return (addr, bit)
    }

    func step(cpu: SPC700, apu: APU, cycles: Int) {
        var debt = cycles
        while debt > 0 {
            let op = cpu.fetch8(apu)
            switch op {

            case 0x00: debt -= 2 // NOP

            // MOV A,#imm / X / Y
            case 0xE8: cpu.a = cpu.fetch8(apu); cpu.updateNZ(cpu.a); debt -= 2
            case 0xCD: cpu.x = cpu.fetch8(apu); cpu.updateNZ(cpu.x); debt -= 2
            case 0x8D: cpu.y = cpu.fetch8(apu); cpu.updateNZ(cpu.y); debt -= 2

            // MOV A, mem
            case 0xE4: cpu.a = apu.read8(dp(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 3
            case 0xF4: cpu.a = apu.read8(dpX(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 4
            case 0xE5: cpu.a = apu.read8(abs16(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 4
            case 0xF5: cpu.a = apu.read8(absX(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 5
            case 0xF6: cpu.a = apu.read8(absY(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 5
            case 0xE7: cpu.a = apu.read8(indX(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 6
            case 0xF8: cpu.x = apu.read8(dp(cpu, apu)); cpu.updateNZ(cpu.x); debt -= 3
            case 0xF7: cpu.a = apu.read8(indY(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 6

            // MOV mem, A
            case 0xC4: apu.write8(dp(cpu, apu), cpu.a); debt -= 4
            case 0xD4: apu.write8(dpX(cpu, apu), cpu.a); debt -= 5
            case 0xC5: apu.write8(abs16(cpu, apu), cpu.a); debt -= 5
            case 0xD8: apu.write8(dp(cpu, apu), cpu.x); debt -= 4
            case 0xD5: apu.write8(absX(cpu, apu), cpu.a); debt -= 6

            // ALU imm
            case 0x88: cpu.adc(cpu.fetch8(apu)); debt -= 2
            case 0xA8: cpu.sbc(cpu.fetch8(apu)); debt -= 2
            case 0x28: cpu.a &= cpu.fetch8(apu); cpu.updateNZ(cpu.a); debt -= 2
            case 0x08: cpu.a |= cpu.fetch8(apu); cpu.updateNZ(cpu.a); debt -= 2
            case 0x48: cpu.a ^= cpu.fetch8(apu); cpu.updateNZ(cpu.a); debt -= 2
            case 0x68: cpu.cmp(cpu.a, cpu.fetch8(apu)); debt -= 2

            // Memory ALU helpers
            case 0x24: cpu.a &= apu.read8(dp(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 3
            case 0x04: cpu.a |= apu.read8(dp(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 3
            case 0x44: cpu.a ^= apu.read8(dp(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 3
            case 0x64: cpu.cmp(cpu.a, apu.read8(dp(cpu, apu))); debt -= 3
            case 0x84: cpu.adc(apu.read8(dp(cpu, apu))); debt -= 3
            case 0xA4: cpu.sbc(apu.read8(dp(cpu, apu))); debt -= 3

            case 0x34: cpu.a &= apu.read8(dpX(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 4
            case 0x14: cpu.a |= apu.read8(dpX(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 4
            case 0x54: cpu.a ^= apu.read8(dpX(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 4
            case 0x74: cpu.cmp(cpu.a, apu.read8(dpX(cpu, apu))); debt -= 4
            case 0x94: cpu.adc(apu.read8(dpX(cpu, apu))); debt -= 4
            case 0xB4: cpu.sbc(apu.read8(dpX(cpu, apu))); debt -= 4

            case 0x25: cpu.a &= apu.read8(abs16(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 4
            case 0x05: cpu.a |= apu.read8(abs16(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 4
            case 0x45: cpu.a ^= apu.read8(abs16(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 4
            case 0x65: cpu.cmp(cpu.a, apu.read8(abs16(cpu, apu))); debt -= 4
            case 0x85: cpu.adc(apu.read8(abs16(cpu, apu))); debt -= 4
            case 0xA5: cpu.sbc(apu.read8(abs16(cpu, apu))); debt -= 4

            // (dp+X) and (dp)+Y ALU
            case 0x07: cpu.a |= apu.read8(indX(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 6
            case 0x27: cpu.a &= apu.read8(indX(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 6
            case 0x47: cpu.a ^= apu.read8(indX(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 6
            case 0x67: cpu.cmp(cpu.a, apu.read8(indX(cpu, apu))); debt -= 6
            case 0x87: cpu.adc(apu.read8(indX(cpu, apu))); debt -= 6
            case 0xA7: cpu.sbc(apu.read8(indX(cpu, apu))); debt -= 6

            case 0x17: cpu.a |= apu.read8(indY(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 6
            case 0x37: cpu.a &= apu.read8(indY(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 6
            case 0x57: cpu.a ^= apu.read8(indY(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 6
            case 0x77: cpu.cmp(cpu.a, apu.read8(indY(cpu, apu))); debt -= 6
            case 0x97: cpu.adc(apu.read8(indY(cpu, apu))); debt -= 6
            case 0xB7: cpu.sbc(apu.read8(indY(cpu, apu))); debt -= 6

            // RMW ops
            case 0xAB:
                let a = dp(cpu, apu); var v = apu.read8(a); v &+= 1; apu.write8(a, v); cpu.updateNZ(v); debt -= 4
            case 0xBB:
                let a = dpX(cpu, apu); var v = apu.read8(a); v &+= 1; apu.write8(a, v); cpu.updateNZ(v); debt -= 5
            case 0xAC:
                let a = abs16(cpu, apu); var v = apu.read8(a); v &+= 1; apu.write8(a, v); cpu.updateNZ(v); debt -= 6

            case 0x8B:
                let a = dp(cpu, apu); var v = apu.read8(a); v &-= 1; apu.write8(a, v); cpu.updateNZ(v); debt -= 4
            case 0x9B:
                let a = dpX(cpu, apu); var v = apu.read8(a); v &-= 1; apu.write8(a, v); cpu.updateNZ(v); debt -= 5
            case 0x8C:
                let a = abs16(cpu, apu); var v = apu.read8(a); v &-= 1; apu.write8(a, v); cpu.updateNZ(v); debt -= 6

            case 0x0B:
                let a = dp(cpu, apu); let r = cpu.asl(apu.read8(a)); apu.write8(a, r); debt -= 4
            case 0x1B:
                let a = dpX(cpu, apu); let r = cpu.asl(apu.read8(a)); apu.write8(a, r); debt -= 5
            case 0x0C:
                let a = abs16(cpu, apu); let r = cpu.asl(apu.read8(a)); apu.write8(a, r); debt -= 6

            case 0x4B:
                let a = dp(cpu, apu); let r = cpu.lsr(apu.read8(a)); apu.write8(a, r); debt -= 4
            case 0x5B:
                let a = dpX(cpu, apu); let r = cpu.lsr(apu.read8(a)); apu.write8(a, r); debt -= 5
            case 0x4C:
                let a = abs16(cpu, apu); let r = cpu.lsr(apu.read8(a)); apu.write8(a, r); debt -= 6

            case 0x2B:
                let a = dp(cpu, apu); let r = cpu.rol(apu.read8(a)); apu.write8(a, r); debt -= 4
            case 0x3B:
                let a = dpX(cpu, apu); let r = cpu.rol(apu.read8(a)); apu.write8(a, r); debt -= 5
            case 0x2C:
                let a = abs16(cpu, apu); let r = cpu.rol(apu.read8(a)); apu.write8(a, r); debt -= 6

            case 0x6B:
                let a = dp(cpu, apu); let r = cpu.ror(apu.read8(a)); apu.write8(a, r); debt -= 4
            case 0x7B:
                let a = dpX(cpu, apu); let r = cpu.ror(apu.read8(a)); apu.write8(a, r); debt -= 5
            case 0x6C:
                let a = abs16(cpu, apu); let r = cpu.ror(apu.read8(a)); apu.write8(a, r); debt -= 6

            // YA 16-bit ops
            case 0xBA: // MOVW YA,dp
                let a = dp(cpu, apu)
                let lo = u16(apu.read8(a))
                let hi = u16(apu.read8(a &+ 1))
                cpu.a = u8(lo & 0xFF)
                cpu.y = u8(hi & 0xFF)
                cpu.updateNZ(cpu.y)
                debt -= 5

            case 0xDA: // MOVW dp,YA
                let a = dp(cpu, apu)
                apu.write8(a, cpu.a)
                apu.write8(a &+ 1, cpu.y)
                debt -= 6

            case 0x7A: // ADDW YA,dp
                let a = dp(cpu, apu)
                let lo = u16(apu.read8(a))
                let hi = u16(apu.read8(a &+ 1))
                let m = (hi << 8) | lo
                let sum = Int(cpu.getYA()) + Int(m)
                cpu.setFlag(SPC700.C, sum > 0xFFFF)
                cpu.setYA(u16(sum & 0xFFFF))
                debt -= 6

            case 0x9A: // SUBW YA,dp
                let a = dp(cpu, apu)
                let lo = u16(apu.read8(a))
                let hi = u16(apu.read8(a &+ 1))
                let m = (hi << 8) | lo
                let diff = Int(cpu.getYA()) - Int(m)
                cpu.setFlag(SPC700.C, diff >= 0)
                cpu.setYA(u16(diff & 0xFFFF))
                debt -= 6

            case 0x5A: // CMPW YA,dp
                let a = dp(cpu, apu)
                let lo = u16(apu.read8(a))
                let hi = u16(apu.read8(a &+ 1))
                let m = (hi << 8) | lo
                let diff = Int(cpu.getYA()) - Int(m)
                cpu.setFlag(SPC700.C, diff >= 0)
                cpu.updateNZ(u8((diff >> 8) & 0xFF))
                debt -= 6

            // Absolute mem.bit ops
            case 0x0A:
                let (addr, bit) = absBitOperand(cpu, apu)
                let b = ((apu.read8(addr) >> bit) & 1) != 0
                cpu.setFlag(SPC700.C, cpu.flag(SPC700.C) || b)
                debt -= 5
            case 0x2A:
                let (addr, bit) = absBitOperand(cpu, apu)
                let b = ((apu.read8(addr) >> bit) & 1) == 0
                cpu.setFlag(SPC700.C, cpu.flag(SPC700.C) || b)
                debt -= 5
            case 0x4A:
                let (addr, bit) = absBitOperand(cpu, apu)
                let b = ((apu.read8(addr) >> bit) & 1) != 0
                cpu.setFlag(SPC700.C, cpu.flag(SPC700.C) && b)
                debt -= 4
            case 0x6A:
                let (addr, bit) = absBitOperand(cpu, apu)
                let b = ((apu.read8(addr) >> bit) & 1) == 0
                cpu.setFlag(SPC700.C, cpu.flag(SPC700.C) && b)
                debt -= 4
            case 0x8A:
                let (addr, bit) = absBitOperand(cpu, apu)
                let b = ((apu.read8(addr) >> bit) & 1) != 0
                cpu.setFlag(SPC700.C, cpu.flag(SPC700.C) != b)
                debt -= 5
            case 0xEA:
                let (addr, bit) = absBitOperand(cpu, apu)
                var v = apu.read8(addr); v ^= (1 << bit); apu.write8(addr, v)
                debt -= 5
            case 0xAA:
                let (addr, bit) = absBitOperand(cpu, apu)
                let b = ((apu.read8(addr) >> bit) & 1) != 0
                cpu.setFlag(SPC700.C, b)
                debt -= 4
            case 0xCA:
                let (addr, bit) = absBitOperand(cpu, apu)
                var v = apu.read8(addr)
                if cpu.flag(SPC700.C) { v |= (1 << bit) } else { v &= ~(1 << bit) }
                apu.write8(addr, v)
                debt -= 6

            // Control / flow (minimal)
            case 0x2F:
                let rel = Int8(bitPattern: cpu.fetch8(apu))
                cpu.pc &+= u16(bitPattern: Int16(rel))
                debt -= 4
            case 0xF0:
                let rel = Int8(bitPattern: cpu.fetch8(apu))
                if cpu.flag(SPC700.Z) { cpu.pc &+= u16(bitPattern: Int16(rel)); debt -= 4 } else { debt -= 2 }
            case 0xD0:
                let rel = Int8(bitPattern: cpu.fetch8(apu))
                if !cpu.flag(SPC700.Z) { cpu.pc &+= u16(bitPattern: Int16(rel)); debt -= 4 } else { debt -= 2 }
            case 0x3F:
                let t = cpu.fetch16(apu); cpu.push16(apu, cpu.pc); cpu.pc = t; debt -= 8
            case 0x6F:
                cpu.pc = cpu.pop16(apu); debt -= 5
            case 0x20: cpu.setFlag(SPC700.P, false); debt -= 2
            case 0x40: cpu.setFlag(SPC700.P, true); debt -= 2
            case 0x60: cpu.setFlag(SPC700.C, false); debt -= 2
            case 0x80: cpu.setFlag(SPC700.C, true); debt -= 2
            case 0xA0: cpu.setFlag(SPC700.I, true); debt -= 3
            case 0xC0: cpu.setFlag(SPC700.I, false); debt -= 3
            case 0xCB: // MOV dp,Y
                apu.write8(dp(cpu, apu), cpu.y)
                debt -= 4

            case 0xEB: // MOV Y,dp
                cpu.y = apu.read8(dp(cpu, apu)); cpu.updateNZ(cpu.y)
                debt -= 3
            case 0xBC: // INC A
                cpu.a &+= 1; cpu.updateNZ(cpu.a)
                debt -= 2

            case 0x9C: // DEC A
                cpu.a &-= 1; cpu.updateNZ(cpu.a)
                debt -= 2
            case 0xB0: // BCS rel
                let rel = Int8(bitPattern: cpu.fetch8(apu))
                if cpu.flag(SPC700.C) { cpu.pc &+= u16(bitPattern: Int16(rel)); debt -= 4 } else { debt -= 2 }

            case 0x90: // BCC rel
                let rel = Int8(bitPattern: cpu.fetch8(apu))
                if !cpu.flag(SPC700.C) { cpu.pc &+= u16(bitPattern: Int16(rel)); debt -= 4 } else { debt -= 2 }

            case 0x30: // BMI rel
                let rel = Int8(bitPattern: cpu.fetch8(apu))
                if cpu.flag(SPC700.N) { cpu.pc &+= u16(bitPattern: Int16(rel)); debt -= 4 } else { debt -= 2 }

            case 0x10: // BPL rel
                let rel = Int8(bitPattern: cpu.fetch8(apu))
                if !cpu.flag(SPC700.N) { cpu.pc &+= u16(bitPattern: Int16(rel)); debt -= 4 } else { debt -= 2 }

            case 0x2D: // PUSH A
                cpu.push8(apu, cpu.a)
                debt -= 4

            case 0x4D: // PUSH X
                cpu.push8(apu, cpu.x)
                debt -= 4

            case 0x6D: // PUSH Y
                cpu.push8(apu, cpu.y)
                debt -= 4

            case 0xAE: // POP A
                cpu.a = cpu.pop8(apu); cpu.updateNZ(cpu.a)
                debt -= 4

            case 0xCE: // POP X
                cpu.x = cpu.pop8(apu); cpu.updateNZ(cpu.x)
                debt -= 4

            case 0xEE: // POP Y
                cpu.y = cpu.pop8(apu); cpu.updateNZ(cpu.y)
                debt -= 4
            case 0x02...0x1F: // SET1/CLR1 dp.bit
                let bit = (op >> 1) & 7
                let isSet = (op & 1) != 0
                let addr = dp(cpu, apu)
                var v = apu.read8(addr)
                if isSet { v |= (1 << bit) } else { v &= ~(1 << bit) }
                apu.write8(addr, v)
                debt -= 4

            case 0x32...0x3F: // BBS/BBC dp.bit,rel
                let bit = (op >> 1) & 7
                let wantSet = (op & 1) != 0
                let addr = dp(cpu, apu)
                let v = apu.read8(addr)
                let rel = Int8(bitPattern: cpu.fetch8(apu))
                let isSet = ((v >> bit) & 1) != 0
                if isSet == wantSet {
                    cpu.pc &+= u16(bitPattern: Int16(rel))
                    debt -= 5
                } else {
                    debt -= 4
                }

            // Special ALU / decimal / halt
            case 0x9F: cpu.xcnA(); debt -= 5 // XCN A
            case 0xCF: cpu.mulYA(); debt -= 9 // MUL YA
            case 0x9E: cpu.divYAByX(); debt -= 12 // DIV YA, X
            case 0xDF: cpu.daaA(); debt -= 3 // DAA A
            case 0xBE: cpu.dasA(); debt -= 3 // DAS A
            case 0xEF: cpu.halt(.sleep); debt = 0 // SLEEP
            case 0xFF: cpu.halt(.stop); debt = 0 // STOP


            default:
                debt -= 2
            }
        }
    }
}
