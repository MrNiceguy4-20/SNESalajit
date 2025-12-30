import Foundation

final class PPURenderer {
    @inline(__always) func renderFrame(regs: PPURegisters, mem: PPUMemory) -> Framebuffer {
        var fb = Framebuffer(width: 256, height: 224, fill: 0x000000FF)

        if regs.forcedBlank {
            return fb
        }

        let backdropBGR = mem.readCGRAM16(colorIndex: 0)
        let backdropRGBA = applyBrightness(SNESColor.bgr555ToRGBA8(backdropBGR), brightness: regs.brightness)
        fb.pixels = Array(repeating: backdropRGBA, count: fb.width * fb.height)

        switch regs.bgMode {
        case 0, 1:
            renderMode1_BG123_4bpp(regs: regs, mem: mem, fb: &fb, backdropBGR: backdropBGR)
        default:
            break
        }

        return fb
    }

    private struct Candidate {
        let priority: Int
        let layer: PPURegisters.Layer
        let bgr555: u16
    }

    @inline(__always) private func renderMode1_BG123_4bpp(regs: PPURegisters, mem: PPUMemory, fb: inout Framebuffer, backdropBGR: u16) {
        let (bg1W, bg1H) = bgMapTileDimensions(sizeBits: regs.bg1ScreenSize)
        let (bg2W, bg2H) = bgMapTileDimensions(sizeBits: regs.bg2ScreenSize)
        let (bg3W, bg3H) = bgMapTileDimensions(sizeBits: regs.bg3ScreenSize)

        let bg1ScrollX = Int(regs.bg1hofs & 0x03FF)
        let bg1ScrollY = Int(regs.bg1vofs & 0x03FF)
        let bg2ScrollX = Int(regs.bg2hofs & 0x03FF)
        let bg2ScrollY = Int(regs.bg2vofs & 0x03FF)
        let bg3ScrollX = Int(regs.bg3hofs & 0x03FF)
        let bg3ScrollY = Int(regs.bg3vofs & 0x03FF)

        let bg3Base = regs.bg3Priority ? 2 : 0
        let bg2Base = 1
        let bg1Base = 2

        let fixed = regs.fixedColor()
        let fixedBGR: u16 = packBGR555(r: fixed.r, g: fixed.g, b: fixed.b)

        for y in 0..<fb.height {
            let bg1sy = (y + bg1ScrollY) % (bg1H * 8)
            let bg2sy = (y + bg2ScrollY) % (bg2H * 8)
            let bg3sy = (y + bg3ScrollY) % (bg3H * 8)

            let bg1tileY = bg1sy >> 3
            let bg2tileY = bg2sy >> 3
            let bg3tileY = bg3sy >> 3

            let bg1inY = bg1sy & 7
            let bg2inY = bg2sy & 7
            let bg3inY = bg3sy & 7

            for x in 0..<fb.width {
                var best: Candidate? = nil

                if regs.mainEnabled(.bg3) && regs.windowAllows(.bg3, x: x) {
                    if let c = fetchBG4bppCandidate(
                        layer: .bg3,
                        basePriority: bg3Base,
                        tilemapBase: regs.bg3TilemapBase,
                        tileDataBase: regs.bg3TileDataBase,
                        mapW: bg3W, mapH: bg3H,
                        scrollX: bg3ScrollX, tileY: bg3tileY, inY: bg3inY,
                        x: x,
                        regs: regs,
                        mem: mem
                    ) {
                        best = pickBest(best, c)
                    }
                }

                if regs.mainEnabled(.bg2) && regs.windowAllows(.bg2, x: x) {
                    if let c = fetchBG4bppCandidate(
                        layer: .bg2,
                        basePriority: bg2Base,
                        tilemapBase: regs.bg2TilemapBase,
                        tileDataBase: regs.bg2TileDataBase,
                        mapW: bg2W, mapH: bg2H,
                        scrollX: bg2ScrollX, tileY: bg2tileY, inY: bg2inY,
                        x: x,
                        regs: regs,
                        mem: mem
                    ) {
                        best = pickBest(best, c)
                    }
                }

                if regs.mainEnabled(.bg1) && regs.windowAllows(.bg1, x: x) {
                    if let c = fetchBG4bppCandidate(
                        layer: .bg1,
                        basePriority: bg1Base,
                        tilemapBase: regs.bg1TilemapBase,
                        tileDataBase: regs.bg1TileDataBase,
                        mapW: bg1W, mapH: bg1H,
                        scrollX: bg1ScrollX, tileY: bg1tileY, inY: bg1inY,
                        x: x,
                        regs: regs,
                        mem: mem
                    ) {
                        best = pickBest(best, c)
                    }
                }

                guard let chosen = best else { continue }

                var outBGR = chosen.bgr555
                if regs.colorMathApplies(chosen.layer) {
                    outBGR = applyColorMath(main: outBGR, subOrFixed: fixedBGR, sub: regs.colorMathSub, half: regs.colorMathHalf)
                }

                var rgba = SNESColor.bgr555ToRGBA8(outBGR)
                rgba = applyBrightness(rgba, brightness: regs.brightness)
                fb.set(x: x, y: y, rgba: rgba)
            }
        }
    }

    @inline(__always)
    private func pickBest(_ a: Candidate?, _ b: Candidate) -> Candidate {
        guard let a else { return b }
        if b.priority >= a.priority { return b }
        return a
    }

