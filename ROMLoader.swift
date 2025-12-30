import Foundation

enum ROMLoader {
    enum ROMError: Error {
        case unreadable
        case tooSmall
    }

    @inline(__always) static func load(url: URL) throws -> Cartridge {
        Log.info("Attempting to load ROM at path: \(url.path)")

        guard let data = try? Data(contentsOf: url) else {
            Log.warn("Failed to read ROM data from disk")
            throw ROMError.unreadable
        }

        let raw = [u8](data)
        let rom = selectBestROMBytes(raw: raw)

        guard rom.count >= 0x10000 else {
            Log.warn("ROM is too small (\(rom.count) bytes) after normalization")
            throw ROMError.tooSmall
        }

        let lo = scoreHeader(rom: rom, headerOffset: 0x7FC0, expected: .loROM)
        let hi = scoreHeader(rom: rom, headerOffset: 0xFFC0, expected: .hiROM)

        let mapping0: Cartridge.Mapping
        let headerOffset0: Int
        if hi > lo {
            mapping0 = .hiROM
            headerOffset0 = 0xFFC0
        } else {
            mapping0 = .loROM
            headerOffset0 = 0x7FC0
        }

        var mapping = mapping0
        var headerOffset = headerOffset0
        if !isMappingSane(rom: rom, mapping: mapping, headerOffset: headerOffset) {
            let alt: Cartridge.Mapping = (mapping == .loROM) ? .hiROM : .loROM
            let altHeader = (alt == .hiROM) ? 0xFFC0 : 0x7FC0
            if isMappingSane(rom: rom, mapping: alt, headerOffset: altHeader) {
                Log.warn("ROM mapping heuristic picked \(mapping), but sanity-check failed; switching to \(alt)")
                mapping = alt
                headerOffset = altHeader
            } else {
                Log.warn("ROM mapping sanity-check failed for both LoROM and HiROM; proceeding with \(mapping) (may be invalid)")
            }
        }

        if isMappingSane(rom: rom, mapping: .loROM, headerOffset: 0x7FC0),
           isMappingSane(rom: rom, mapping: .hiROM, headerOffset: 0xFFC0) {
            let loPref = mappingPreferenceScore(rom: rom, mapping: .loROM, headerOffset: 0x7FC0)
            let hiPref = mappingPreferenceScore(rom: rom, mapping: .hiROM, headerOffset: 0xFFC0)
            if hiPref > loPref {
                if mapping != .hiROM {
                    Log.warn("Both LoROM and HiROM look sane; preferring HiROM (score lo=\(loPref) hi=\(hiPref)).")
                }
                mapping = .hiROM
                headerOffset = 0xFFC0
            } else if loPref > hiPref {
                if mapping != .loROM {
                    Log.warn("Both LoROM and HiROM look sane; preferring LoROM (score lo=\(loPref) hi=\(hiPref)).")
                }
                mapping = .loROM
                headerOffset = 0x7FC0
            }
        }

        let sramSizeBytes = parseSRAMSizeBytes(rom: rom, headerOffset: headerOffset)
        Log.info("Selected mapping: \(mapping) (lo score=\(lo), hi score=\(hi)), SRAM=\(sramSizeBytes) bytes")
        return Cartridge(rom: rom, mapping: mapping, sramSizeBytes: sramSizeBytes)
    }

    @inline(__always) private static func isMappingSane(rom: [u8], mapping: Cartridge.Mapping, headerOffset: Int) -> Bool {
        guard headerOffset >= 0, headerOffset + 0x40 <= rom.count else { return false }

        let rvLo = Int(rom[headerOffset + 0x3C])
        let rvHi = Int(rom[headerOffset + 0x3D])
        let reset = (rvHi << 8) | rvLo

        if reset == 0x0000 || reset == 0xFFFF { return false }
        if reset < 0x8000 { return false }

        let cart = Cartridge(rom: rom, mapping: mapping, sramSizeBytes: 0)
        guard let entryOff = cart.romOffset(bank: 0x00, addr: u16(reset)),
              entryOff >= 0, entryOff < rom.count else {
            return false
        }

        if rom[entryOff] == 0xFF { return false }

        switch rom[entryOff] {
        case 0x00, 0x02, 0xDB, 0x82, 0x42:
            return false
        default:
            break
        }

        let probeCount = min(32, rom.count - entryOff)
        if probeCount > 0 {
            var suspicious = 0
            for i in 0..<probeCount {
                let b = rom[entryOff + i]
                if b == 0x00 || b == 0xFF { suspicious += 1 }
            }
            if suspicious * 2 >= probeCount { return false }
        }

        return true
    }

