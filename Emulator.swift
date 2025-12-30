import Foundation
import CryptoKit
import Combine

final class Emulator {
    let bus = Bus()
    let cpu = CPU65816()
    let ppu = PPU()
    let apu = APU()
    let irq = InterruptController()
    @Published var framebuffer: Framebuffer?
    private let clock = MasterClock()
    private var romURL: URL?
    private(set) var romName: String?
    private(set) var romSHA1: String?

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

    @inline(__always) func reset() {
        irq.reset()
        clock.reset()
        bus.reset()
        apu.reset()
        cpu.reset()
    }

    @inline(__always) func loadROM(url: URL) throws {
        saveSRAM()

        let cart = try ROMLoader.load(url: url)
        romURL = url
        romName = url.lastPathComponent
        if let data = try? Data(contentsOf: url) {
            let digest = Insecure.SHA1.hash(data: data)
            romSHA1 = digest.map { String(format: "%02x", $0) }.joined()
        } else {
            romSHA1 = nil
        }
        loadSRAMIfPresent(for: cart)
        bus.insertCartridge(cart)
        reset()
    }

    @inline(__always) func step(seconds: Double) {
        let cyclesToRun = Int(MasterClock.masterHz * seconds)
        step(masterCycles: cyclesToRun)
    }

    @inline(__always) func step(masterCycles: Int) {
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

            let cpuCycles = clock.cpuCycles(forMasterCycles: slice)

            if cpuCycles > 0 {
                if !(cpu.isWaiting && !cpu.nmiPending && !cpu.irqLine) {
                    cpu.step(cycles: cpuCycles)
                }
            }

            bus.step(masterCycles: slice)
            ppu.step(masterCycles: slice)
            apu.step(masterCycles: slice)

            remaining -= slice
            clock.advance(masterCycles: slice)
        }
    }

    @inline(__always) func submitFrame(_ fb: Framebuffer) {
        DispatchQueue.main.async {
            self.framebuffer = fb
        }
    }

    @inline(__always) func saveSRAM() {
        guard let cart = bus.cartridge, cart.hasSRAM, let saveURL = saveFileURL else { return }
        guard let bytes = cart.serializeSRAM() else { return }

        do {
            try Data(bytes).write(to: saveURL)
            Log.info("Saved SRAM to \(saveURL.path)")
        } catch {
            Log.warn("Failed to save SRAM: \(error.localizedDescription)")
        }
    }

    @inline(__always) private func loadSRAMIfPresent(for cart: Cartridge) {
        guard cart.hasSRAM, let saveURL = saveFileURL else { return }
        guard let data = try? Data(contentsOf: saveURL) else { return }

        let slice = data.prefix(cart.sramCapacity)
        cart.loadSRAM([u8](slice))
        Log.info(String(format: "Loaded %d bytes of SRAM from %@", slice.count, saveURL.lastPathComponent))
    }

    @inline(__always) private var saveFileURL: URL? {
        guard let romURL else { return nil }
        return romURL.deletingPathExtension().appendingPathExtension("srm")
    }
}