    @inline(__always) private func fetchBG4bppCandidate(
        layer: PPURegisters.Layer,
        basePriority: Int,
        tilemapBase: Int,
        tileDataBase: Int,
        mapW: Int,
        mapH: Int,
        scrollX: Int,
        tileY: Int,
        inY: Int,
        x: Int,
        regs: PPURegisters,
        mem: PPUMemory
    ) -> Candidate? {
        let sx = (x + scrollX) % (mapW * 8)
        let tileX = sx >> 3
        let inX = sx & 7

        let entryAddr = bgEntryAddress(tilemapBase: tilemapBase, tileX: tileX, tileY: tileY, mapW: mapW, mapH: mapH)
        let lo = mem.readVRAMByte(entryAddr)
        let hi = mem.readVRAMByte(entryAddr + 1)
        let entry = u16(lo) | (u16(hi) << 8)

        let tileNum = Int(entry & 0x03FF)
        let palNum = Int((entry >> 10) & 0x07)
        let prioBit = (entry & 0x2000) != 0
        let hflip = (entry & 0x4000) != 0
        let vflip = (entry & 0x8000) != 0

        let px = hflip ? (7 - inX) : inX
        let py = vflip ? (7 - inY) : inY

        let colorIndex = fetch4bppPixel(tileDataBase: tileDataBase, tileNum: tileNum, x: px, y: py, mem: mem)
        if colorIndex == 0 { return nil }

        let cgramIndex = palNum * 16 + colorIndex
        let bgr = mem.readCGRAM16(colorIndex: cgramIndex)

        let prio = basePriority + (prioBit ? 4 : 0)
        return Candidate(priority: prio, layer: layer, bgr555: bgr)
    }

    @inline(__always) private func bgMapTileDimensions(sizeBits: u8) -> (w: Int, h: Int) {
        switch sizeBits & 0x03 {
        case 0: return (32, 32)
        case 1: return (64, 32)
        case 2: return (32, 64)
        case 3: return (64, 64)
        default: return (32, 32)
        }
    }

    @inline(__always) private func bgEntryAddress(tilemapBase: Int, tileX: Int, tileY: Int, mapW: Int, mapH: Int) -> Int {
        let screensX = max(1, mapW / 32)
        let screensY = max(1, mapH / 32)

        let screenX = (tileX >> 5) % screensX
        let screenY = (tileY >> 5) % screensY

        let screenIndex = screenX + (screenY * screensX)
        let screenBase = tilemapBase + screenIndex * 0x800

        let localX = tileX & 31
        let localY = tileY & 31
        let entryIndex = localY * 32 + localX
        return screenBase + entryIndex * 2
    }

    @inline(__always) private func fetch4bppPixel(tileDataBase: Int, tileNum: Int, x: Int, y: Int, mem: PPUMemory) -> Int {
        let tileBase = tileDataBase + tileNum * 32
        let rowBase = tileBase + y * 2
        let p0 = mem.readVRAMByte(rowBase + 0)
        let p1 = mem.readVRAMByte(rowBase + 1)
        let p2 = mem.readVRAMByte(rowBase + 16 + 0)
        let p3 = mem.readVRAMByte(rowBase + 16 + 1)

        let bit = 7 - x
        let b0 = (p0 >> bit) & 1
        let b1 = (p1 >> bit) & 1
        let b2 = (p2 >> bit) & 1
        let b3 = (p3 >> bit) & 1

        return Int(b0 | (b1 << 1) | (b2 << 2) | (b3 << 3))
    }

    @inline(__always)
    private func applyColorMath(main: u16, subOrFixed: u16, sub: Bool, half: Bool) -> u16 {
        let (mr, mg, mb) = unpackBGR555(main)
        let (sr, sg, sb) = unpackBGR555(subOrFixed)

        var r, g, b: Int

        if sub {
            r = mr - sr
            g = mg - sg
            b = mb - sb
        } else {
            r = mr + sr
            g = mg + sg
            b = mb + sb
        }

        if half {
            r >>= 1
            g >>= 1
            b >>= 1
        }

        r = max(0, min(31, r))
        g = max(0, min(31, g))
        b = max(0, min(31, b))

        return packBGR555(r: r, g: g, b: b)
    }

    @inline(__always)
    private func unpackBGR555(_ v: u16) -> (r: Int, g: Int, b: Int) {
        let b = Int(v & 0x1F)
        let g = Int((v >> 5) & 0x1F)
        let r = Int((v >> 10) & 0x1F)
        return (r, g, b)
    }

    @inline(__always)
    private func packBGR555(r: Int, g: Int, b: Int) -> u16 {
        return u16((r & 31) << 10) | u16((g & 31) << 5) | u16(b & 31)
    }

    @inline(__always)
    private func applyBrightness(_ rgba: u32, brightness: u8) -> u32 {
        let br = Int(brightness & 0x0F)
        if br >= 15 { return rgba }
        if br == 0 { return 0x000000FF }

        let scale = br
        let r = Int((rgba >> 24) & 0xFF)
        let g = Int((rgba >> 16) & 0xFF)
        let b = Int((rgba >> 8) & 0xFF)
        let a = Int(rgba & 0xFF)

        let rr = (r * scale) / 15
        let gg = (g * scale) / 15
        let bb = (b * scale) / 15

        return (u32(rr) << 24) | (u32(gg) << 16) | (u32(bb) << 8) | u32(a)
    }
}
