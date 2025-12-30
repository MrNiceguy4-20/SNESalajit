import Foundation

final class DSPVoice {
    var volL: Int = 0
    var volR: Int = 0
    var pitch: Int = 0x1000
    var sampleAddr: Int = 0
    var active: Bool = false

    enum EnvState { case attack, decay, sustain, release, off }
    var envState: EnvState = .off

    private(set) var envLevel: Int = 0
    var sustainLevel: Int = 0x400
    var attackRate: Int = 4
    var decayRate: Int = 2
    var releaseRate: Int = 8

    private var envCounter: Int = 0
    private static let envPeriod = 32

    private var phase: Int = 0
    private var prev1: Int = 0
    private var prev2: Int = 0
    private var decoded: [Int] = []
    private var decodeIndex: Int = 0

    private var keyOnDelay: Int = 0
    private var loopAddr: Int = 0
    private var pendingEndNoLoop: Bool = false

    private(set) var endHitThisSample: Bool = false
    var noiseEnabled: Bool = false

    @inline(__always) func keyOn(sampleAddr: Int) {
        self.sampleAddr = sampleAddr
        self.loopAddr = sampleAddr
        active = true
        envState = .attack
        envLevel = 0
        phase = 0
        prev1 = 0
        prev2 = 0
        decoded.removeAll(keepingCapacity: true)
        decodeIndex = 0
        pendingEndNoLoop = false
        endHitThisSample = false
        keyOnDelay = 2
        envCounter = 0
    }

    @inline(__always) func keyOff() {
        if envState != .off { envState = .release }
    }

    @inline(__always) private func clockEnvelope() {
        envCounter += 1
        if envCounter < Self.envPeriod { return }
        envCounter = 0
        switch envState {
        case .attack:
            envLevel += attackRate
            if envLevel >= 0x7FF {
                envLevel = 0x7FF
                envState = .decay
            }
        case .decay:
            envLevel -= decayRate
            if envLevel <= sustainLevel {
                envLevel = sustainLevel
                envState = .sustain
            }
        case .sustain:
            break
        case .release:
            envLevel -= releaseRate
            if envLevel <= 0 {
                envLevel = 0
                envState = .off
                active = false
            }
        case .off:
            break
        }
    }

    @inline(__always) func nextSample(read: (Int)->u8, pitchDelta: Int = 0, noiseSample: Int = 0) -> Int {
        endHitThisSample = false
        guard active else { return 0 }

        if keyOnDelay > 0 {
            keyOnDelay -= 1
            return 0
        }

        clockEnvelope()

        phase &+= (pitch &+ pitchDelta)
        while phase >= 0x1000 {
            phase -= 0x1000
            if decodeIndex >= decoded.count {
                let header = read(sampleAddr)
                let data = (1...8).map { read(sampleAddr + $0) }
                sampleAddr += 9
                let endBit = (header & 0x01) != 0
                let loopBit = (header & 0x02) != 0
                decoded = BRRDecoder.decodeBlock(header: header, data: data, prev1: &prev1, prev2: &prev2)
                decodeIndex = 0
                if endBit {
                    endHitThisSample = true
                    if loopBit {
                        sampleAddr = loopAddr
                        pendingEndNoLoop = false
                    } else {
                        pendingEndNoLoop = true
                    }
                }
            }
        }

        let raw = noiseEnabled
            ? noiseSample
            : (decoded.isEmpty ? 0 : decoded[min(decodeIndex, decoded.count - 1)])

        let scaled = (raw * envLevel) >> 11
        decodeIndex += 1

        if pendingEndNoLoop && decodeIndex >= decoded.count {
            keyOff()
            pendingEndNoLoop = false
        }

        return scaled
    }
}
