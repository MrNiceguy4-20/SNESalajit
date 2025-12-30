import Foundation

struct BRRDecoder {
    @inline(__always) static func decodeBlock(header: u8, data: [u8], prev1: inout Int, prev2: inout Int) -> [Int] {
        let shift = Int(header >> 4)
        let filter = (header >> 2) & 0x03
        var out: [Int] = []
        out.reserveCapacity(16)

        func clamp(_ v: Int) -> Int {
            return min(32767, max(-32768, v))
        }

        for byte in data {
            for nib in [byte >> 4, byte & 0x0F] {
                var s = Int(Int8(bitPattern: (nib & 0x08) != 0 ? nib | 0xF0 : nib))
                s <<= shift

                var predicted = s
                switch filter {
                case 1: predicted += prev1 * 15 / 16
                case 2: predicted += (prev1 * 61 - prev2 * 15) / 32
                case 3: predicted += (prev1 * 115 - prev2 * 13) / 64
                default: break
                }

                predicted = clamp(predicted)
                prev2 = prev1
                prev1 = predicted
                out.append(predicted)
            }
        }
        return out
    }
}
