import Foundation

/// 128KB Work RAM (WRAM).
final class WRAM {
    private var data = [u8](repeating: 0, count: 128 * 1024)

    func reset() {
        data.withUnsafeMutableBufferPointer { buf in
            buf.initialize(repeating: 0)
        }
    }

    func read8(offset: Int) -> u8 {
        data[offset & (data.count - 1)]
    }

    func write8(offset: Int, value: u8) {
        data[offset & (data.count - 1)] = value
    }
}
