import Foundation

final class PPURegisters {
    // Optional debug trace sink set by PPU.
    var traceHook: ((String) -> Void)? = nil
    var rdnmi: UInt8 = 0
    @inline(__always)
    private func hex8(_ v: u8) -> String { String(format: "$%02X", Int(v)) }
    @inline(__always)
    private func hex16(_ v: u16) -> String { String(format: "$%04X", Int(v)) }
    @inline(__always)
    private func trace(_ video: VideoTiming, _ s: String) {
        traceHook?("[SL:\(video.scanline) DOT:\(video.dot)] \(s)")
    }

    // MARK: - Display / mode
    private(set) var forcedBlank: Bool = true
    private(set) var brightness: u8 = 0

    private(set) var bgMode: u8 = 1
    private(set) var bg3Priority: Bool = false

    // MARK: - BG tilemap / tiles
    private(set) var bg1ScreenBase: u8 = 0
    private(set) var bg1ScreenSize: u8 = 0
    private(set) var bg2ScreenBase: u8 = 0
    private(set) var bg2ScreenSize: u8 = 0
    private(set) var bg3ScreenBase: u8 = 0
    private(set) var bg3ScreenSize: u8 = 0
    private(set) var bg4ScreenBase: u8 = 0
    private(set) var bg4ScreenSize: u8 = 0

    private(set) var bg1TileBase: u8 = 0
    private(set) var bg2TileBase: u8 = 0
    private(set) var bg3TileBase: u8 = 0
    private(set) var bg4TileBase: u8 = 0

    // MARK: - BG scroll
    private var bg1hofsLatch: u8 = 0
    private var bg1vofsLatch: u8 = 0
    private var bg2hofsLatch: u8 = 0
    private var bg2vofsLatch: u8 = 0
    private var bg3hofsLatch: u8 = 0
    private var bg3vofsLatch: u8 = 0
    private var bg4hofsLatch: u8 = 0
    private var bg4vofsLatch: u8 = 0

    private(set) var bg1hofs: u16 = 0
    private(set) var bg1vofs: u16 = 0
    private(set) var bg2hofs: u16 = 0
    private(set) var bg2vofs: u16 = 0
    private(set) var bg3hofs: u16 = 0
    private(set) var bg3vofs: u16 = 0
    private(set) var bg4hofs: u16 = 0
    private(set) var bg4vofs: u16 = 0

    // MARK: - Screen enable
    // $212C/$212D TM/TS
    private(set) var tmMain: u8 = 0
    private(set) var tsSub: u8 = 0

    // MARK: - Windowing
    // $2123-$2125: W12SEL/W34SEL/WOBJSEL
    private(set) var w12sel: u8 = 0
    private(set) var w34sel: u8 = 0
    private(set) var wobjsel: u8 = 0

    // $2126-$2129: window positions
    private(set) var wh0: u8 = 0
    private(set) var wh1: u8 = 0
    private(set) var wh2: u8 = 0
    private(set) var wh3: u8 = 0

    // $212A-$212B: window logic
    private(set) var wbglog: u8 = 0
    private(set) var wobjlog: u8 = 0

    // MARK: - Color math
    // $2130 CGWSEL, $2131 CGADSUB, $2132 COLDATA
    private(set) var cgwsel: u8 = 0
    private(set) var cgadsub: u8 = 0
    private(set) var coldata: u8 = 0
    private var fixedColorR: Int = 0
    private var fixedColorG: Int = 0
    private var fixedColorB: Int = 0

    // MARK: - VRAM
    private(set) var vmain: u8 = 0x80
    private(set) var vramAddr: u16 = 0
    private var vramReadBuffer: u16 = 0

    // MARK: - CGRAM
    private(set) var cgramAddr: u8 = 0
    private var cgramWriteLatch: u8? = nil
    private var cgramReadLatch: u16 = 0

    // MARK: - H/V latch ($2137 latch, read via $213C/$213D)
    private var hvLatchH: u16 = 0
    private var hvLatchV: u16 = 0
    private var hvLatchToggleH: Bool = false
    private var hvLatchToggleV: Bool = false

