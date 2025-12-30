import Foundation

final class Cartridge {
    enum Mapping {
        case loROM
        case hiROM
        case unknown
    }

    let rom: [u8]
    let mapping: Mapping
    private var sram: [u8]

    var sramCapacity: Int { sram.count }
    var hasSRAM: Bool { !sram.isEmpty }

    init(rom: [u8], mapping: Mapping, sramSizeBytes: Int) {
        self.rom = rom
        self.mapping = mapping
        self.sram = sramSizeBytes > 0 ? Array(repeating: 0x00, count: sramSizeBytes) : []
    }

    @inline(__always) func read8(bank: u8, addr: u16) -> u8 {
        if isSRAM(bank: bank, addr: addr) {
            let off = sramOffset(bank: bank, addr: addr)
            if off >= 0 && off < sram.count { return sram[off] }
            return 0xFF
        }
        guard let off0 = romOffset(bank: bank, addr: addr) else { return 0xFF }
        let count = rom.count
        guard count > 0 else { return 0xFF }
        let off = off0 >= 0 ? (off0 % count) : 0
        return rom[off]
    }


    @inline(__always) func write8(bank: u8, addr: u16, value: u8) {
        guard hasSRAM, isSRAM(bank: bank, addr: addr) else { return }
        let off = sramOffset(bank: bank, addr: addr)
        guard off >= 0 && off < sram.count else { return }
        sram[off] = value
    }

    @inline(__always) func romOffset(bank: u8, addr: u16) -> Int? {
        let b = Int(bank)
        if b == 0x7E || b == 0x7F { return nil }

        switch mapping {
        case .loROM:
            if (b <= 0x3F) || (b >= 0x80 && b <= 0xBF) {
                guard addr >= 0x8000 else { return nil }
                return ((b & 0x3F) * 0x8000) + Int(addr - 0x8000)
            }
            if (b >= 0x40 && b <= 0x7D) || (b >= 0xC0 && b <= 0xFF) {
                guard addr < 0x8000 else { return nil }
                return ((b & 0x3F) * 0x8000) + Int(addr)
            }
            return nil

        case .hiROM:
            if (b <= 0x3F) || (b >= 0x80 && b <= 0xBF) {
                guard addr >= 0x8000 else { return nil }
                return ((b & 0x3F) * 0x10000) + Int(addr)
            }
            if (b >= 0x40 && b <= 0x7D) || (b >= 0xC0 && b <= 0xFF) {
                return ((b & 0x3F) * 0x10000) + Int(addr)
            }
            return nil

        case .unknown:
            return nil
        }
    }


    @inline(__always) private func isSRAM(bank: u8, addr: u16) -> Bool {
        let b = Int(bank)
        switch mapping {
        case .loROM:
            return (b >= 0x70 && b <= 0x7D) && addr < 0x8000
        case .hiROM:
            return (b >= 0x20 && b <= 0x3F) && (addr >= 0x6000 && addr <= 0x7FFF)
        case .unknown:
            return false
        }
    }

    @inline(__always) private func sramOffset(bank: u8, addr: u16) -> Int {
        let b = Int(bank)
        switch mapping {
        case .loROM:
            return (b - 0x70) * 0x8000 + Int(addr)
        case .hiROM:
            return (b - 0x20) * 0x2000 + Int(addr - 0x6000)
        case .unknown:
            return 0
        }
    }

    @inline(__always) func loadSRAM(_ data: [u8]) {
        guard hasSRAM else { return }
        let count = min(data.count, sram.count)
        for i in 0..<count {
            sram[i] = data[i]
        }
    }

    @inline(__always) func serializeSRAM() -> [u8]? {
        guard hasSRAM else { return nil }
        return sram
    }
}
