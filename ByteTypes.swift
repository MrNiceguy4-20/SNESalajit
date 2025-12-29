import Foundation

typealias u8  = UInt8
typealias u16 = UInt16
typealias u32 = UInt32
typealias u64 = UInt64
typealias i32 = Int32

@inline(__always) func lo8(_ v: u16) -> u8 { u8(truncatingIfNeeded: v) }
@inline(__always) func hi8(_ v: u16) -> u8 { u8(truncatingIfNeeded: v >> 8) }

@inline(__always) func make16(_ lo: u8, _ hi: u8) -> u16 { u16(lo) | (u16(hi) << 8) }

extension UInt32 {

    static func rgba(_ r: u8, _ g: u8, _ b: u8, _ a: u8 = 0xFF) -> UInt32 {
        (UInt32(a) << 24) | (UInt32(b) << 16) | (UInt32(g) << 8) | UInt32(r)
    }
}