    func reset() {
        forcedBlank = true
        brightness = 0

        bgMode = 1
        bg3Priority = false

        bg1ScreenBase = 0; bg1ScreenSize = 0
        bg2ScreenBase = 0; bg2ScreenSize = 0
        bg3ScreenBase = 0; bg3ScreenSize = 0
        bg4ScreenBase = 0; bg4ScreenSize = 0

        bg1TileBase = 0; bg2TileBase = 0; bg3TileBase = 0; bg4TileBase = 0

        bg1hofsLatch = 0; bg1vofsLatch = 0
        bg2hofsLatch = 0; bg2vofsLatch = 0
        bg3hofsLatch = 0; bg3vofsLatch = 0
        bg4hofsLatch = 0; bg4vofsLatch = 0

        bg1hofs = 0; bg1vofs = 0
        bg2hofs = 0; bg2vofs = 0
        bg3hofs = 0; bg3vofs = 0
        bg4hofs = 0; bg4vofs = 0

        tmMain = 0
        tsSub = 0

        w12sel = 0; w34sel = 0; wobjsel = 0
        wh0 = 0; wh1 = 0; wh2 = 0; wh3 = 0
        wbglog = 0; wobjlog = 0

        cgwsel = 0
        cgadsub = 0
        coldata = 0
        fixedColorR = 0; fixedColorG = 0; fixedColorB = 0

        vmain = 0x80
        vramAddr = 0
        vramReadBuffer = 0

        cgramAddr = 0
        cgramWriteLatch = nil
        cgramReadLatch = 0

        hvLatchH = 0
        hvLatchV = 0
        hvLatchToggleH = false
        hvLatchToggleV = false
    }

    // MARK: - Read

    func read(addr: u16, mem: PPUMemory, openBus: u8, video: VideoTiming) -> u8 {
        trace(video, "R \(hex16(addr))")
        switch addr {
        case 0x2137:
            // SLHV is write-only on real HW; reads typically return open bus.
            return openBus

        case 0x2139:
            trace(video, "VMDATAL read @VRAM[\(hex16(vramAddr))]")
            // VMDATAL (low)
            return u8(truncatingIfNeeded: vramReadBuffer)

        case 0x213A:
            trace(video, "VMDATAH read @VRAM[\(hex16(vramAddr))]")
            // VMDATAH (high)
            let v = u8(truncatingIfNeeded: vramReadBuffer >> 8)
            advanceVRAMAddress()
            vramReadBuffer = mem.readVRAM16(wordAddress: mapVRAMWordAddress(vramAddr))
            return v

        case 0x213B:
            trace(video, "CGDATA read @CGRAM[\(hex8(cgramAddr))]")
            // CGDATA
            if (openBus & 1) == 0 {
                cgramReadLatch = mem.readCGRAM16(colorIndex: Int(cgramAddr))
                return u8(truncatingIfNeeded: cgramReadLatch)
            } else {
                let hi = u8(truncatingIfNeeded: cgramReadLatch >> 8)
                cgramAddr &+= 1
                return hi
            }

        case 0x213C:
            let out: u8 = !hvLatchToggleH
                ? u8(truncatingIfNeeded: hvLatchH)
                : u8(truncatingIfNeeded: hvLatchH >> 8)
            hvLatchToggleH.toggle()
            return out

        case 0x213D:
            let out: u8 = !hvLatchToggleV
                ? u8(truncatingIfNeeded: hvLatchV)
                : u8(truncatingIfNeeded: hvLatchV >> 8)
            hvLatchToggleV.toggle()
            return out

        default:
            return openBus
        }
    }

    // MARK: - Write

