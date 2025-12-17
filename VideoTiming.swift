import Foundation

/// Bus-owned video timing state (H/V counters, vblank, etc.)
struct VideoTiming {
    // Dot clock ~= master / 4 (NTSC). We model in master cycles.
    static let masterCyclesPerDot = 4

    // NTSC-ish defaults (Phase 3 will refine for interlace/region/etc.)
    static let dotsPerScanline = 341
    static let totalScanlines = 262
    static let visibleScanlines = 224

    static let vblankStartScanline = visibleScanlines
    
    var dot: Int = 0          // 0..340
    var scanline: Int = 0     // 0..261

    var inVBlank: Bool = false
    var didEnterVBlank: Bool = false
    var didLeaveVBlank: Bool = false

    /// Approximate auto-joypad busy duration, in dots (used for $4212 bit0).
    var autoJoypadBusyDots: Int = 0

    var autoJoypadBusy: Bool { autoJoypadBusyDots > 0 }

    mutating func reset() {
        dot = 0
        scanline = 0
        inVBlank = false
        didEnterVBlank = false
        didLeaveVBlank = false
        autoJoypadBusyDots = 0
    }
}
