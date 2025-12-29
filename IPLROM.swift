import Foundation

enum IPLROM {
    static let base: Int = 0xFFC0
    static let size: Int = 0x40
    static var bytes: [u8] = Array(repeating: 0xFF, count: size)

    @inline(__always)
    static func read(_ addr: Int) -> u8 {
        bytes[(addr - base) & (size - 1)]
    }
}
