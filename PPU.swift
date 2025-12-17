import Foundation

/// PPU (Phase 3: basic registers + VRAM/CGRAM/OAM + simple BG rendering at vblank).
final class PPU {
    private weak var bus: Bus?

    private(set) var framebuffer = Framebuffer(width: 256, height: 224)

    let regs = PPURegisters()
    let mem = PPUMemory()
    private let renderer = PPURenderer()

    private var timing = VideoTiming()
    private var inVBlank: Bool = false
    private var frameCounter: Int = 0
    private let vblankLogInterval = 60

    func attach(bus: Bus) { self.bus = bus }

    func reset() {
        inVBlank = false
        framebuffer = Framebuffer(width: 256, height: 224, fill: .rgba(0, 0, 0, 0xFF))
        regs.reset()
        timing.reset()
        mem.reset()
        frameCounter = 0
        Log.debug("PPU reset; VRAM/CGRAM/OAM cleared", component: .ppu)
    }

    func step(masterCycles: Int) {
        var cycles = masterCycles

        while cycles > 0 {
            // Advance one dot
            timing.dot += 1
            cycles -= VideoTiming.masterCyclesPerDot

            if timing.dot >= VideoTiming.dotsPerScanline {
                timing.dot = 0
                timing.scanline += 1

                // Enter VBlank
                if timing.scanline == VideoTiming.vblankStartScanline {
                    timing.inVBlank = true
                    onEnterVBlank()
                }

                // End of frame
                if timing.scanline >= VideoTiming.totalScanlines {
                    timing.scanline = 0
                    timing.inVBlank = false
                    onLeaveVBlank()
                }
            }
        }
    }


    func onEnterVBlank() {
        inVBlank = true
        framebuffer = renderer.renderFrame(regs: regs, mem: mem)
        Log.debug("PPU frame rendered", component: .ppu)
    }

    func onLeaveVBlank() {
        inVBlank = false
        if frameCounter % vblankLogInterval == 0 {
            Log.debug("PPU left VBlank", component: .ppu)
        }
    }

    func readRegister(addr: u16, openBus: u8, video: VideoTiming) -> u8 {
        regs.read(addr: addr, mem: mem, openBus: openBus, video: video)
    }

    func writeRegister(addr: u16, value: u8, openBus: inout u8, video: VideoTiming) {
        regs.write(addr: addr, value: value, mem: mem, openBus: &openBus, video: video)
    }
}
