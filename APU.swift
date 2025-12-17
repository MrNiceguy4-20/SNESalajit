import Foundation

/// APU (Phase 6.1)
/// - SPC700 core execution via staged JIT router (JIT is OFF by default)
/// - Timers + ports + DSP register window
/// - IPL ROM mapping at $FFC0-$FFFF controlled by $F1 bit7
final class APU {
    private weak var bus: Bus?

    private var cpuToApu: [u8] = [0,0,0,0]
    private var apuToCpu: [u8] = [0,0,0,0]

    // CPU->APU port writes are latched at the next APU step boundary.
    private var cpuToApuPending: [u8] = [0,0,0,0]
    private var cpuToApuPendingMask: u8 = 0

    private var ram: [u8] = Array(repeating: 0, count: 65536)

    private let spc = SPC700()
    private let interp = SPC700Interpreter()
    private let spcJIT = SPC700JIT()   // Phase 6.x: staged JIT router (fallback to interpreter)
    private let dsp = DSP()
    private let audio = AudioBuffer(sampleRate: 32000)
    private let timers = SPCTimers()

    private var spcCycleAcc: Int = 0
    private static let masterCyclesPerSPC = 21

    // IPL enable (true after reset, cleared by $F1 bit7 = 1)
    private var iplEnabled: Bool = true

    func attach(bus: Bus) { self.bus = bus }

    func reset() {
        cpuToApu = [0,0,0,0]
        apuToCpu = [0,0,0,0]
        cpuToApuPending = [0,0,0,0]
        cpuToApuPendingMask = 0
        ram = Array(repeating: 0, count: 65536)

        spc.reset()
        spcJIT.reset()
        spcJIT.enabled = false  // keep behavior identical unless explicitly enabled by caller

        dsp.reset()
        audio.reset()
        timers.reset()

        iplEnabled = true
        spcCycleAcc = 0
    }

    @inline(__always)
    private func applyPendingCpuPorts() {
        let m = cpuToApuPendingMask
        if m == 0 { return }
        for i in 0..<4 {
            if (m & (1 << i)) != 0 {
                cpuToApu[i] = cpuToApuPending[i]
            }
        }
        cpuToApuPendingMask = 0
    }

    func step(masterCycles: Int) {
        spcCycleAcc += masterCycles
        let cycles = spcCycleAcc / Self.masterCyclesPerSPC
        if cycles <= 0 { return }
        spcCycleAcc -= cycles * Self.masterCyclesPerSPC

        // Phase 6.1: route through JIT runner (safe fallback to interpreter)
        spcJIT.run(cpu: spc, apu: self, interpreter: interp, cycles: cycles)

        timers.step(spcCycles: cycles)

        for _ in 0..<cycles {
            let (l,r) = dsp.mix(
                readRAM: { self.ram[$0 & 0xFFFF] },
                writeRAM: { addr, val in self.ram[addr & 0xFFFF] = u8(val & 0xFF) }
            )
            audio.push(left: l, right: r)
        }
    }

    // MARK: - CPU/APU ports (SNES side)
    func cpuReadPort(_ i: Int) -> u8 { apuToCpu[i & 3] }
    func cpuWritePort(_ i: Int, value: u8) {
        let idx = i & 3
        cpuToApuPending[idx] = value
        cpuToApuPendingMask |= (1 << idx)
    }
    func apuReadPort(_ i: Int) -> u8 { cpuToApu[i & 3] }
    func apuWritePort(_ i: Int, value: u8) { apuToCpu[i & 3] = value }

    // MARK: - SPC memory map
    func read8(_ addr: u16) -> u8 {
        let a = Int(addr)

        // IPL ROM mapping
        if iplEnabled && a >= IPLROM.base && a < (IPLROM.base + IPLROM.size) {
            return IPLROM.read(a)
        }

        switch a {
        case 0x00F4...0x00F7:
            return apuReadPort(a - 0x00F4)

        case 0x00FD:
            return timers.readCounter(0)
        case 0x00FE:
            return timers.readCounter(1)
        case 0x00FF:
            return timers.readCounter(2)

        case 0x00F0...0x00FF:
            return dsp.read(reg: a & 0x7F)

        default:
            return ram[a]
        }
    }

    func write8(_ addr: u16, _ value: u8) {
        let a = Int(addr)

        switch a {
        case 0x00F4...0x00F7:
            apuWritePort(a - 0x00F4, value: value)

        case 0x00F1:
            // Timer enable bits 0..2; bit7 disables IPL mapping (sticky)
            timers.writeControl(value)
            if (value & 0x80) != 0 { iplEnabled = false }

        case 0x00FA:
            timers.writeTarget(0, value)
        case 0x00FB:
            timers.writeTarget(1, value)
        case 0x00FC:
            timers.writeTarget(2, value)

        case 0x00F0...0x00FF:
            dsp.write(reg: a & 0x7F, value: value)

        default:
            ram[a] = value
        }
    }

    func pullAudio(into buffer: inout [Int16]) {
        audio.pull(into: &buffer)
    }
}
