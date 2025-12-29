import Foundation

/// PPU (Phase 3: basic registers + VRAM/CGRAM/OAM + simple BG rendering at vblank).
final class PPU {
    init() {
        regs.traceHook = { [weak self] line in
            self?.pushTrace(line)
        }
    }

    private weak var bus: Bus?
    private var video = VideoTiming()
    private(set) var framebuffer = Framebuffer(width: 256, height: 224)
    let renderer = PPURenderer()
    let regs = PPURegisters()
    let mem = PPUMemory()
    

    var inVBlank: Bool = false

    // MARK: - Debug trace
    private var traceRing: [String] = Array(repeating: "", count: 128)
    private var traceHead: Int = 0
    private var traceCount: Int = 0

    private func pushTrace(_ s: String) {
        traceRing[traceHead] = s
        traceHead = (traceHead + 1) & (traceRing.count - 1)
        traceCount = min(traceCount + 1, traceRing.count)
    }

    private func recentTrace() -> [String] {
        guard traceCount > 0 else { return [] }
        var out: [String] = []
        out.reserveCapacity(traceCount)
        let start = (traceHead - traceCount + traceRing.count) % traceRing.count
        for i in 0..<traceCount {
            out.append(traceRing[(start + i) % traceRing.count])
        }
        return out
    }


    func attach(bus: Bus) { self.bus = bus }

    func reset() {
        // Cold/reset power-on state should also reset video timing so VBlank edges are deterministic.
        video = VideoTiming()

        inVBlank = false
        framebuffer = Framebuffer(width: 256, height: 224, fill: 0x000000FF)
        regs.reset()
        mem.reset()

        // Clear debug trace ring on reset so snapshots reflect the new run.
        traceRing = Array(repeating: "", count: 128)
        traceHead = 0
        traceCount = 0
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
        inVBlank = true
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
        let recentTrace: [String]
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
            framebufferHeight: framebuffer.height,
            recentTrace: recentTrace()
        )
    }
}