    @inline(__always) static func mappingPreferenceScore(rom: [u8], mapping: Cartridge.Mapping, headerOffset: Int) -> Int {
        guard headerOffset >= 0, headerOffset + 0x40 <= rom.count else { return Int.min }

        var score = 0
        let mapMode = rom[headerOffset + 0x15]
        let looksHiROM = (mapMode & 0x01) != 0
        switch mapping {
        case .loROM: score += looksHiROM ? -8 : 8
        case .hiROM: score += looksHiROM ? 8 : -8
        case .unknown: break
        }

        let c1 = Int(rom[headerOffset + 0x1C]) | (Int(rom[headerOffset + 0x1D]) << 8)
        let c2 = Int(rom[headerOffset + 0x1E]) | (Int(rom[headerOffset + 0x1F]) << 8)
        score += ((c1 ^ c2) == 0xFFFF) ? 4 : -2

        let rvLo = Int(rom[headerOffset + 0x3C])
        let rvHi = Int(rom[headerOffset + 0x3D])
        let reset = (rvHi << 8) | rvLo
        if reset >= 0x8000 && reset != 0xFFFF && reset != 0x0000 { score += 6 } else { score -= 10 }

        let cart = Cartridge(rom: rom, mapping: mapping, sramSizeBytes: 0)
        if let entryOff = cart.romOffset(bank: 0x00, addr: u16(reset)), entryOff >= 0, entryOff < rom.count {
            let op = rom[entryOff]
            if op == 0xFF { score -= 12 }
            else { score += 2 }

            if [0x78, 0x18, 0xD8, 0xC2, 0xE2, 0xA2, 0x5C].contains(op) { score += 4 }
        } else {
            score -= 12
        }

        return score
    }

    @inline(__always) private static func selectBestROMBytes(raw: [u8]) -> [u8] {
        var bases: [[u8]] = [raw]
        if raw.count % 1024 == 512, raw.count > 512 {
            let stripped = Array(raw.dropFirst(512))
            bases.append(stripped)
        }

        var bestROM: [u8] = raw
        var bestScore = Int.min

        for base in bases {
            guard base.count >= 0x10000 else { continue }

            let candidate = pickBestROMVariant(rom: base)
            let evalROM: [u8]
            if candidate.count % 1024 == 512, candidate.count > 512 {
                evalROM = Array(candidate.dropFirst(512))
            } else {
                evalROM = candidate
            }

            let lo = scoreHeader(rom: evalROM, headerOffset: 0x7FC0, expected: .loROM)
            let hi = scoreHeader(rom: evalROM, headerOffset: 0xFFC0, expected: .hiROM)
            var score = max(lo, hi)

            if isMappingSane(rom: evalROM, mapping: .loROM, headerOffset: 0x7FC0) { score += 50 }
            if isMappingSane(rom: evalROM, mapping: .hiROM, headerOffset: 0xFFC0) { score += 50 }

            if evalROM.count >= 0x10000 {
                let loReset = (Int(evalROM[0x7FC0 + 0x3D]) << 8) | Int(evalROM[0x7FC0 + 0x3C])
                if loReset >= 0x8000 && loReset != 0xFFFF && loReset != 0x0000 { score += 10 }
                let hiReset = (Int(evalROM[0xFFC0 + 0x3D]) << 8) | Int(evalROM[0xFFC0 + 0x3C])
                if hiReset >= 0x8000 && hiReset != 0xFFFF && hiReset != 0x0000 { score += 10 }
            }

            if score > bestScore {
                bestScore = score
                bestROM = evalROM
            }
        }

        if bestScore != Int.min {
            Log.info("ROM normalization selected best variant (score=\(bestScore), size=\(bestROM.count) bytes)")
        }

        if bestROM.count % 1024 == 512, bestROM.count > 512 {
            bestROM = Array(bestROM.dropFirst(512))
            Log.info("Stripped 512-byte copier header from selected variant (final size=\(bestROM.count) bytes)")
        }

        return bestROM
    }