    func write(addr: u16, value: u8, mem: PPUMemory, openBus: inout u8, video: VideoTiming) {
        trace(video, "W \(hex16(addr)) = \(hex8(value))")
        switch addr {
        case 0x2100:
            forcedBlank = (value & 0x80) != 0
            brightness = value & 0x0F

        case 0x2105:
            bgMode = value & 0x07
            bg3Priority = (value & 0x08) != 0

        case 0x2107:
            bg1ScreenBase = (value >> 2) & 0x3F
            bg1ScreenSize = value & 0x03
        case 0x2108:
            bg2ScreenBase = (value >> 2) & 0x3F
            bg2ScreenSize = value & 0x03
        case 0x2109:
            bg3ScreenBase = (value >> 2) & 0x3F
            bg3ScreenSize = value & 0x03
        case 0x210A:
            bg4ScreenBase = (value >> 2) & 0x3F
            bg4ScreenSize = value & 0x03

        case 0x210B:
            bg1TileBase = value & 0x0F
            bg2TileBase = (value >> 4) & 0x0F

        case 0x210C:
            bg3TileBase = value & 0x0F
            bg4TileBase = (value >> 4) & 0x0F

        case 0x210D:
            let lo = value
            let hi = bg1hofsLatch
            bg1hofs = (u16(hi) << 8) | u16(lo)
            bg1hofsLatch = value

        case 0x210E:
            let lo = value
            let hi = bg1vofsLatch
            bg1vofs = (u16(hi) << 8) | u16(lo)
            bg1vofsLatch = value

        case 0x210F:
            let lo = value
            let hi = bg2hofsLatch
            bg2hofs = (u16(hi) << 8) | u16(lo)
            bg2hofsLatch = value

        case 0x2110:
            let lo = value
            let hi = bg2vofsLatch
            bg2vofs = (u16(hi) << 8) | u16(lo)
            bg2vofsLatch = value

        case 0x2111:
            let lo = value
            let hi = bg3hofsLatch
            bg3hofs = (u16(hi) << 8) | u16(lo)
            bg3hofsLatch = value

        case 0x2112:
            let lo = value
            let hi = bg3vofsLatch
            bg3vofs = (u16(hi) << 8) | u16(lo)
            bg3vofsLatch = value

        case 0x2113:
            let lo = value
            let hi = bg4hofsLatch
            bg4hofs = (u16(hi) << 8) | u16(lo)
            bg4hofsLatch = value

        case 0x2114:
            let lo = value
            let hi = bg4vofsLatch
            bg4vofs = (u16(hi) << 8) | u16(lo)
            bg4vofsLatch = value

        case 0x2115:
            vmain = value

        case 0x2116:
            vramAddr = (vramAddr & 0xFF00) | u16(value)
            vramReadBuffer = mem.readVRAM16(wordAddress: mapVRAMWordAddress(vramAddr))

        case 0x2117:
            vramAddr = (vramAddr & 0x00FF) | (u16(value) << 8)
            vramReadBuffer = mem.readVRAM16(wordAddress: mapVRAMWordAddress(vramAddr))

        case 0x2118:
            trace(video, "VMDATAL write = \(hex8(value)) @VRAM[\(hex16(vramAddr))]")
            mem.writeVRAMLow(wordAddress: mapVRAMWordAddress(vramAddr), value: value)
            if (vmain & 0x80) == 0 { advanceVRAMAddress() }

        case 0x2119:
            trace(video, "VMDATAH write = \(hex8(value)) @VRAM[\(hex16(vramAddr))]")
            mem.writeVRAMHigh(wordAddress: mapVRAMWordAddress(vramAddr), value: value)
            if (vmain & 0x80) != 0 { advanceVRAMAddress() }

        case 0x2121:
            cgramAddr = value
            cgramWriteLatch = nil

        case 0x2122:
            trace(video, "CGDATA write = \(hex8(value)) @CGRAM[\(hex8(cgramAddr))]")
            if let lo = cgramWriteLatch {
                let word = u16(lo) | (u16(value) << 8)
                mem.writeCGRAM16(colorIndex: Int(cgramAddr), value: word)
                cgramAddr &+= 1
                cgramWriteLatch = nil
            } else {
                cgramWriteLatch = value
            }

        case 0x212C: tmMain = value
        case 0x212D: tsSub = value

        case 0x2123: w12sel = value
        case 0x2124: w34sel = value
        case 0x2125: wobjsel = value
        case 0x2126: wh0 = value
        case 0x2127: wh1 = value
        case 0x2128: wh2 = value
        case 0x2129: wh3 = value
        case 0x212A: wbglog = value
        case 0x212B: wobjlog = value

        case 0x2130: cgwsel = value
        case 0x2131: cgadsub = value
        case 0x2132:
            coldata = value
            applyFixedColorComponent(value)

        case 0x2137:
            hvLatchH = u16(video.dot)
            hvLatchV = u16(video.scanline)
            hvLatchToggleH = false
            hvLatchToggleV = false

        default:
            break
        }

        openBus = value
    }

    // MARK: - Helpers used by renderer

    enum Layer { case bg1, bg2, bg3, bg4, obj, color }

    @inline(__always)
    func mainEnabled(_ layer: Layer) -> Bool {
        switch layer {
        case .bg1: return (tmMain & 0x01) != 0
        case .bg2: return (tmMain & 0x02) != 0
        case .bg3: return (tmMain & 0x04) != 0
        case .bg4: return (tmMain & 0x08) != 0
        case .obj: return (tmMain & 0x10) != 0
        case .color: return true
        }
    }

    @inline(__always)
    func subEnabled(_ layer: Layer) -> Bool {
        switch layer {
        case .bg1: return (tsSub & 0x01) != 0
        case .bg2: return (tsSub & 0x02) != 0
        case .bg3: return (tsSub & 0x04) != 0
        case .bg4: return (tsSub & 0x08) != 0
        case .obj: return (tsSub & 0x10) != 0
        case .color: return true
        }
    }

