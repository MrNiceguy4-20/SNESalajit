import Foundation

enum SNESColor {
    static func bgr555ToRGBA8(_ bgr: u16) -> u32 {
        let r5 = u32(bgr & 0x1F)
        let g5 = u32((bgr >> 5) & 0x1F)
        let b5 = u32((bgr >> 10) & 0x1F)

        let r8 = u8(truncatingIfNeeded: (r5 << 3) | (r5 >> 2))
        let g8 = u8(truncatingIfNeeded: (g5 << 3) | (g5 >> 2))
        let b8 = u8(truncatingIfNeeded: (b5 << 3) | (b5 >> 2))

        return .rgba(r8, g8, b8, 0xFF)
    }
}
