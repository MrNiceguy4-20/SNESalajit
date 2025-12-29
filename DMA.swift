import Foundation

final class DMAEngine {

    struct DMAChannelDebugState {
        let index: Int
        let dmap: u8
        let bbad: u8
        let a1t: u16
        let a1b: u8
        let das: u16
        let a2a: u16
        let a2b: u8
        let ntr: u8

        let hdmaTableAddr: u16
        let hdmaBank: u8
        let hdmaLineCounter: u8
        let hdmaDoTransfer: Bool
    }

    struct DMADebugState {
        let channels: [DMAChannelDebugState]
    }

    func debugSnapshot() -> DMADebugState {
        let chs = channels.enumerated().map { (i, c) in
            DMAChannelDebugState(
                index: i,
                dmap: c.dmap,
                bbad: c.bbad,
                a1t: c.a1t,
                a1b: c.a1b,
                das: c.das,
                a2a: c.a2a,
                a2b: c.a2b,
                ntr: c.ntr,
                hdmaTableAddr: c.hdmaTableAddr,
                hdmaBank: c.hdmaBank,
                hdmaLineCounter: c.hdmaLineCounter,
                hdmaDoTransfer: c.hdmaDoTransfer
            )
        }
        return DMADebugState(channels: chs)
    }

    private(set) var channels: [DMAChannel] = Array(repeating: DMAChannel(), count: 8)

    private static let masterCyclesPerByte: Int = 8
    private static let masterCyclesPerChannelOverhead: Int = 8

    func reset() {
        for i in 0..<8 { channels[i].reset() }
    }

    func readReg(channel: Int, reg: Int) -> u8 {
        let ch = channels[channel]
        switch reg {
        case 0x0: return ch.dmap
        case 0x1: return ch.bbad
        case 0x2: return lo8(ch.a1t)
        case 0x3: return hi8(ch.a1t)
        case 0x4: return ch.a1b
        case 0x5: return lo8(ch.das)
        case 0x6: return hi8(ch.das)
        case 0x7: return lo8(ch.a2a)
        case 0x8: return hi8(ch.a2a)
        case 0x9: return ch.a2b
        case 0xA: return ch.ntr
        default:  return 0xFF
        }
    }

    func writeReg(channel: Int, reg: Int, value: u8) {
        switch reg {
        case 0x0: channels[channel].dmap = value
        case 0x1: channels[channel].bbad = value
        case 0x2: channels[channel].a1t = (channels[channel].a1t & 0xFF00) | u16(value)
        case 0x3: channels[channel].a1t = (channels[channel].a1t & 0x00FF) | (u16(value) << 8)
        case 0x4: channels[channel].a1b = value
        case 0x5: channels[channel].das = (channels[channel].das & 0xFF00) | u16(value)
        case 0x6: channels[channel].das = (channels[channel].das & 0x00FF) | (u16(value) << 8)
        case 0x7: channels[channel].a2a = (channels[channel].a2a & 0xFF00) | u16(value)
        case 0x8: channels[channel].a2a = (channels[channel].a2a & 0x00FF) | (u16(value) << 8)
        case 0x9: channels[channel].a2b = value
        case 0xA: channels[channel].ntr = value
        default: break
        }
    }

    @discardableResult
    func start(mask: u8, bus: Bus) -> Int {
        var totalBytes = 0
        var channelsRun = 0

        for ch in 0..<8 {
            if (mask & (1 << ch)) == 0 { continue }
            channelsRun += 1
            totalBytes += runChannel(ch, bus: bus)
        }

        if channelsRun == 0 { return 0 }
        return (totalBytes * DMAEngine.masterCyclesPerByte) + (channelsRun * DMAEngine.masterCyclesPerChannelOverhead)
    }

    private func runChannel(_ idx: Int, bus: Bus) -> Int {
        var ch = channels[idx]
        let mode = ch.transferMode
        let dirBtoA = ch.directionBtoA

        var remaining = Int(ch.das)
        if remaining == 0 { remaining = 0x10000 }

        var transferred = 0

        while remaining > 0 {
            let offsets = DMAEngine.transferOffsets(for: mode)
            for off in offsets {
                if remaining == 0 { break }

                let bOffset = (u16(ch.bbad) &+ u16(off)) & 0x00FF
                let b = u16(0x2100) &+ bOffset
                if dirBtoA {
                    let v = bus.read8_mmio(b)
                    let bank = ch.a1b
                    let addr = ch.a1t
                    bus.write8(bank: bank, addr: addr, value: v)
                } else {
                    let bank = ch.a1b
                    let addr = ch.a1t
                    let v = bus.read8_dma(bank: bank, addr: addr)
                    if v != 0 {
                        Log.debug("DMA write non-zero: $\(Hex.u8(v)) from $\(Hex.u8(bank)):\(Hex.u16(addr))")
                    }
                    bus.write8_mmio(b, value: v)
                }

                transferred += 1
                ch.advanceABus()
                remaining -= 1
            }
        }

        ch.das = 0
        channels[idx] = ch

        return transferred
    }

    func hdmaInit(mask: u8, bus: Bus) {
        _ = bus
        for ch in 0..<8 {
            if (mask & (1 << ch)) == 0 { continue }
            var c = channels[ch]
            c.hdmaTableAddr = c.a2a
            c.hdmaBank = c.a2b
            c.hdmaLineCounter = 0
            c.hdmaDoTransfer = false
            channels[ch] = c
        }
    }

    func hdmaStep(mask: u8, bus: Bus) {
        for ch in 0..<8 {
            if (mask & (1 << ch)) == 0 { continue }
            var c = channels[ch]

            if c.hdmaBank == 0 && c.hdmaTableAddr == 0 {
                c.hdmaTableAddr = c.a2a
                c.hdmaBank = c.a2b
            }

            if c.hdmaTableAddr == 0 && c.hdmaLineCounter == 0 {
                channels[ch] = c
                continue
            }

            if c.hdmaLineCounter == 0 {
                let desc = bus.read8_dma(bank: c.hdmaBank, addr: c.hdmaTableAddr)
                c.hdmaTableAddr &+= 1

                if desc == 0 {
                    c.hdmaTableAddr = 0
                    c.hdmaLineCounter = 0
                    c.hdmaDoTransfer = false
                    channels[ch] = c
                    continue
                }

                c.hdmaLineCounter = desc & 0x7F
                c.hdmaDoTransfer = (desc & 0x80) == 0
            }

            if c.hdmaDoTransfer && c.hdmaLineCounter > 0 {
                let mode = c.transferMode
                let offsets = DMAEngine.transferOffsets(for: mode)

                for off in offsets {
                    let data = bus.read8_dma(bank: c.hdmaBank, addr: c.hdmaTableAddr)
                    c.hdmaTableAddr &+= 1
                    let bOffset = (u16(c.bbad) &+ u16(off)) & 0x00FF
                    let b = u16(0x2100) &+ bOffset
                    bus.write8_mmio(b, value: data)
                }
            }

            if c.hdmaLineCounter > 0 {
                c.hdmaLineCounter &-= 1
            }

            channels[ch] = c
        }
    }

    private static func transferOffsets(for mode: Int) -> [Int] {
        switch mode & 7 {
        case 0: return [0]
        case 1: return [0, 1]
        case 2: return [0, 0]
        case 3: return [0, 0, 1, 1]
        case 4: return [0, 1, 2, 3]
        case 5: return [0, 0, 0, 0]
        case 6: return [0, 1]
        case 7: return [0, 1, 0, 1]
        default: return [0]
        }
    }
}
