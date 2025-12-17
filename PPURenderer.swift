import Foundation

/// Phase 8.4 renderer:
/// - Mode 0/1 BG1/BG2/BG3 (4bpp) with TM + window mask + priority
/// - OBJ (4bpp) with per-scanline evaluation (32 sprites / 34 tiles) + overflow flags
/// - Basic fixed-color math + brightness
final class PPURenderer {

    func renderFrame(regs: PPURegisters, mem: PPUMemory) -> Framebuffer {
        var fb = Framebuffer(width: 256, height: 224, fill: .rgba(0, 0, 0, 0xFF))

        // Reset overflow flags for the frame (latched if any scanline overflows).
        regs.clearObjOverflowFlags()

        if regs.forcedBlank {
            return fb
        }

        let backdropBGR = mem.readCGRAM16(colorIndex: 0)
        let backdropRGBA = applyBrightness(SNESColor.bgr555ToRGBA8(backdropBGR), brightness: regs.brightness)
        fb.pixels = Array(repeating: backdropRGBA, count: fb.width * fb.height)

        if regs.bgMode == 0 || regs.bgMode == 1 {
            renderMode01(regs: regs, mem: mem, fb: &fb, backdropBGR: backdropBGR)
        }

        return fb
    }

    // MARK: - Mode 0/1 compositing

    private struct Candidate {
        let priority: Int
        let layer: PPURegisters.Layer
        let bgr555: u16
    }

    private struct Sprite {
        let index: Int
        let x: Int
        let y: Int
        let w: Int
        let h: Int
        let tile: Int
        let pal: Int
        let prio: Int
        let hflip: Bool
        let vflip: Bool
        let nameBase: Int
    }

