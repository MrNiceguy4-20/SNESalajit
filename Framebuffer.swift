import Foundation

/// Simple 32-bit RGBA8 framebuffer for Metal upload.
struct Framebuffer: Sendable {
    let width: Int
    let height: Int
    var pixels: [UInt32] // RGBA8 little-endian (memory layout [R, G, B, A])

    init(width: Int, height: Int, fill: UInt32 = .rgba(0, 0, 0, 0xFF)) {
        self.width = width
        self.height = height
        self.pixels = Array(repeating: fill, count: width * height)
    }

    mutating func set(x: Int, y: Int, rgba: UInt32) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        pixels[y * width + x] = rgba
    }
}
