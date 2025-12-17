import Foundation

enum ROMLoader {
    enum ROMError: Error {
        case unreadable
        case tooSmall
    }

    static func load(url: URL) throws -> Cartridge {
        guard let data = try? Data(contentsOf: url) else { throw ROMError.unreadable }
        var bytes = [u8](data)

        // Strip 512-byte copier header if present (common in .smc)
        if bytes.count % 1024 == 512 {
            bytes.removeFirst(512)
        }
        guard bytes.count > 0x8000 else { throw ROMError.tooSmall }

        // Detect mapping + SRAM size from internal header (best-effort).
        let mapping = detectMapping(rom: bytes)
        let headerOffset = internalHeaderOffset(for: mapping)
        let sramSizeBytes = parseSRAMSize(rom: bytes, headerOffset: headerOffset)

        return Cartridge(rom: bytes, mapping: mapping, sramSizeBytes: sramSizeBytes)
    }

    // MARK: - Header parsing

    private static func internalHeaderOffset(for mapping: Cartridge.Mapping) -> Int {
        switch mapping {
        case .loROM: return 0x7FC0
        case .hiROM: return 0xFFC0
        case .unknown: return 0x7FC0
        }
    }

    private static func parseSRAMSize(rom: [u8], headerOffset: Int) -> Int {
        // SRAM size byte at header + 0x18 in SNES internal header (0x7FD8 for LoROM).
        let o = headerOffset + 0x18
        guard o < rom.count else { return 0 }
        let exp = rom[o]
        // Value is log2(size in kbits) or 0 if none; common: 0x03 => 8kbits? In practice many docs treat it as size = 2^n kbits.
        // We'll use: sizeBytes = (1 << exp) * 1024 / 8, but clamp to sane range.
        if exp == 0 { return 0 }
        if exp > 0x10 { return 0 }
        let kbits = 1 << Int(exp) // kbits
        let bytes = (kbits * 1024) / 8
        // Clamp: 0..512KB
        return min(max(bytes, 0), 512 * 1024)
    }

    private static func detectMapping(rom: [u8]) -> Cartridge.Mapping {
        // Prefer map mode byte at internal header + 0x15 (0x7FD5/0xFFD5)
        let lo = scoreHeader(rom: rom, headerOffset: 0x7FC0)
        let hi = scoreHeader(rom: rom, headerOffset: 0xFFC0)

        return (lo >= hi) ? .loROM : .hiROM
    }

    private static func scoreHeader(rom: [u8], headerOffset: Int) -> Int {
        guard headerOffset + 0x20 < rom.count else { return 0 }

        // Title is 21 bytes at offset 0x00
        let title = rom[headerOffset..<(headerOffset+21)]
        let titleScore = title.reduce(0) { acc, b in
            let printable = (b >= 0x20 && b <= 0x7E)
            return acc + (printable ? 2 : -1)
        }

        // Map mode byte at +0x15
        let mapMode = rom[headerOffset + 0x15]
        let mapScore: Int
        switch mapMode & 0x0F {
        case 0x0: mapScore = 8  // LoROM-ish
        case 0x1: mapScore = 8  // HiROM-ish (still ambiguous)
        default:  mapScore = 0
        }

        // Checksum complement + checksum should add to 0xFFFF (weak signal).
        let c1 = Int(rom[headerOffset + 0x1C]) | (Int(rom[headerOffset + 0x1D]) << 8)
        let c2 = Int(rom[headerOffset + 0x1E]) | (Int(rom[headerOffset + 0x1F]) << 8)
        let sumScore = ((c1 ^ c2) == 0xFFFF) ? 4 : 0

        return titleScore + mapScore + sumScore
    }
}
