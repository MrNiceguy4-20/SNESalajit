import Foundation

final class PPU {
    var faultRecorder: FaultRecorder?
    init() {
        regs.traceHook = { [weak self] line in
            self?.pushTrace(line)
        }
    }

    private weak var bus: Bus?
    private(set) var framebuffer = Framebuffer(width: 256, height: 224)
    let renderer = PPURenderer()
    let regs = PPURegisters()
    let mem = PPUMemory()
    
    var inVBlank: Bool = false

    private var traceRing: [String] = Array(repeating: "", count: 128)
    private var traceHead: Int = 0
    private var traceCount: Int = 0

    @inline(__always) private func pushTrace(_ s: String) {
        traceRing[traceHead] = s
        traceHead = (traceHead + 1) & (traceRing.count - 1)
        traceCount = min(traceCount + 1, traceRing.count)
    }

    @inline(__always) private func recentTrace() -> [String] {
        guard traceCount > 0 else { return [] }
        var out: [String] = []
        out.reserveCapacity(traceCount)
        let start = (traceHead - traceCount + traceRing.count) % traceRing.count
        for i in 0..<traceCount {
            out.append(traceRing[(start + i) % traceRing.count])
        }
        return out
    }

    @inline(__always) func attach(bus: Bus) { self.bus = bus }

    @inline(__always) func reset() {
        inVBlank = false
        framebuffer = Framebuffer(width: 256, height: 224, fill: 0x000000FF)
        regs.reset()
        mem.reset()
        traceRing = Array(repeating: "", count: 128)
        traceHead = 0
        traceCount = 0
    }

    @inline(__always) func step(masterCycles: Int) {
        _ = masterCycles
    }

    @inline(__always) func onEnterVBlank() {
        inVBlank = true
        let fb = renderer.renderFrame(regs: regs, mem: mem)
        bus?.ppuOwner?.submitFrame(fb)
    }

    @inline(__always) func onLeaveVBlank() {
        inVBlank = false
    }

    @inline(__always) func readRegister(addr: u16, openBus: u8, video: VideoTiming) -> u8 {
        regs.read(addr: addr, mem: mem, openBus: openBus, video: video)
    }

    @inline(__always) func writeRegister(addr: u16, value: u8, openBus: inout u8, video: VideoTiming) {
        regs.write(addr: addr, value: value, mem: mem, openBus: &openBus, video: video)
    }

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

    @inline(__always) func debugSnapshot() -> PPUDebugState {
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
