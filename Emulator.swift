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
    private var romURL: URL?

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
        saveSRAM()

        let cart = try ROMLoader.load(url: url)
        romURL = url
        loadSRAMIfPresent(for: cart)
        bus.insertCartridge(cart)
        reset()
    }

    /// Step emulator by wall-clock time (seconds).
    func step(seconds: Double) {
        let masterHz = 21_477_272.0
        let cyclesToRun = Int(masterHz * seconds)
        step(masterCycles: cyclesToRun)
    }

    func step(masterCycles: Int) {
        var remaining = masterCycles
        while remaining > 0 {
            let chunk = min(remaining, 12)
            var slice = chunk

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

            cpu.step(cycles: max(1, slice / 6))
            bus.step(masterCycles: slice)
            ppu.step(masterCycles: slice)
            apu.step(masterCycles: slice)

            remaining -= slice
            clock.advance(masterCycles: slice)
        }
    }

    func saveSRAM() {
        guard let cart = bus.cartridge, cart.hasSRAM, let saveURL = saveFileURL else { return }
        guard let bytes = cart.serializeSRAM() else { return }

        do {
            try Data(bytes).write(to: saveURL)
            Log.info("Saved SRAM to \(saveURL.path)")
        } catch {
            Log.warn("Failed to save SRAM: \(error.localizedDescription)")
        }
    }

    private func loadSRAMIfPresent(for cart: Cartridge) {
        guard cart.hasSRAM, let saveURL = saveFileURL else { return }
        guard let data = try? Data(contentsOf: saveURL) else { return }

        let slice = data.prefix(cart.sramCapacity)
        cart.loadSRAM([u8](slice))
        Log.info(String(format: "Loaded %d bytes of SRAM from %@", slice.count, saveURL.lastPathComponent))
    }

    private var saveFileURL: URL? {
        guard let romURL else { return nil }
        return romURL.deletingPathExtension().appendingPathExtension("srm")
    }
}
