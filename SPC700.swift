import Foundation

final class SPC700 {
    var a: u8 = 0
    var x: u8 = 0
    var y: u8 = 0
    var sp: u8 = 0xEF
    var pc: u16 = 0x0000
    var psw: u8 = 0x02

    static let N: u8 = 0x80
    static let V: u8 = 0x40
    static let P: u8 = 0x20
    static let B: u8 = 0x10
    static let H: u8 = 0x08
    static let I: u8 = 0x04
    static let Z: u8 = 0x02
    static let C: u8 = 0x01

    @inline(__always) func reset() {
        a = 0; x = 0; y = 0
        sp = 0xEF
        pc = 0xFFC0
        psw = 0x02
    }

    enum HaltReason { case none, sleep, stop }
    var haltReason: HaltReason = .none
    
    @inline(__always) var halted: Bool { haltReason != .none }
    @inline(__always) func halt(_ r: HaltReason) { haltReason = r }
    @inline(__always) func resume() { haltReason = .none }
    
    @inline(__always) func dpBase() -> u16 { (psw & SPC700.P) != 0 ? 0x0100 : 0x0000 }
    @inline(__always) func setFlag(_ mask: u8, _ on: Bool) { on ? (psw |= mask) : (psw &= ~mask) }
    @inline(__always) func flag(_ mask: u8) -> Bool { (psw & mask) != 0 }

    @inline(__always) func updateNZ(_ v: u8) {
        setFlag(SPC700.Z, v == 0)
        setFlag(SPC700.N, (v & 0x80) != 0)
    }

    @inline(__always) func xcnA() {
        a = (a >> 4) | (a << 4)
        updateNZ(a)
    }
    
    @inline(__always) func mulYA() {
        let prod = u16(y) * u16(a)
        a = u8(prod & 0xFF)
        y = u8(prod >> 8)
        updateNZ(y)
    }
    
    @inline(__always) func divYAByX() {
        let ya = getYA()
        setFlag(SPC700.H, (x & 0x0F) <= (y & 0x0F))
        if x == 0 {
            a = 0xFF; y = 0xFF
            setFlag(SPC700.V, true)
        } else {
            let q = ya / u16(x)
            let r = ya % u16(x)
            setFlag(SPC700.V, q > 0xFF)
            a = u8(q & 0xFF)
            y = u8(r & 0xFF)
        }
        updateNZ(a)
    }
    
    @inline(__always) func daaA() {
        var v = Int(a)
        if flag(SPC700.C) || v > 0x99 {
            v += 0x60
            setFlag(SPC700.C, true)
        }
        if flag(SPC700.H) || (v & 0x0F) > 0x09 {
            v += 0x06
        }
        a = u8(v & 0xFF)
        updateNZ(a)
    }
    
    @inline(__always) func dasA() {
        var v = Int(a)
        if !flag(SPC700.C) || v > 0x99 {
            v -= 0x60
            setFlag(SPC700.C, false)
        }
        if !flag(SPC700.H) || (v & 0x0F) > 0x09 {
            v -= 0x06
        }
        a = u8(v & 0xFF)
        updateNZ(a)
    }
    
    @inline(__always) func fetch8(_ apu: APU) -> u8 {
        let v = apu.read8(pc)
        pc &+= 1
        return v
    }

    @inline(__always) func fetch16(_ apu: APU) -> u16 {
        let lo = u16(fetch8(apu))
        let hi = u16(fetch8(apu))
        return lo | (hi << 8)
    }

    @inline(__always) func push8(_ apu: APU, _ v: u8) {
        apu.write8(0x0100 | u16(sp), v)
        sp &-= 1
    }

    @inline(__always) func pop8(_ apu: APU) -> u8 {
        sp &+= 1
        return apu.read8(0x0100 | u16(sp))
    }

    @inline(__always) func push16(_ apu: APU, _ v: u16) {
        push8(apu, u8(v >> 8))
        push8(apu, u8(v & 0xFF))
    }

    @inline(__always) func pop16(_ apu: APU) -> u16 {
        let lo = u16(pop8(apu))
        let hi = u16(pop8(apu))
        return lo | (hi << 8)
    }

    @inline(__always) func adc(_ v: u8) {
        let c = flag(SPC700.C) ? 1 : 0
        let sum = Int(a) + Int(v) + c
        setFlag(SPC700.H, ((a & 0x0F) + (v & 0x0F) + u8(c)) > 0x0F)
        setFlag(SPC700.V, (~(Int(a) ^ Int(v)) & (Int(a) ^ sum) & 0x80) != 0)
        setFlag(SPC700.C, sum > 0xFF)
        a = u8(sum & 0xFF)
        updateNZ(a)
    }

    @inline(__always) func sbc(_ v: u8) {
        let c = flag(SPC700.C) ? 1 : 0
        let diff = Int(a) - Int(v) - (1 - c)
        setFlag(SPC700.H, (a & 0x0F) >= ((v & 0x0F) + u8(1 - c)))
        setFlag(SPC700.V, ((Int(a) ^ Int(v)) & (Int(a) ^ diff) & 0x80) != 0)
        setFlag(SPC700.C, diff >= 0)
        a = u8(diff & 0xFF)
        updateNZ(a)
    }

    @inline(__always) func cmp(_ lhs: u8, _ rhs: u8) {
        let diff = Int(lhs) - Int(rhs)
        setFlag(SPC700.C, diff >= 0)
        updateNZ(u8(diff & 0xFF))
    }

    @inline(__always) func asl(_ v: u8) -> u8 {
        setFlag(SPC700.C, (v & 0x80) != 0)
        let r = v << 1
        updateNZ(r)
        return r
    }

    @inline(__always) func lsr(_ v: u8) -> u8 {
        setFlag(SPC700.C, (v & 1) != 0)
        let r = v >> 1
        updateNZ(r)
        return r
    }

    @inline(__always) func rol(_ v: u8) -> u8 {
        let cIn: u8 = flag(SPC700.C) ? 1 : 0
        setFlag(SPC700.C, (v & 0x80) != 0)
        let r = (v << 1) | cIn
        updateNZ(r)
        return r
    }

    @inline(__always) func ror(_ v: u8) -> u8 {
        let cIn: u8 = flag(SPC700.C) ? 0x80 : 0
        setFlag(SPC700.C, (v & 1) != 0)
        let r = (v >> 1) | cIn
        updateNZ(r)
        return r
    }

    @inline(__always) func getYA() -> u16 { (u16(y) << 8) | u16(a) }
    @inline(__always) func setYA(_ v: u16) {
        a = u8(v & 0xFF)
        y = u8(v >> 8)
        updateNZ(y)
    }
}
