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
        let p = (u16(cpu.fetch8(apu)) &+ u16(cpu.x)) & 0x00FF
        let lo = u16(apu.read8(cpu.dpBase() | p))
        let hi = u16(apu.read8(cpu.dpBase() | ((p &+ 1) & 0x00FF)))
        return lo | (hi << 8)
    }

    @inline(__always)
    private func indY(_ cpu: SPC700, _ apu: APU) -> u16 {
        let p = u16(cpu.fetch8(apu))
        let lo = u16(apu.read8(cpu.dpBase() | p))
        let hi = u16(apu.read8(cpu.dpBase() | ((p &+ 1) & 0x00FF)))
        let base = lo | (hi << 8)
        return base &+ u16(cpu.y)
    }

    @inline(__always)
    private func absBitOperand(_ cpu: SPC700, _ apu: APU) -> (addr: u16, bit: Int) {
        let op = cpu.fetch16(apu)
        let bit = Int((op >> 13) & 0x7)
        let addr = op & 0x1FFF
        return (addr, bit)
    }

    @inline(__always)
    private func readDP16(_ cpu: SPC700, _ apu: APU, _ off: u8) -> u16 {
        let lo = u16(apu.read8(cpu.dpBase() | u16(off)))
        let hi = u16(apu.read8(cpu.dpBase() | u16(off &+ 1)))
        return lo | (hi << 8)
    }

    @inline(__always)
    private func writeDP16(_ cpu: SPC700, _ apu: APU, _ off: u8, _ v: u16) {
        apu.write8(cpu.dpBase() | u16(off), u8(v & 0xFF))
        apu.write8(cpu.dpBase() | u16(off &+ 1), u8((v >> 8) & 0xFF))
    }
    
    @inline(__always) func step(cpu: SPC700, apu: APU, cycles: Int) {
        var debt = cycles
        while debt > 0 {
            let op = cpu.fetch8(apu)
            switch op {
            case 0x00: debt -= 2
            case 0xBD: cpu.sp = cpu.x; debt -= 2
            case 0xE8: cpu.a = cpu.fetch8(apu); cpu.updateNZ(cpu.a); debt -= 2
            case 0xCD: cpu.x = cpu.fetch8(apu); cpu.updateNZ(cpu.x); debt -= 2
            case 0x8D: cpu.y = cpu.fetch8(apu); cpu.updateNZ(cpu.y); debt -= 2
            case 0xDD: cpu.a = cpu.y; cpu.updateNZ(cpu.a); debt -= 2
            case 0x5D: cpu.x = cpu.a; cpu.updateNZ(cpu.x); debt -= 2
            case 0xE4: cpu.a = apu.read8(dp(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 3
            case 0xF4: cpu.a = apu.read8(dpX(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 4
            case 0xE5: cpu.a = apu.read8(abs16(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 4
            case 0xF5: cpu.a = apu.read8(absX(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 5
            case 0xF6: cpu.a = apu.read8(absY(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 5
            case 0xE7: cpu.a = apu.read8(indX(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 6
            case 0xF7: cpu.a = apu.read8(indY(cpu, apu)); cpu.updateNZ(cpu.a); debt -= 6
            case 0xEB: cpu.y = apu.read8(dp(cpu, apu)); cpu.updateNZ(cpu.y); debt -= 3
            case 0xCC: cpu.y = apu.read8(abs16(cpu, apu)); cpu.updateNZ(cpu.y); debt -= 4
            case 0x78:
                let imm = cpu.fetch8(apu)
                let addr = dp(cpu, apu)
                cpu.cmp(apu.read8(addr), imm)
                debt -= 5
            case 0x7E:
                let addr = dp(cpu, apu)
                cpu.cmp(cpu.y, apu.read8(addr))
                debt -= 3
            case 0xC4: apu.write8(dp(cpu, apu), cpu.a); debt -= 4
            case 0xD4: apu.write8(dpX(cpu, apu), cpu.a); debt -= 5
            case 0xC5: apu.write8(abs16(cpu, apu), cpu.a); debt -= 5
            case 0xD5: apu.write8(absX(cpu, apu), cpu.a); debt -= 6
            case 0xD6: apu.write8(absY(cpu, apu), cpu.a); debt -= 6
            case 0xC7: apu.write8(indX(cpu, apu), cpu.a); debt -= 7
            case 0xD7: apu.write8(indY(cpu, apu), cpu.a); debt -= 7
            case 0x8F:
                let imm = cpu.fetch8(apu)
                let addr = dp(cpu, apu)
                apu.write8(addr, imm)
                debt -= 5
            case 0xC6:
                let addr = cpu.dpBase() | u16(cpu.x)
                apu.write8(addr, cpu.a)
                debt -= 4
            case 0xAB:
                let addr = dp(cpu, apu)
                let v = apu.read8(addr) &+ 1
                apu.write8(addr, v)
                cpu.updateNZ(v)
                debt -= 4
            case 0xDA:
                writeDP16(cpu, apu, cpu.fetch8(apu), cpu.getYA())
                debt -= 5
            case 0xBA:
                cpu.setYA(readDP16(cpu, apu, cpu.fetch8(apu)))
                debt -= 5
            case 0xD8: apu.write8(dp(cpu, apu), cpu.x); debt -= 4
            case 0xF8: apu.write8(dpY(cpu, apu), cpu.x); debt -= 5
            case 0xD9: apu.write8(abs16(cpu, apu), cpu.x); debt -= 5
            case 0xCB: apu.write8(dp(cpu, apu), cpu.y); debt -= 4
            case 0xDB: apu.write8(dpX(cpu, apu), cpu.y); debt -= 5
            case 0x7A:
                let val = readDP16(cpu, apu, cpu.fetch8(apu))
                let ya = cpu.getYA()
                let sum = Int(ya) + Int(val)
                cpu.setFlag(SPC700.V, (~(Int(ya) ^ Int(val)) & (Int(ya) ^ sum) & 0x8000) != 0)
                cpu.setFlag(SPC700.C, sum > 0xFFFF)
                cpu.setFlag(SPC700.H, ((Int(ya) & 0x0FFF) + (Int(val) & 0x0FFF)) > 0x0FFF)
                cpu.setYA(u16(sum & 0xFFFF))
                debt -= 5
            case 0x9A:
                let val = readDP16(cpu, apu, cpu.fetch8(apu))
                let ya = cpu.getYA()
                let diff = Int(ya) - Int(val)
                cpu.setFlag(SPC700.V, ((Int(ya) ^ Int(val)) & (Int(ya) ^ diff) & 0x8000) != 0)
                cpu.setFlag(SPC700.C, diff >= 0)
                cpu.setFlag(SPC700.H, (Int(ya) & 0x0FFF) >= (Int(val) & 0x0FFF))
                cpu.setYA(u16(diff & 0xFFFF))
                debt -= 5
            case 0x5A:
                let val = readDP16(cpu, apu, cpu.fetch8(apu))
                let ya = cpu.getYA()
                let diff = Int(ya) - Int(val)
                cpu.setFlag(SPC700.C, diff >= 0)
                cpu.setFlag(SPC700.N, (diff & 0x8000) != 0)
                cpu.setFlag(SPC700.Z, (diff & 0xFFFF) == 0)
                debt -= 4
            case 0xBC: cpu.a &+= 1; cpu.updateNZ(cpu.a); debt -= 2
            case 0x3D: cpu.x &+= 1; cpu.updateNZ(cpu.x); debt -= 2
            case 0xFC: cpu.y &+= 1; cpu.updateNZ(cpu.y); debt -= 2
            case 0x9C: cpu.a &-= 1; cpu.updateNZ(cpu.a); debt -= 2
            case 0x1D: cpu.x &-= 1; cpu.updateNZ(cpu.x); debt -= 2
            case 0xDC: cpu.y &-= 1; cpu.updateNZ(cpu.y); debt -= 2
            case 0x60: cpu.setFlag(SPC700.C, false); debt -= 2
            case 0x80: cpu.setFlag(SPC700.C, true); debt -= 2
            case 0xED: cpu.setFlag(SPC700.C, !cpu.flag(SPC700.C)); debt -= 3
            case 0x20: cpu.setFlag(SPC700.P, false); debt -= 2
            case 0x40: cpu.setFlag(SPC700.P, true); debt -= 2
            case 0xC0: cpu.setFlag(SPC700.I, false); debt -= 3
            case 0xA0: cpu.setFlag(SPC700.I, true); debt -= 3
            case 0x2F:
                let rel = Int8(bitPattern: cpu.fetch8(apu))
                cpu.pc &+= u16(bitPattern: Int16(rel))
                debt -= 4
            case 0xF0:
                let rel = Int8(bitPattern: cpu.fetch8(apu))
                if cpu.flag(SPC700.Z) { cpu.pc &+= u16(bitPattern: Int16(rel)); debt -= 4 }
                else { debt -= 2 }
            case 0xD0:
                let rel = Int8(bitPattern: cpu.fetch8(apu))
                if !cpu.flag(SPC700.Z) { cpu.pc &+= u16(bitPattern: Int16(rel)); debt -= 4 }
                else { debt -= 2 }
            case 0xB0:
                let rel = Int8(bitPattern: cpu.fetch8(apu))
                if cpu.flag(SPC700.C) { cpu.pc &+= u16(bitPattern: Int16(rel)); debt -= 4 }
                else { debt -= 2 }
            case 0x90:
                let rel = Int8(bitPattern: cpu.fetch8(apu))
                if !cpu.flag(SPC700.C) { cpu.pc &+= u16(bitPattern: Int16(rel)); debt -= 4 }
                else { debt -= 2 }
            case 0x30:
                let rel = Int8(bitPattern: cpu.fetch8(apu))
                if cpu.flag(SPC700.N) { cpu.pc &+= u16(bitPattern: Int16(rel)); debt -= 4 }
                else { debt -= 2 }
            case 0x10:
                let rel = Int8(bitPattern: cpu.fetch8(apu))
                if !cpu.flag(SPC700.N) { cpu.pc &+= u16(bitPattern: Int16(rel)); debt -= 4 }
                else { debt -= 2 }
            case 0x70:
                let rel = Int8(bitPattern: cpu.fetch8(apu))
                if cpu.flag(SPC700.V) { cpu.pc &+= u16(bitPattern: Int16(rel)); debt -= 4 }
                else { debt -= 2 }
            case 0x50:
                let rel = Int8(bitPattern: cpu.fetch8(apu))
                if !cpu.flag(SPC700.V) { cpu.pc &+= u16(bitPattern: Int16(rel)); debt -= 4 }
                else { debt -= 2 }
            case 0x1F:
                let target = 0xFF00 | u16(cpu.fetch8(apu))
                cpu.push16(apu, cpu.pc)
                cpu.pc = target
                debt -= 6
            case 0x01, 0x11, 0x21, 0x31, 0x41, 0x51, 0x61, 0x71, 0x81, 0x91, 0xA1, 0xB1, 0xC1, 0xD1, 0xE1, 0xF1:
                let vector = 0xFFC0 | (u16(15 - (op >> 4)) << 1)
                let lo = u16(apu.read8(vector))
                let hi = u16(apu.read8(vector + 1))
                cpu.push16(apu, cpu.pc)
                cpu.pc = lo | (hi << 8)
                debt -= 8
            case 0x2D: cpu.push8(apu, cpu.a); debt -= 4
            case 0x4D: cpu.push8(apu, cpu.x); debt -= 4
            case 0x6D: cpu.push8(apu, cpu.y); debt -= 4
            case 0x0D: cpu.push8(apu, cpu.psw); debt -= 4
            case 0xAE: cpu.a = cpu.pop8(apu); debt -= 4
            case 0xCE: cpu.x = cpu.pop8(apu); debt -= 4
            case 0xEE: cpu.y = cpu.pop8(apu); cpu.updateNZ(cpu.y); debt -= 4
            case 0x0E:
                let addr = abs16(cpu, apu); let v = apu.read8(addr)
                cpu.updateNZ(cpu.a &- v)
                apu.write8(addr, v | cpu.a)
                debt -= 6
            case 0x4E:
                let addr = abs16(cpu, apu); let v = apu.read8(addr)
                cpu.updateNZ(cpu.a &- v)
                apu.write8(addr, v & ~cpu.a)
                debt -= 6
            case 0x02...0x1F:
                let bit = (op >> 1) & 7
                let isSet = (op & 1) != 0
                let addr = dp(cpu, apu)
                var v = apu.read8(addr)
                if isSet { v |= (1 << bit) } else { v &= ~(1 << bit) }
                apu.write8(addr, v)
                debt -= 4
            case 0x32...0x3F:
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
            case 0x9F: cpu.xcnA(); debt -= 5
            case 0xCF: cpu.mulYA(); debt -= 9
            case 0x9E: cpu.divYAByX(); debt -= 12
            case 0xDF: cpu.daaA(); debt -= 3
            case 0xBE: cpu.dasA(); debt -= 3
            case 0xEF: cpu.halt(.sleep); debt = 0
            case 0xFF: cpu.halt(.stop); debt = 0
            default: debt -= 2
            }
        }
    }
}
