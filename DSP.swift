import Foundation

final class DSP {
    private var regs: [u8] = Array(repeating: 0, count: 0x80)
    private var voices: [DSPVoice] = (0..<8).map { _ in DSPVoice() }

    private var mvolL: Int = 127
    private var mvolR: Int = 127
    private var evolL: Int = 0
    private var evolR: Int = 0
    private var efb: Int = 0

    private var eon: u8 = 0
    private var pmon: u8 = 0
    private var non: u8 = 0
    private var kon: u8 = 0

    private var esa: Int = 0
    private var edl: Int = 0
    private var echoPos: Int = 0
    private var fir: [Int] = Array(repeating: 0, count: 8)
    private var firHistL: [Int] = Array(repeating: 0, count: 8)
    private var firHistR: [Int] = Array(repeating: 0, count: 8)

    private var endx: u8 = 0
    private var flg: u8 = 0
    private var echoWriteDisable: Bool = false
    private var mute: Bool = false

    private var noiseLFSR: Int = 0x4000
    private var noiseCounter: Int = 0
    private var noisePeriod: Int = 4

    private var lastVoiceOut: [Int] = Array(repeating: 0, count: 8)
    
    func reset() {
        regs = Array(repeating: 0, count: 0x80)
        voices.forEach { $0.keyOff() }
        mvolL = 127; mvolR = 127
        evolL = 0; evolR = 0
        efb = 0
        eon = 0; pmon = 0; non = 0; kon = 0
        esa = 0; edl = 0; echoPos = 0
        fir = Array(repeating: 0, count: 8)
        firHistL = Array(repeating: 0, count: 8)
        firHistR = Array(repeating: 0, count: 8)
        endx = 0
        flg = 0
        echoWriteDisable = false
        mute = false
        noiseLFSR = 0x4000
        noiseCounter = 0
        noisePeriod = 4
    }

    func read(reg: Int) -> u8 {
        let r = reg & 0x7F
        if r == 0x7C {
            let v = endx
            endx = 0
            return v
        }
        return regs[r]
    }

    func write(reg: Int, value: u8) {
        let r = reg & 0x7F
        regs[r] = value

        let v = r >> 4
        let o = r & 0x0F
        if v < 8 {
            let voice = voices[v]
            switch o {
            case 0x00: voice.volL = Int(Int8(bitPattern: value))
            case 0x01: voice.volR = Int(Int8(bitPattern: value))
            case 0x02: voice.pitch = (voice.pitch & 0xFF00) | Int(value)
            case 0x03: voice.pitch = (voice.pitch & 0x00FF) | (Int(value) << 8)
            case 0x04: voice.sampleAddr = Int(value) << 8
            default: break
            }
        }

        switch r {
        case 0x0C: mvolL = Int(Int8(bitPattern: value))
        case 0x1C: mvolR = Int(Int8(bitPattern: value))
        case 0x2C: evolL = Int(Int8(bitPattern: value))
        case 0x3C: evolR = Int(Int8(bitPattern: value))
        case 0x4C:
            kon = value
            for i in 0..<8 where (value & (1 << i)) != 0 {
                voices[i].keyOn(sampleAddr: voices[i].sampleAddr)
            }
            if regs[0x4D] == 0 { eon = value }
        case 0x4D:
            eon = value
        case 0x5C:
            for i in 0..<8 where (value & (1 << i)) != 0 { voices[i].keyOff() }
        case 0x6D: esa = Int(value) << 8
        case 0x7D: edl = Int(value & 0x0F)
        case 0x0F...0x16:
            fir[r - 0x0F] = Int(Int8(bitPattern: value))
        case 0x2D: pmon = value
        case 0x3D: non = value
        case 0x6C:
            flg = value
            echoWriteDisable = (value & 0x20) != 0
            mute = (value & 0x40) != 0
            if (value & 0x80) != 0 {
                noiseLFSR = 0x4000
                noiseCounter = 0
                echoPos = 0
            }
            let n = Int(value & 0x1F)
            noisePeriod = max(1, 1 << (min(10, n >> 1)))
        default:
            break
        }
    }

    private func nextNoiseSample() -> Int {
        noiseCounter += 1
        if noiseCounter >= noisePeriod {
            noiseCounter = 0
            let bit = ((noiseLFSR ^ (noiseLFSR >> 1)) & 1)
            noiseLFSR = (noiseLFSR >> 1) | (bit << 14)
        }
        return ((noiseLFSR & 1) != 0) ? 16384 : -16384
    }

    func mix(readRAM: (Int)->u8, writeRAM: (Int, Int)->Void) -> (Int, Int) {
        let noise = nextNoiseSample()
        var newEndx: u8 = 0
        var dryL = 0
        var dryR = 0
        var echoInL = 0
        var echoInR = 0
        var currentOut = Array(repeating: 0, count: 8)

        for i in 0..<8 {
            voices[i].noiseEnabled = (non & (1 << i)) != 0
            let pitchDelta = (i > 0 && (pmon & (1 << i)) != 0) ? (lastVoiceOut[i - 1] >> 4) : 0
            let s = voices[i].nextSample(read: readRAM, pitchDelta: pitchDelta, noiseSample: noise)
            currentOut[i] = s
            if voices[i].endHitThisSample {
                newEndx |= (1 << i)
            }
            let vL = s * voices[i].volL
            let vR = s * voices[i].volR
            dryL += vL
            dryR += vR
            if (eon & (1 << i)) != 0 {
                echoInL += vL
                echoInR += vR
            }
        }

        lastVoiceOut = currentOut
        dryL >>= 7; dryR >>= 7
        echoInL >>= 7; echoInR >>= 7

        let echoAddr = (esa + echoPos) & 0xFFFF
        let echoL = Int(Int16(bitPattern: UInt16(readRAM(echoAddr) | (readRAM(echoAddr + 1) << 8))))
        let echoR = Int(Int16(bitPattern: UInt16(readRAM(echoAddr + 2) | (readRAM(echoAddr + 3) << 8))))

        firHistL.insert(echoL, at: 0); firHistL.removeLast()
        firHistR.insert(echoR, at: 0); firHistR.removeLast()

        var wetL = 0, wetR = 0
        for i in 0..<8 {
            wetL += firHistL[i] * fir[i]
            wetR += firHistR[i] * fir[i]
        }
        wetL >>= 6; wetR >>= 6

        if !echoWriteDisable {
            let fbL = echoInL + ((wetL * efb) >> 7)
            let fbR = echoInR + ((wetR * efb) >> 7)
            writeRAM(echoAddr, fbL & 0xFF)
            writeRAM(echoAddr + 1, (fbL >> 8) & 0xFF)
            writeRAM(echoAddr + 2, fbR & 0xFF)
            writeRAM(echoAddr + 3, (fbR >> 8) & 0xFF)
        }

        let echoBytes = max(4, edl * 0x800)
        echoPos = (echoPos + 4) % echoBytes
        endx |= newEndx
        if mute { return (0, 0) }

        let outL = ((dryL * mvolL) >> 7) + ((wetL * evolL) >> 7)
        let outR = ((dryR * mvolR) >> 7) + ((wetR * evolR) >> 7)

        return (
            max(-32768, min(32767, outL)),
            max(-32768, min(32767, outR))
        )
    }
}
