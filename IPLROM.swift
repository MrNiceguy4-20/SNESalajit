import Foundation

/// Non-copyrighted IPL ROM stub + hook.
/// Real SNES has a 64-byte IPL at $FFC0-$FFFF.
/// We ship 0xFF-filled stub and allow you to swap in real bytes externally.
enum IPLROM {
    static let base: Int = 0xFFC0
    static let size: Int = 0x40

    /// Default stub (all 0xFF). Replace at runtime if desired.
    static var bytes: [u8] = Array(repeating: 0xFF, count: size)

    @inline(__always)
    static func read(_ addr: Int) -> u8 {
        bytes[(addr - base) & (size - 1)]
    }
}
