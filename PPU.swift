import Foundation

/// PPU (Phase 3: basic registers + VRAM/CGRAM/OAM + simple BG rendering at vblank).
final class PPU {
    private weak var bus: Bus?
    private var video = VideoTiming()
    private(set) var framebuffer = Framebuffer(width: 256, height: 224)
    let renderer = PPURenderer()
    let regs = PPURegisters()
    let mem = PPUMemory()
    

    var inVBlank: Bool = false

    func attach(bus: Bus) { self.bus = bus }

    func reset() {
        inVBlank = false
        framebuffer = Framebuffer(width: 256, height: 224, fill: 0x000000FF)
        regs.reset()
        mem.reset()
    }

    func step(masterCycles: Int) {
        var cycles = masterCycles

        while cycles > 0 {
            video.stepDot()

            if video.didEnterVBlank {
                onEnterVBlank()
                if let cpu = bus?.cpu {
                    cpu.nmiPending = true
                }
            }

            if video.didLeaveVBlank {
                onLeaveVBlank()
            }

            cycles -= VideoTiming.masterCyclesPerDot
        }
    }

    func onEnterVBlank() {
        let fb = renderer.renderFrame(regs: regs, mem: mem)
        bus?.ppuOwner?.submitFrame(fb)
    }

    func onLeaveVBlank() {
        inVBlank = false
    }

    func readRegister(addr: u16, openBus: u8, video: VideoTiming) -> u8 {
        regs.read(addr: addr, mem: mem, openBus: openBus, video: video)
    }

    func writeRegister(addr: u16, value: u8, openBus: inout u8, video: VideoTiming) {
        regs.write(addr: addr, value: value, mem: mem, openBus: &openBus, video: video)
    }

    // MARK: - Debug

    struct PPUDebugState: Sendable {
        let forcedBlank: Bool
        let brightness: u8

        let bgMode: u8
        let bg3Priority: Bool

        let tmMain: u8
        let tsSub: u8

        let vramAddr: u16
        let cgramAddr: u8

        let framebufferWidth: Int
        let framebufferHeight: Int
    }

    func debugSnapshot() -> PPUDebugState {
        PPUDebugState(
            forcedBlank: regs.forcedBlank,
            brightness: regs.brightness,
            bgMode: regs.bgMode,
            bg3Priority: regs.bg3Priority,
            tmMain: regs.tmMain,
            tsSub: regs.tsSub,
            vramAddr: regs.vramAddr,
            cgramAddr: regs.cgramAddr,
            framebufferWidth: framebuffer.width,
            framebufferHeight: framebuffer.height
        )
    }
}
