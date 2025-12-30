import Foundation

struct DMAChannel {
    var dmap: u8 = 0
    var bbad: u8 = 0
    var a1t: u16 = 0
    var a1b: u8 = 0
    var das: u16 = 0
    var a2a: u16 = 0
    var dasb: u8 = 0
    var a2b: u8 = 0
    var ntr: u8 = 0

    var hdmaTableAddr: u16 = 0
    var hdmaBank: u8 = 0
    var hdmaLineCounter: u8 = 0
    var hdmaDoTransfer: Bool = false

    @inline(__always) mutating func reset() {
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

    @inline(__always) mutating func advanceABus() {
        if fixed { return }
        let delta: Int32 = decrement ? -1 : 1
        var full = Int32((Int32(a1b) << 16) | Int32(a1t))
        full = (full + delta) & 0x00FF_FFFF
        a1t = u16(full & 0xFFFF)
        a1b = u8((full >> 16) & 0xFF)
    }
}
