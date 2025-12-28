import Foundation

struct VideoTiming {
    static let masterCyclesPerDot = 4

    static let dotsPerScanline = 341
    static let totalScanlines = 262
    static let visibleScanlines = 224

    static let vblankStartScanline = 225

    var dot: Int = 0
    var scanline: Int = 0

    var inVBlank: Bool = false

    private(set) var didEnterVBlank: Bool = false
    private(set) var didLeaveVBlank: Bool = false

    var autoJoypadBusyDots: Int = 0

    var autoJoypadBusy: Bool { autoJoypadBusyDots > 0 }

    var isHBlank: Bool {
        dot >= 274 && dot < VideoTiming.dotsPerScanline
    }

    var isVisibleScanline: Bool {
        scanline < VideoTiming.visibleScanlines
    }

    var isVBlankScanline: Bool {
        scanline >= VideoTiming.vblankStartScanline
    }

    mutating func reset() {
        dot = 0
        scanline = 0
        inVBlank = false
        didEnterVBlank = false
        didLeaveVBlank = false
        autoJoypadBusyDots = 0
    }

    mutating func consumeDidEnterVBlank() -> Bool {
        let v = didEnterVBlank
        didEnterVBlank = false
        return v
    }

    mutating func consumeDidLeaveVBlank() -> Bool {
        let v = didLeaveVBlank
        didLeaveVBlank = false
        return v
    }

    mutating func stepDot() {
        didEnterVBlank = false
        didLeaveVBlank = false

        if autoJoypadBusyDots > 0 { autoJoypadBusyDots -= 1 }

        dot += 1
        if dot < VideoTiming.dotsPerScanline { return }

        dot = 0
        scanline += 1

        if !inVBlank && scanline == VideoTiming.vblankStartScanline {
            inVBlank = true
            didEnterVBlank = true
        }

        if scanline >= VideoTiming.totalScanlines {
            scanline = 0
            if inVBlank {
                inVBlank = false
                didLeaveVBlank = true
            }
        }
    }
}
