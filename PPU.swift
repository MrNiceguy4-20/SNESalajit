import Foundation

/// PPU (Phase 3: basic registers + VRAM/CGRAM/OAM + simple BG rendering at vblank).
final class PPU {
    private weak var bus: Bus?

    private(set) var framebuffer = Framebuffer(width: 256, height: 224)

    let regs = PPURegisters()
    let mem = PPUMemory()
    private let renderer = PPURenderer()

    private var inVBlank: Bool = false

    func attach(bus: Bus) { self.bus = bus }

    func reset() {
        inVBlank = false
        framebuffer = Framebuffer(width: 256, height: 224, fill: 0x000000FF)
        regs.reset()
        mem.reset()
        Log.debug("PPU reset; VRAM/CGRAM/OAM cleared", component: .ppu)
    }

    func step(masterCycles: Int) {
        _ = masterCycles
    }

    func onEnterVBlank() {
        inVBlank = true
        framebuffer = renderer.renderFrame(regs: regs, mem: mem)
        Log.debug("PPU entered VBlank; rendered framebuffer", component: .ppu)
    }

    func onLeaveVBlank() {
        inVBlank = false
        Log.debug("PPU left VBlank", component: .ppu)
    }

    func readRegister(addr: u16, openBus: u8, video: VideoTiming) -> u8 {
        regs.read(addr: addr, mem: mem, openBus: openBus, video: video)
    }

    func writeRegister(addr: u16, value: u8, openBus: inout u8, video: VideoTiming) {
        regs.write(addr: addr, value: value, mem: mem, openBus: &openBus, video: video)
    }
}
