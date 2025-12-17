import Foundation

/// Extremely simplified renderer (Phase 3).
/// Renders at VBlank using current VRAM/CGRAM state (not cycle-accurate).
final class PPURenderer {

    func renderFrame(regs: PPURegisters, mem: PPUMemory) -> Framebuffer {
        var fb = Framebuffer(width: 256, height: 224, fill: 0x000000FF)

        if regs.forcedBlank {
            return fb
        }

        let backdrop = SNESColor.bgr555ToRGBA8(mem.readCGRAM16(colorIndex: 0))
        fb.pixels = Array(repeating: backdrop, count: fb.width * fb.height)

        switch regs.bgMode {
        case 0, 1:
            renderBG1_Mode1_4bpp(regs: regs, mem: mem, fb: &fb)
        default:
            // Other modes not yet implemented.
            break
        }

        return fb
    }

    // MARK: - BG1 Mode 0/1 4bpp (simplified)

    private func renderBG1_Mode1_4bpp(regs: PPURegisters, mem: PPUMemory, fb: inout Framebuffer) {
        let tilemapBase = regs.bg1TilemapBase
        let tileDataBase = regs.bg1TileDataBase

        // BG scroll registers are 10-bit on SNES.
        let scrollX = Int(regs.bg1hofs & 0x03FF)
        let scrollY = Int(regs.bg1vofs & 0x03FF)

        // Screen size (BG1SC bits 0-1):
        // 0: 32x32 tiles, 1: 64x32, 2: 32x64, 3: 64x64
        let (mapW, mapH) = bgMapTileDimensions(sizeBits: regs.bg1ScreenSize)

        for y in 0..<fb.height {
            let sy = (y + scrollY) % (mapH * 8)
            let tileY = sy >> 3
            let inY = sy & 7

            for x in 0..<fb.width {
                let sx = (x + scrollX) % (mapW * 8)
                let tileX = sx >> 3
                let inX = sx & 7

                let entryAddr = bgEntryAddress(tilemapBase: tilemapBase, tileX: tileX, tileY: tileY)
                let lo = mem.readVRAMByte(entryAddr)
                let hi = mem.readVRAMByte(entryAddr + 1)
                let entry = u16(lo) | (u16(hi) << 8)

                let tileNum = Int(entry & 0x03FF)
                let palNum = Int((entry >> 10) & 0x07)
                let hflip = (entry & 0x4000) != 0
                let vflip = (entry & 0x8000) != 0

                let px = hflip ? (7 - inX) : inX
                let py = vflip ? (7 - inY) : inY

                let colorIndex = fetch4bppPixel(tileDataBase: tileDataBase, tileNum: tileNum, x: px, y: py, mem: mem)
                if colorIndex == 0 { continue } // color 0 = transparent

                let cgramIndex = palNum * 16 + colorIndex
                let bgr = mem.readCGRAM16(colorIndex: cgramIndex)
                fb.set(x: x, y: y, rgba: SNESColor.bgr555ToRGBA8(bgr))
            }
        }
    }

    private func bgMapTileDimensions(sizeBits: u8) -> (w: Int, h: Int) {
        switch sizeBits & 0x03 {
        case 0: return (32, 32)
        case 1: return (64, 32)
        case 2: return (32, 64)
        case 3: return (64, 64)
        default: return (32, 32)
        }
    }

    /// Compute BG tilemap entry address for BG1 with 32x32 "screens" arranged in 2KB blocks.
    ///
    /// Each 32x32 screen is 2048 bytes (0x800). For 64x64 there are 4 screens.
    private func bgEntryAddress(tilemapBase: Int, tileX: Int, tileY: Int) -> Int {
        let screenX = (tileX >> 5) & 1
        let screenY = (tileY >> 5) & 1

        // screen index: 0=top-left, 1=top-right, 2=bottom-left, 3=bottom-right
        let screenIndex = screenX | (screenY << 1)
        let screenBase = tilemapBase + screenIndex * 0x800

        let localX = tileX & 31
        let localY = tileY & 31
        let entryIndex = localY * 32 + localX
        return screenBase + entryIndex * 2
    }

    private func fetch4bppPixel(tileDataBase: Int, tileNum: Int, x: Int, y: Int, mem: PPUMemory) -> Int {
        // 4bpp tile = 32 bytes; planes 0/1 at +0..15, planes 2/3 at +16..31.
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
}
