import Foundation

final class PPUMemory {
    private var vram = [u8](repeating: 0, count: 64 * 1024)
    private var cgram = [u8](repeating: 0, count: 512)
    private var oam = [u8](repeating: 0, count: 544)

    func reset() {
        vram = Array(repeating: 0, count: 64 * 1024)
        cgram = Array(repeating: 0, count: 512)
        oam = Array(repeating: 0, count: 544)
        writeCGRAM16(colorIndex: 0, value: 0x0000)
    }

    @inline(__always)
    func readVRAMByte(_ byteAddress: Int) -> u8 {
        vram[byteAddress & 0xFFFF]
    }

    @inline(__always)
    func writeVRAMByte(_ byteAddress: Int, value: u8) {
        vram[byteAddress & 0xFFFF] = value
    }

    func readVRAM16(wordAddress: u16) -> u16 {
        let byteIndex = (Int(wordAddress) * 2) & 0xFFFF
        let lo = vram[byteIndex]
        let hi = vram[(byteIndex + 1) & 0xFFFF]
        return u16(lo) | (u16(hi) << 8)
    }

    func writeVRAMLow(wordAddress: u16, value: u8) {
        let byteIndex = (Int(wordAddress) * 2) & 0xFFFF
        vram[byteIndex] = value
    }

    func writeVRAMHigh(wordAddress: u16, value: u8) {
        let byteIndex = ((Int(wordAddress) * 2) + 1) & 0xFFFF
        vram[byteIndex] = value
    }

    func readCGRAM16(colorIndex: Int) -> u16 {
        let idx = (colorIndex & 0xFF) * 2
        let lo = cgram[idx]
        let hi = cgram[idx + 1]
        return u16(lo) | (u16(hi) << 8)
    }

    func writeCGRAM16(colorIndex: Int, value: u16) {
        let idx = (colorIndex & 0xFF) * 2
        cgram[idx] = u8(value & 0xFF)
        cgram[idx + 1] = u8((value >> 8) & 0x7F)
    }

    func readOAM(_ addr: Int) -> u8 {
        if addr < 0 || addr >= 544 { return 0 }
        return oam[addr]
    }

    func writeOAM(_ addr: Int, _ value: u8) {
        if addr < 0 || addr >= 544 { return }
        oam[addr] = value
    }
}
