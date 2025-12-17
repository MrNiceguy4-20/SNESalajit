import Foundation

final class AudioBuffer {
    private var buffer: [Int16] = []
    private let _sampleRate: Int

    var sampleRate: Int { _sampleRate }

    init(sampleRate: Int) {
        self._sampleRate = sampleRate
    }

    func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    /// Append `samples` *mono* samples of silence. If you're using interleaved stereo,
    /// pass `samples = frames * 2`.
    func produceSilence(samples: Int) {
        guard samples > 0 else { return }
        buffer.append(contentsOf: repeatElement(0, count: samples))
    }

    /// Interleaved stereo push (L,R).
    func push(left: Int, right: Int) {
        @inline(__always) func clamp16(_ v: Int) -> Int16 {
            if v > 32767 { return 32767 }
            if v < -32768 { return -32768 }
            return Int16(v)
        }
        buffer.append(clamp16(left))
        buffer.append(clamp16(right))
    }

    func pull(into out: inout [Int16]) {
        let n = min(out.count, buffer.count)
        guard n > 0 else { return }
        out[0..<n] = buffer[0..<n]
        buffer.removeFirst(n)
    }
}