    func windowAllows(_ layer: Layer, x: Int) -> Bool {
        let sel = windowSel(for: layer)
        let w1en = (sel & 0x02) != 0
        let w1inv = (sel & 0x01) != 0
        let w2en = (sel & 0x08) != 0
        let w2inv = (sel & 0x04) != 0

        if !w1en && !w2en { return true }

        let in1 = w1en ? inWindow(x: x, left: Int(wh0), right: Int(wh1), invert: w1inv) : false
        let in2 = w2en ? inWindow(x: x, left: Int(wh2), right: Int(wh3), invert: w2inv) : false

        let logic = windowLogic(for: layer)
        let inside: Bool
        switch logic {
        case 0: inside = in1 || in2
        case 1: inside = in1 && in2
        case 2: inside = (in1 != in2)
        default: inside = !(in1 != in2)
        }

        return !inside
    }

    var colorMathSub: Bool { (cgadsub & 0x80) != 0 }
    var colorMathHalf: Bool { (cgadsub & 0x40) != 0 }

    func colorMathApplies(_ layer: Layer) -> Bool {
        switch layer {
        case .bg1: return (cgadsub & 0x01) != 0
        case .bg2: return (cgadsub & 0x02) != 0
        case .bg3: return (cgadsub & 0x04) != 0
        case .bg4: return (cgadsub & 0x08) != 0
        case .obj: return (cgadsub & 0x10) != 0
        case .color: return false
        }
    }

    func fixedColor() -> (r: Int, g: Int, b: Int) { (fixedColorR, fixedColorG, fixedColorB) }

    // MARK: - Private

    private func advanceVRAMAddress() {
        // VMAIN ($2115) bits 0-1 select increment size in *words*.
        // 00: +1, 01: +32, 10: +128, 11: +128.
        let inc: u16
        switch vmain & 0x03 {
        case 0x00: inc = 1
        case 0x01: inc = 32
        default:   inc = 128
        }
        vramAddr &+= inc
    }

    /// VRAM address remapping selected by VMAIN ($2115) bits 2-3.
    /// The SNES PPU applies this remap to the internal *word* address.
    @inline(__always)
    private func mapVRAMWordAddress(_ addr: u16) -> u16 {
        switch (vmain >> 2) & 0x03 {
        case 0x00:
            return addr
        case 0x01:
            // 8x8 tiles (32-byte rows): swap A4-A7 with A8-A11 in groups.
            // Common for planar tile uploads.
            return (addr & 0xFF00) | ((addr & 0x00E0) << 3) | (addr & 0x001F)
        case 0x02:
            // 16-byte rows
            return (addr & 0xFE00) | ((addr & 0x01C0) << 3) | (addr & 0x003F)
        default:
            // 8-byte rows
            return (addr & 0xFC00) | ((addr & 0x0380) << 3) | (addr & 0x007F)
        }
    }

    private func applyFixedColorComponent(_ v: u8) {
        let intensity = Int(v & 0x1F)
        if (v & 0x20) != 0 { fixedColorB = intensity }
        if (v & 0x40) != 0 { fixedColorG = intensity }
        if (v & 0x80) != 0 { fixedColorR = intensity }
    }

    @inline(__always)
    private func inWindow(x: Int, left: Int, right: Int, invert: Bool) -> Bool {
        let xx = x & 0xFF
        let inside = xx >= left && xx <= right
        return invert ? !inside : inside
    }

    @inline(__always)
    private func windowSel(for layer: Layer) -> u8 {
        switch layer {
        case .bg1: return w12sel & 0x0F
        case .bg2: return (w12sel >> 4) & 0x0F
        case .bg3: return w34sel & 0x0F
        case .bg4: return (w34sel >> 4) & 0x0F
        case .obj: return wobjsel & 0x0F
        case .color: return (wobjsel >> 4) & 0x0F
        }
    }

    @inline(__always)
    private func windowLogic(for layer: Layer) -> Int {
        let v: u8
        switch layer {
        case .bg1: v = wbglog & 0x03
        case .bg2: v = (wbglog >> 2) & 0x03
        case .bg3: v = (wbglog >> 4) & 0x03
        case .bg4: v = (wbglog >> 6) & 0x03
        case .obj: v = wobjlog & 0x03
        case .color: v = (wobjlog >> 2) & 0x03
        }
        return Int(v)
    }

    // MARK: - Derived bases for renderer
    var bg1TileDataBase: Int { Int(bg1TileBase) * 0x1000 }
    var bg2TileDataBase: Int { Int(bg2TileBase) * 0x1000 }
    var bg3TileDataBase: Int { Int(bg3TileBase) * 0x1000 }
    var bg4TileDataBase: Int { Int(bg4TileBase) * 0x1000 }

    var bg1TilemapBase: Int { Int(bg1ScreenBase) * 0x400 }
    var bg2TilemapBase: Int { Int(bg2ScreenBase) * 0x400 }
    var bg3TilemapBase: Int { Int(bg3ScreenBase) * 0x400 }
    var bg4TilemapBase: Int { Int(bg4ScreenBase) * 0x400 }
}
