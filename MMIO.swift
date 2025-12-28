import Foundation

/// MMIO address decoding helpers.
enum MMIO {
    // PPU registers
    static let ppuStart: u16 = 0x2100
    static let ppuEnd:   u16 = 0x21FF

    // APU I/O ports (within $21xx window but not PPU regs)
    static let apuStart: u16 = 0x2140
    static let apuEnd:   u16 = 0x2143

    // WRAM address/data port ($2180-$2183)
    static let wramPortStart: u16 = 0x2180
    static let wramPortEnd:   u16 = 0x2183

    // CPU/interrupt/timer registers
    static let cpuStart: u16 = 0x4200
    static let cpuEnd:   u16 = 0x421F

    // DMA channel registers
    static let dmaStart: u16 = 0x4300
    static let dmaEnd:   u16 = 0x437F

    static func isMMIO(_ addr: u16) -> Bool {
        (addr >= ppuStart && addr <= ppuEnd) ||
        (addr >= apuStart && addr <= apuEnd) ||
        (addr >= wramPortStart && addr <= wramPortEnd) ||
        (addr >= cpuStart && addr <= cpuEnd) ||
        (addr >= dmaStart && addr <= dmaEnd)
    }
}