    @inline(__always) private static func pickBestROMVariant(rom: [u8]) -> [u8] {
        func bestScore(_ r: [u8]) -> Int {
            let lo = scoreHeader(rom: r, headerOffset: 0x7FC0, expected: .loROM)
            let hi = scoreHeader(rom: r, headerOffset: 0xFFC0, expected: .hiROM)
            var s = max(lo, hi)
            let loSane = isMappingSane(rom: r, mapping: .loROM, headerOffset: 0x7FC0)
            let hiSane = isMappingSane(rom: r, mapping: .hiROM, headerOffset: 0xFFC0)
            if loSane { s += 120 }
            if hiSane { s += 120 }
            if !loSane && !hiSane { s -= 200 }
            return s
        }

        let originalScore = bestScore(rom)
        let de32 = deinterleave(rom, chunkSize: 0x8000, swapSize: 0x4000)
        let de32Score = bestScore(de32)
        let de64 = deinterleave(rom, chunkSize: 0x10000, swapSize: 0x8000)
        let de64Score = bestScore(de64)

        var best = rom
        var bestS = originalScore
        var bestName: String? = nil

        if de32Score > bestS {
            best = de32
            bestS = de32Score
            bestName = "32KB/16KB"
        }
        if de64Score > bestS {
            best = de64
            bestS = de64Score
            bestName = "64KB/32KB"
        }

        if let bestName {
            Log.info("Detected interleaved ROM layout (\(bestName)); de-interleaved for loading (score \(originalScore) -> \(bestS))")
        }
        return best
    }

    @inline(__always) private static func deinterleave(_ rom: [u8], chunkSize: Int, swapSize: Int) -> [u8] {
        guard chunkSize > 0, swapSize > 0, chunkSize == swapSize * 2 else { return rom }
        guard rom.count >= chunkSize else { return rom }

        var out = rom
        let chunks = rom.count / chunkSize
        for c in 0..<chunks {
            let base = c * chunkSize
            for i in 0..<swapSize {
                out[base + i] = rom[base + swapSize + i]
                out[base + swapSize + i] = rom[base + i]
            }
        }
        return out
    }

    @inline(__always) private static func parseSRAMSizeBytes(rom: [u8], headerOffset: Int) -> Int {
        guard headerOffset + 0x18 < rom.count else { return 0 }
        let v = Int(rom[headerOffset + 0x18] & 0x0F)
        if v == 0 { return 0 }
        let kb = 1 << v
        return kb * 1024
    }

    @inline(__always) private static func scoreHeader(rom: [u8], headerOffset: Int, expected: Cartridge.Mapping) -> Int {
        guard headerOffset + 0x40 <= rom.count else { return -9999 }

        var titleScore = 0
        for i in 0..<21 {
            let b = rom[headerOffset + i]
            if b == 0x00 { break }
            if b >= 0x20 && b <= 0x7E { titleScore += 1 }
        }

        let mapMode = rom[headerOffset + 0x15]
        let looksHiROM = (mapMode & 0x01) != 0
        var mapScore = 0
        switch expected {
        case .loROM: mapScore = looksHiROM ? -6 : 6
        case .hiROM: mapScore = looksHiROM ? 6 : -6
        case .unknown: mapScore = 0
        }

        let c1 = Int(rom[headerOffset + 0x1C]) | (Int(rom[headerOffset + 0x1D]) << 8)
        let c2 = Int(rom[headerOffset + 0x1E]) | (Int(rom[headerOffset + 0x1F]) << 8)
        let sumScore = ((c1 ^ c2) == 0xFFFF) ? 6 : -2

        let rvLo = Int(rom[headerOffset + 0x3C])
        let rvHi = Int(rom[headerOffset + 0x3D])
        let reset = (rvHi << 8) | rvLo

        var vecScore = 0
        if reset == 0x0000 || reset == 0xFFFF { vecScore -= 10 }
        if reset >= 0x8000 { vecScore += 6 } else { vecScore -= 6 }

        let entryOff: Int? = {
            switch expected {
            case .loROM:
                if reset < 0x8000 { return nil }
                return Int(reset - 0x8000)
            case .hiROM:
                return Int(reset)
            case .unknown:
                return nil
            }
        }()
        if let o = entryOff, o >= 0, o < rom.count {
            if rom[o] == 0xFF { vecScore -= 8 }
        } else {
            vecScore -= 8
        }

        return titleScore + mapScore + sumScore + vecScore
    }
}
