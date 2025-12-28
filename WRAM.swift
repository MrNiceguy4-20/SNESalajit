import Foundation

final class WRAM {
    private var data = [u8](repeating: 0, count: 128 * 1024)

    func reset() {
        data.withUnsafeMutableBufferPointer { buf in
            for i in 0..<buf.count {
                buf[i] = (i & 1) == 0 ? 0x55 : 0xAA
            }
            let clearCount = min(0x0200, buf.count)
            for i in 0..<clearCount {
                buf[i] = 0x00
            }
        }
    }

    func read8(offset: Int) -> u8 {
        data[offset & (data.count - 1)]
    }

    func write8(offset: Int, value: u8) {
        data[offset & (data.count - 1)] = value
    }
}
