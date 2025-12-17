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

    init(rom: [u8], mapping: Mapping, sramSizeBytes: Int) {
        self.rom = rom
        self.mapping = mapping
        self.sram = Array(repeating: 0x00, count: max(0, sramSizeBytes))
    }

    // MARK: - Public bus access

    func read8(bank: u8, addr: u16) -> u8 {
        // SRAM ranges (common cases):
        if !sram.isEmpty, isSRAM(bank: bank, addr: addr) {
            let o = sramOffset(bank: bank, addr: addr)
            return sram[o % sram.count]
        }

        // ROM mapping
        if let ro = romOffset(bank: bank, addr: addr) {
            return rom[ro]
        }

        return 0xFF
    }

    func write8(bank: u8, addr: u16, value: u8) {
        if !sram.isEmpty, isSRAM(bank: bank, addr: addr) {
            let o = sramOffset(bank: bank, addr: addr)
            sram[o % sram.count] = value
        }
        // ROM is read-only.
    }

    // MARK: - Mapping helpers

    private func romOffset(bank: u8, addr: u16) -> Int? {
        switch mapping {
        case .loROM:
            // LoROM: banks 00-7D/80-FF, addr 8000-FFFF => 32KB pages
            if addr < 0x8000 { return nil }
            let b = Int(bank & 0x7F)
            if b > 0x7D { /* 7E/7F are WRAM handled by bus */ }
            let page = b & 0x7F
            let off = (page * 0x8000) + Int(addr - 0x8000)
            return off % rom.count

        case .hiROM:
            // HiROM: banks 00-7D/80-FF, addr 0000-FFFF => 64KB pages (commonly 40-7D/ C0-FF for ROM)
            let b = Int(bank & 0x7F)
            // Avoid 7E/7F WRAM – bus handles.
            if bank == 0x7E || bank == 0x7F { return nil }
            let off = (b * 0x10000) + Int(addr)
            return off % rom.count

        case .unknown:
            // Fallback: flat wrap
            let off = (Int(bank) << 16) | Int(addr)
            return off % rom.count
        }
    }

    private func isSRAM(bank: u8, addr: u16) -> Bool {
        switch mapping {
        case .loROM:
            // LoROM SRAM often in banks 70-7D (and F0-FD mirrors), addr 0000-7FFF
            let b = bank & 0x7F
            return (b >= 0x70 && b <= 0x7D) && addr < 0x8000
        case .hiROM:
            // HiROM SRAM often banks 20-3F / A0-BF, addr 6000-7FFF (varies)
            let b = bank & 0x7F
            return (b >= 0x20 && b <= 0x3F) && (addr >= 0x6000 && addr <= 0x7FFF)
        case .unknown:
            return false
        }
    }

    private func sramOffset(bank: u8, addr: u16) -> Int {
        switch mapping {
        case .loROM:
            let b = Int(bank & 0x7F) - 0x70
            return (b * 0x8000) + Int(addr)
        case .hiROM:
            let b = Int(bank & 0x7F) - 0x20
            return (b * 0x2000) + Int(addr - 0x6000)
        case .unknown:
            return 0
        }
    }
}
