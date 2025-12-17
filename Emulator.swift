import Foundation

/// Top-level orchestrator. Single-core deterministic stepping.
///
/// Phase 2:
/// - MDMA stalls the CPU for an approximate number of master cycles (bus-owned).
/// - Timekeeping remains bus-driven (H/V counters, IRQ/NMI edges, etc.).
final class Emulator {
    let bus = Bus()
    let cpu = CPU65816()
    let ppu = PPU()
    let apu = APU()

    private let clock = MasterClock()

    init() {
        cpu.attach(bus: bus)
        ppu.attach(bus: bus)
        apu.attach(bus: bus)

        bus.cpu = cpu
        bus.ppu = ppu
        bus.apu = apu

        reset()
    }

    func reset() {
        clock.reset()
        bus.reset()
        ppu.reset()
        apu.reset()
        cpu.reset()
    }

    func loadROM(url: URL) throws {
        let cart = try ROMLoader.load(url: url)
        bus.insertCartridge(cart)
        reset()
    }

    /// Step emulator by wall-clock time (seconds).
    func step(seconds: Double) {
        // SNES master clock (NTSC) ~21.47727 MHz. (Phase 5 will support PAL/region.)
        let masterHz = 21_477_272.0
        let cyclesToRun = Int(masterHz * seconds)
        step(masterCycles: cyclesToRun)
    }

    func step(masterCycles: Int) {
        var remaining = masterCycles
        while remaining > 0 {
            // We advance in small chunks so bus timers/DMA can trigger deterministically.
            // Chunk is 12 master cycles (~3 PPU dots).
            let chunk = min(remaining, 12)
            var slice = chunk

            // 1) If DMA is stalling the CPU, consume stall first (CPU does not run).
            let stalled = bus.consumeDMAStall(masterCycles: slice)
            if stalled > 0 {
                bus.step(masterCycles: stalled)
                ppu.step(masterCycles: stalled)
                apu.step(masterCycles: stalled)
                clock.advance(masterCycles: stalled)

                remaining -= stalled
                slice -= stalled

                if slice <= 0 { continue }
            }

            // 2) Normal execution slice: run CPU + bus + PPU/APU.
            cpu.step(cycles: max(1, slice / 6))
            bus.step(masterCycles: slice)
            ppu.step(masterCycles: slice)
            apu.step(masterCycles: slice)

            remaining -= slice
            clock.advance(masterCycles: slice)
        }
    }
}
