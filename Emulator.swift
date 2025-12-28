import Foundation
import Combine

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
    @Published var framebuffer: Framebuffer?
    private let clock = MasterClock()
    private var romURL: URL?

    init() {
        cpu.attach(bus: bus)
        ppu.attach(bus: bus)
        apu.attach(bus: bus)

        bus.cpu = cpu
        bus.ppu = ppu
        bus.ppuOwner = self
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

    func step(seconds: Double) {
        let masterHz = 21_477_272.0
        let cyclesToRun = Int(masterHz * seconds)
        step(masterCycles: cyclesToRun)
    }


    func step(masterCycles: Int) {
        var remaining = masterCycles

        // Phase 12: preserve CPU/master ratio exactly (master ~= cpu * 6).
        // This eliminates long-term drift from integer truncation.
        var cpuMasterAcc: Int = 0  // remainder in master cycles (0..5)

        while remaining > 0 {
            let chunk = min(remaining, 12)
            var slice = chunk

            // 1) MDMA stall consumes master cycles where CPU does not execute.
            let stalled = bus.consumeDMAStall(masterCycles: slice)
            if stalled > 0 {
                bus.step(masterCycles: stalled)
                ppu.step(masterCycles: stalled)
                apu.step(masterCycles: stalled)
                clock.advance(masterCycles: stalled)

                remaining -= stalled
                slice -= stalled
                if slice <= 0 { continue }

                // IMPORTANT: do NOT add stalled cycles into cpuMasterAcc.
            }

            // 2) Convert master->CPU cycles with remainder carry (no drift).
            cpuMasterAcc += slice
            let cpuCycles = cpuMasterAcc / 6
            cpuMasterAcc = cpuMasterAcc % 6

            if cpuCycles > 0 {
                if !(cpu.isWaiting && !cpu.nmiPending && !cpu.irqLine) {
                    cpu.step(cycles: cpuCycles)
                }
            }

            // 3) Advance the rest of the system in master cycles.
            bus.step(masterCycles: slice)
            ppu.step(masterCycles: slice)
            apu.step(masterCycles: slice)

            remaining -= slice
            clock.advance(masterCycles: slice)
        }
    }

    func submitFrame(_ fb: Framebuffer) {
        DispatchQueue.main.async {
            self.framebuffer = fb
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