    private func renderMode01(regs: PPURegisters, mem: PPUMemory, fb: inout Framebuffer, backdropBGR: u16) {
        let (bg1W, bg1H) = bgMapTileDimensions(sizeBits: regs.bg1ScreenSize)
        let (bg2W, bg2H) = bgMapTileDimensions(sizeBits: regs.bg2ScreenSize)
        let (bg3W, bg3H) = bgMapTileDimensions(sizeBits: regs.bg3ScreenSize)

        let bg1ScrollX = Int(regs.bg1hofs & 0x03FF)
        let bg1ScrollY = Int(regs.bg1vofs & 0x03FF)
        let bg2ScrollX = Int(regs.bg2hofs & 0x03FF)
        let bg2ScrollY = Int(regs.bg2vofs & 0x03FF)
        let bg3ScrollX = Int(regs.bg3hofs & 0x03FF)
        let bg3ScrollY = Int(regs.bg3vofs & 0x03FF)

        // Approx BG base priorities
        let bg3Base = regs.bg3Priority ? 2 : 0
        let bg2Base = 1
        let bg1Base = 2

        let fixed = regs.fixedColor()
        let fixedBGR: u16 = packBGR555(r: fixed.r, g: fixed.g, b: fixed.b)

        for y in 0..<fb.height {
            // Per-scanline OBJ evaluation (Phase 8.4)
            let sprites = regs.mainEnabled(.obj) ? evaluateSpritesForScanline(y: y, regs: regs, mem: mem) : []

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

                // BG3
                if regs.mainEnabled(.bg3) && regs.windowAllows(.bg3, x: x) {
                    if let c = fetchBG4bppCandidate(
                        layer: .bg3,
                        basePriority: bg3Base,
                        tilemapBase: regs.bg3TilemapBase,
                        tileDataBase: regs.bg3TileDataBase,
                        mapW: bg3W, mapH: bg3H,
                        scrollX: bg3ScrollX, tileY: bg3tileY, inY: bg3inY,
                        x: x,
                        mem: mem
                    ) { best = pickBest(best, c) }
                }

                // BG2
                if regs.mainEnabled(.bg2) && regs.windowAllows(.bg2, x: x) {
                    if let c = fetchBG4bppCandidate(
                        layer: .bg2,
                        basePriority: bg2Base,
                        tilemapBase: regs.bg2TilemapBase,
                        tileDataBase: regs.bg2TileDataBase,
                        mapW: bg2W, mapH: bg2H,
                        scrollX: bg2ScrollX, tileY: bg2tileY, inY: bg2inY,
                        x: x,
                        mem: mem
                    ) { best = pickBest(best, c) }
                }

                // BG1
                if regs.mainEnabled(.bg1) && regs.windowAllows(.bg1, x: x) {
                    if let c = fetchBG4bppCandidate(
                        layer: .bg1,
                        basePriority: bg1Base,
                        tilemapBase: regs.bg1TilemapBase,
                        tileDataBase: regs.bg1TileDataBase,
                        mapW: bg1W, mapH: bg1H,
                        scrollX: bg1ScrollX, tileY: bg1tileY, inY: bg1inY,
                        x: x,
                        mem: mem
                    ) { best = pickBest(best, c) }
                }

                // OBJ
                if !sprites.isEmpty && regs.windowAllows(.obj, x: x) {
                    if let c = fetchOBJCandidate(x: x, y: y, sprites: sprites, regs: regs, mem: mem) {
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

    // MARK: - BG fetch

    @inline(__always)
    private func pickBest(_ a: Candidate?, _ b: Candidate) -> Candidate {
        guard let a else { return b }
        if b.priority >= a.priority { return b }
        return a
    }

    private func fetchBG4bppCandidate(
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
        mem: PPUMemory
    ) -> Candidate? {
        let sx = (x + scrollX) % (mapW * 8)
        let tileX = sx >> 3
        let inX = sx & 7

        let entryAddr = bgEntryAddress(tilemapBase: tilemapBase, tileX: tileX, tileY: tileY)
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

    // MARK: - OBJ evaluation + fetch

    private func evaluateSpritesForScanline(y: Int, regs: PPURegisters, mem: PPUMemory) -> [Sprite] {
        // Real hardware rotates sprite priority based on OAMADDR at start of scanline.
        let start = Int((regs.oamAddr >> 2) & 0x7F) // 0..127
        let sizeSel = regs.objSizeSel
        let nameBase = regs.objNameBase

        var sprites: [Sprite] = []
        sprites.reserveCapacity(32)

        var found = 0
        var tiles = 0

        for n in 0..<128 {
            let i = (start + n) & 127
            let base = i * 4
            let sy = Int(mem.readOAM(base + 0))
            let tile = Int(mem.readOAM(base + 1))
            let attr = Int(mem.readOAM(base + 2))
            let sxLo = Int(mem.readOAM(base + 3))

            let hiIndex = 512 + (i >> 2)
            let hiShift = (i & 3) * 2
            let hiBits = Int((mem.readOAM(hiIndex) >> hiShift) & 0x03)

            let x = sxLo | ((hiBits & 0x01) << 8)
            let big = (hiBits & 0x02) != 0

            let (w, h) = objDimensions(sizeSel: sizeSel, big: big)

            // Y is 0..255 wrap; treat as signed wrap for visibility
            var yy = sy
            if yy >= 224 { yy -= 256 }
            let inRange = y >= yy && y < (yy + h)
            if !inRange { continue }

            found += 1
            if found > 32 {
                regs.setObjOverflow(range: true, time: false)
                // still continue to accumulate tiles/time until we hit limits
            }

            let prio = (attr >> 4) & 0x03
            let pal = (attr >> 1) & 0x07
            let hflip = (attr & 0x40) != 0
            let vflip = (attr & 0x80) != 0

            let tileCount = max(1, w / 8)
            tiles += tileCount
            if tiles > 34 {
                regs.setObjOverflow(range: false, time: true)
            }

            if sprites.count < 32 && tiles <= 34 {
                sprites.append(Sprite(
                    index: i, x: x, y: yy, w: w, h: h,
                    tile: tile, pal: pal, prio: prio,
                    hflip: hflip, vflip: vflip, nameBase: nameBase
                ))
            }
        }

        return sprites
    }

    private func fetchOBJCandidate(x: Int, y: Int, sprites: [Sprite], regs: PPURegisters, mem: PPUMemory) -> Candidate? {
        // Draw in OAM order: first match wins among same priority.
        // We'll pick highest priority overall (then first encountered).
        var best: Candidate? = nil

        for sp in sprites {
            let localX = x - sp.x
            let localY = y - sp.y
            if localX < 0 || localY < 0 || localX >= sp.w || localY >= sp.h { continue }

            let px = sp.hflip ? (sp.w - 1 - localX) : localX
            let py = sp.vflip ? (sp.h - 1 - localY) : localY

            let colorIndex = fetchOBJPixel4bpp(tile: sp.tile, nameBase: sp.nameBase, w: sp.w, x: px, y: py, mem: mem)
            if colorIndex == 0 { continue }

            let cgramIndex = 0x80 + sp.pal * 16 + colorIndex
            let bgr = mem.readCGRAM16(colorIndex: cgramIndex)

            // OBJ priority buckets should interleave with BG; we approximate:
            // higher sp.prio means higher priority.
            let prio = 6 + sp.prio * 3

            let cand = Candidate(priority: prio, layer: .obj, bgr555: bgr)
            best = pickBest(best, cand)
        }

        return best
    }

    private func fetchOBJPixel4bpp(tile: Int, nameBase: Int, w: Int, x: Int, y: Int, mem: PPUMemory) -> Int {
        // OBJ tile data base: coarse selection (not full hardware-accurate)
        let base = (nameBase & 0x07) * 0x2000

        let tilesPerRow = max(1, w / 8)
        let tx = x >> 3
        let ty = y >> 3
        let inX = x & 7
        let inY = y & 7

        let tileNum = tile + ty * tilesPerRow + tx
        return fetch4bppPixel(tileDataBase: base, tileNum: tileNum, x: inX, y: inY, mem: mem)
    }

    private func objDimensions(sizeSel: Int, big: Bool) -> (w: Int, h: Int) {
        // SNES has 8 size pairs selected by OBJSEL.
        // We implement the standard table:
        // 0: 8x8 / 16x16
        // 1: 8x8 / 32x32
        // 2: 8x8 / 64x64
        // 3: 16x16 / 32x32
        // 4: 16x16 / 64x64
        // 5: 32x32 / 64x64
        // 6: 16x32 / 32x64
        // 7: 16x32 / 32x32 (fallback)
        let small: (Int, Int)
        let large: (Int, Int)
        switch sizeSel & 7 {
        case 0: small = (8, 8);   large = (16, 16)
        case 1: small = (8, 8);   large = (32, 32)
        case 2: small = (8, 8);   large = (64, 64)
        case 3: small = (16, 16); large = (32, 32)
        case 4: small = (16, 16); large = (64, 64)
        case 5: small = (32, 32); large = (64, 64)
        case 6: small = (16, 32); large = (32, 64)
        default: small = (16, 32); large = (32, 32)
        }
        return big ? (large.0, large.1) : (small.0, small.1)
    }

    // MARK: - Helpers

    private func bgMapTileDimensions(sizeBits: u8) -> (w: Int, h: Int) {
        switch sizeBits & 0x03 {
        case 0: return (32, 32)
        case 1: return (64, 32)
        case 2: return (32, 64)
        case 3: return (64, 64)
        default: return (32, 32)
        }
    }

    private func bgEntryAddress(tilemapBase: Int, tileX: Int, tileY: Int) -> Int {
        let screenX = (tileX >> 5) & 1
        let screenY = (tileY >> 5) & 1

        let screenIndex = screenX | (screenY << 1)
        let screenBase = tilemapBase + screenIndex * 0x800

        let localX = tileX & 31
        let localY = tileY & 31
        let entryIndex = localY * 32 + localX
        return screenBase + entryIndex * 2
    }

    private func fetch4bppPixel(tileDataBase: Int, tileNum: Int, x: Int, y: Int, mem: PPUMemory) -> Int {
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

        var r: Int
        var g: Int
        var b: Int

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
        if br == 0 { return .rgba(0, 0, 0, 0xFF) }

        let r = Int(rgba & 0xFF)
        let g = Int((rgba >> 8) & 0xFF)
        let b = Int((rgba >> 16) & 0xFF)
        let a = Int((rgba >> 24) & 0xFF)

        let rr = (r * br) / 15
        let gg = (g * br) / 15
        let bb = (b * br) / 15

        return .rgba(u8(rr), u8(gg), u8(bb), u8(a))
    }
}
