import Foundation

final class X64Assembler {

    func ret() -> [UInt8] { [0xC3] }

    func nop() -> [UInt8] { [0x90] }

    func movRAX(imm64: UInt64) -> [UInt8] {
        var b: [UInt8] = [0x48, 0xB8]
        var v = imm64
        for _ in 0..<8 { b.append(UInt8(truncatingIfNeeded: v)); v >>= 8 }
        return b
    }

    func movRDI(imm64: UInt64) -> [UInt8] {
        var b: [UInt8] = [0x48, 0xBF]
        var v = imm64
        for _ in 0..<8 { b.append(UInt8(truncatingIfNeeded: v)); v >>= 8 }
        return b
    }

    func movRSI(imm64: UInt64) -> [UInt8] {
        var b: [UInt8] = [0x48, 0xBE]
        var v = imm64
        for _ in 0..<8 { b.append(UInt8(truncatingIfNeeded: v)); v >>= 8 }
        return b
    }

    func movRDX(imm64: UInt64) -> [UInt8] {
        var b: [UInt8] = [0x48, 0xBA]
        var v = imm64
        for _ in 0..<8 { b.append(UInt8(truncatingIfNeeded: v)); v >>= 8 }
        return b
    }

    func movRCX(imm64: UInt64) -> [UInt8] {
        var b: [UInt8] = [0x48, 0xB9]
        var v = imm64
        for _ in 0..<8 { b.append(UInt8(truncatingIfNeeded: v)); v >>= 8 }
        return b
    }

    func movRCX_RDX() -> [UInt8] { [0x48, 0x89, 0xD1] }

    func callRAX() -> [UInt8] { [0xFF, 0xD0] }

    func jmp(rel32: Int32) -> [UInt8] {
        var b: [UInt8] = [0xE9]
        var v = UInt32(bitPattern: rel32)
        for _ in 0..<4 { b.append(UInt8(truncatingIfNeeded: v)); v >>= 8 }
        return b
    }
}
