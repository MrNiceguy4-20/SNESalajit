import Foundation

final class SPCTimers {
    private var enable: u8 = 0
    private var target: [u8] = [0,0,0]
    private var counter: [u8] = [0,0,0]
    private var divider: [Int] = [0,0,0]

    private let periods = [128, 128, 16]

    static func hvbjoy(video: VideoTiming) -> u8 {
        var v: u8 = 0
        if video.inVBlank { v |= 0x80 }
        if video.isHBlank { v |= 0x40 }
        if video.autoJoypadBusy { v |= 0x01 }
        return v
    }

    func reset() {
        enable = 0
        target = [0,0,0]
        counter = [0,0,0]
        divider = [0,0,0]
    }

    func writeControl(_ v: u8) {
        enable = v & 0x07
        for i in 0..<3 where (enable & (1 << i)) == 0 {
            counter[i] = 0
            divider[i] = 0
        }
    }

    func writeTarget(_ i: Int, _ v: u8) { target[i] = v }

    func readCounter(_ i: Int) -> u8 {
        let v = counter[i]
        counter[i] = 0
        return v
    }

    func step(spcCycles: Int) {
        for i in 0..<3 {
            guard (enable & (1 << i)) != 0 else { continue }
            divider[i] += spcCycles
            while divider[i] >= periods[i] {
                divider[i] -= periods[i]
                counter[i] &+= 1
            }
        }
    }
}
