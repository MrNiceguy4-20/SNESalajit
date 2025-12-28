import Foundation

/// Cartridge ROM/SRAM mapping (Phase 2: basic LoROM/HiROM).
final class Cartridge {
    enum Mapping {
        case loROM
        case hiROM
        case unknown
    }

    let rom: [u8]
    let mapping: Mapping

    // SRAM (battery-backed) – size may be 0.
    private var sram: [u8]

    // MARK: - SRAM Info

    var sramCapacity: Int { sram.count }
    var hasSRAM: Bool { !sram.isEmpty }

    init(rom: [u8], mapping: Mapping, sramSizeBytes: Int) {
        self.rom = rom
        self.mapping = mapping
        self.sram = sramSizeBytes > 0 ? Array(repeating: 0x00, count: sramSizeBytes) : []
    }

    // MARK: - Public bus access

    func read8(bank: u8, addr: u16) -> u8 {
        if isSRAM(bank: bank, addr: addr) {
            let off = sramOffset(bank: bank, addr: addr)
            if off >= 0 && off < sram.count { return sram[off] }
            return 0xFF
        }

        guard let off = romOffset(bank: bank, addr: addr) else { return 0xFF }
        guard off >= 0 && off < rom.count else { return 0xFF }
        return rom[off]
    }

    func write8(bank: u8, addr: u16, value: u8) {
        guard hasSRAM, isSRAM(bank: bank, addr: addr) else { return }
        let off = sramOffset(bank: bank, addr: addr)
        guard off >= 0 && off < sram.count else { return }
        sram[off] = value
    }

    // MARK: - Mapping helpers

    func romOffset(bank: u8, addr: u16) -> Int? {
        let b = Int(bank & 0x7F)
        if b == 0x7E || b == 0x7F || b > 0x7D { return nil }

        switch mapping {
        case .loROM:
            if addr >= 0x8000 {
                return (b * 0x8000) + Int(addr - 0x8000)
            }
            if b >= 0x40 {
                return ((b - 0x40) * 0x8000) + Int(addr)
            }
            return nil

        case .hiROM:
            // HiROM valid banks: $C0–$FF only
            if b < 0xC0 { return nil }
            return (Int(b - 0xC0) * 0x10000) + Int(addr)
        case .unknown:
            return nil
        }
    }

    private func isSRAM(bank: u8, addr: u16) -> Bool {
        let b = Int(bank & 0x7F)
        switch mapping {
        case .loROM:
            return (b >= 0x70 && b <= 0x7D) && addr < 0x8000
        case .hiROM:
            return (b >= 0x20 && b <= 0x3F) && (addr >= 0x6000 && addr <= 0x7FFF)
        case .unknown:
            return false
        }
    }

    private func sramOffset(bank: u8, addr: u16) -> Int {
        let b = Int(bank & 0x7F)
        switch mapping {
        case .loROM:
            return (b - 0x70) * 0x8000 + Int(addr)
        case .hiROM:
            return (b - 0x20) * 0x2000 + Int(addr - 0x6000)
        case .unknown:
            return 0
        }
    }

    // MARK: - Persistence

    func loadSRAM(_ data: [u8]) {
        guard hasSRAM else { return }
        let count = min(data.count, sram.count)
        for i in 0..<count {
            sram[i] = data[i]
        }
    }

    func serializeSRAM() -> [u8]? {
        guard hasSRAM else { return nil }
        return sram
    }
}
