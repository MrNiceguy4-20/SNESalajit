import Foundation

/// One DMA/HDMA channel register file (mirrors $43x0-$43xF).
struct DMAChannel {
    // $43x0 DMAP
    // bits: 0-2 transfer mode, 3 fixed, 4 inc/dec (0=inc,1=dec), 7 direction (0=A->B,1=B->A)
    var dmap: u8 = 0

    // $43x1 BBAD
    var bbad: u8 = 0

    // $43x2-$43x4 A1T (A-bus address 24-bit)
    var a1t: u16 = 0
    var a1b: u8 = 0

    // $43x5-$43x6 DAS (transfer size)
    var das: u16 = 0

    // $43x7-$43x8 DASB / A2A (HDMA table address) – used by HDMA
    var a2a: u16 = 0
    var dasb: u8 = 0

    // $43x9 A2B (HDMA bank) – used by HDMA
    var a2b: u8 = 0

    // $43xA NLTR (HDMA line counter) – used by HDMA runtime
    var ntr: u8 = 0

    // $43xB-$43xF unused/open bus
    // Runtime state
    var hdmaTableAddr: u16 = 0
    var hdmaBank: u8 = 0
    var hdmaLineCounter: u8 = 0
    var hdmaDoTransfer: Bool = false

    mutating func reset() {
        dmap = 0
        bbad = 0
        a1t = 0
        a1b = 0
        das = 0
        a2a = 0
        dasb = 0
        a2b = 0
        ntr = 0

        hdmaTableAddr = 0
        hdmaBank = 0
        hdmaLineCounter = 0
        hdmaDoTransfer = false
    }

    var transferMode: Int { Int(dmap & 0x07) }
    var fixed: Bool { (dmap & 0x08) != 0 }
    var decrement: Bool { (dmap & 0x10) != 0 }
    var directionBtoA: Bool { (dmap & 0x80) != 0 }

    var aBusAddress24: u32 {
        (u32(a1b) << 16) | u32(a1t)
    }

    mutating func advanceABus() {
        if fixed { return }
        let delta: Int32 = decrement ? -1 : 1
        var full = Int32((Int32(a1b) << 16) | Int32(a1t))
        full = (full + delta) & 0x00FF_FFFF
        a1t = u16(full & 0xFFFF)
        a1b = u8((full >> 16) & 0xFF)
    }

}
