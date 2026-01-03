import Foundation

final class APU {
    var faultRecorder: FaultRecorder?
    private weak var bus: Bus?

    private var cpuToApu: [u8] = [0, 0, 0, 0]
    private var apuToCpu: [u8] = [0, 0, 0, 0]
    private var cpuToApuPending: [u8] = [0, 0, 0, 0]
    private var cpuToApuPendingMask: u8 = 0
    private var lastCpuToApuWrite: [u8] = [0, 0, 0, 0]
    private var lastApuToCpuWrite: [u8] = [0, 0, 0, 0]

    private var portEventRing: [APUHandshakeEvent] = Array(repeating: APUHandshakeEvent(direction: .cpuToApu, port: 0, value: 0), count: 32)
    private var portEventHead: Int = 0
    private var portEventCount: Int = 0

    private var ram: [u8] = Array(repeating: 0, count: 65536)
    private let spc = SPC700()
    private let interp = SPC700Interpreter()
    private let spcJIT = SPC700JIT()
    private let dsp = DSP()
    private let audio = AudioBuffer(sampleRate: 32000)
    private let timers = SPCTimers()

    private var spcCycleAcc: Int = 0
    private static let masterCyclesPerSPC = 21
    private static let masterCyclesPerCPU = 6
    private var iplEnabled: Bool = true

    @inline(__always) func attach(bus: Bus) { self.bus = bus }

    @inline(__always) private func pushPortEvent(_ e: APUHandshakeEvent) {
        portEventRing[portEventHead] = e
        portEventHead = (portEventHead + 1) % portEventRing.count
        if portEventCount < portEventRing.count { portEventCount += 1 }
    }

    @inline(__always) private func recentPortEvents() -> [APUHandshakeEvent] {
        guard portEventCount > 0 else { return [] }
        let start = (portEventHead - portEventCount + portEventRing.count) % portEventRing.count
        return (0..<portEventCount).map { portEventRing[(start + $0) % portEventRing.count] }
    }

    @inline(__always) func debugSnapshot() -> APUDebugSnapshot {
        let reason: String
        switch spc.haltReason {
        case .none: reason = "none"
        case .sleep: reason = "sleep"
        case .stop: reason = "stop"
        }
        return APUDebugSnapshot(
            spcA: spc.a, spcX: spc.x, spcY: spc.y, spcSP: spc.sp, spcPC: spc.pc, spcPSW: spc.psw,
            spcHalted: spc.halted, spcHaltReason: reason, iplEnabled: iplEnabled,
            spcJITEnabled: spcJIT.enabled, cpuToApu: cpuToApu, apuToCpu: apuToCpu,
            cpuToApuPendingMask: cpuToApuPendingMask, lastCpuToApuWrite: lastCpuToApuWrite,
            lastApuToCpuWrite: lastApuToCpuWrite, recentPortEvents: recentPortEvents()
        )
    }

    @inline(__always) func reset() {
        portEventHead = 0
        portEventCount = 0
        cpuToApu = [0, 0, 0, 0]
        cpuToApuPending = [0, 0, 0, 0]
        cpuToApuPendingMask = 0
        apuToCpu = [0, 0, 0, 0]
        lastCpuToApuWrite = [0, 0, 0, 0]
        lastApuToCpuWrite = [0, 0, 0, 0]
        ram = Array(repeating: 0, count: 65536)
        spc.reset()
        spcJIT.reset()
        spcJIT.enabled = false
        dsp.reset()
        audio.reset()
        timers.reset()
        iplEnabled = true
        spcCycleAcc = 0
    }

    @inline(__always) private func applyPendingCpuPorts() {
        let m = cpuToApuPendingMask
        if m == 0 { return }
        for i in 0..<4 where (m & (1 << i)) != 0 {
            cpuToApu[i] = cpuToApuPending[i]
        }
        cpuToApuPendingMask = 0
    }

    @inline(__always) private func wakeSPCIfHalted() {
        if spc.halted { spc.resume() }
    }

    @inline(__always) func step(masterCycles: Int) {
        spcCycleAcc += masterCycles
        let cycles = spcCycleAcc / Self.masterCyclesPerSPC
        if cycles <= 0 { return }
        spcCycleAcc -= cycles * Self.masterCyclesPerSPC

        applyPendingCpuPorts()

        if cycles > 0 {
            spcJIT.run(cpu: spc, apu: self, interpreter: interp, cycles: cycles)
            timers.step(spcCycles: cycles)
            for _ in 0..<cycles {
                let (l, r) = dsp.mix(
                    readRAM: { self.ram[$0 & 0xFFFF] },
                    writeRAM: { addr, val in self.ram[addr & 0xFFFF] = u8(val & 0xFF) }
                )
                audio.push(left: l, right: r)
            }
        }
    }

    @inline(__always) func cpuReadPort(_ i: Int) -> u8 {
        step(masterCycles: Self.masterCyclesPerCPU)
        return apuToCpu[i & 3]
    }

    @inline(__always) func cpuWritePort(_ i: Int, value: u8) {
        let idx = i & 3
        cpuToApuPending[idx] = value
        cpuToApuPendingMask |= (1 << idx)
        lastCpuToApuWrite[idx] = value
        pushPortEvent(APUHandshakeEvent(direction: .cpuToApu, port: idx, value: value))
        wakeSPCIfHalted()
        step(masterCycles: Self.masterCyclesPerCPU)
    }

    @inline(__always) func apuReadPort(_ i: Int) -> u8 { cpuToApu[i & 3] }

    @inline(__always) func apuWritePort(_ i: Int, value: u8) {
        let idx = i & 3
        apuToCpu[idx] = value
        lastApuToCpuWrite[idx] = value
        pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: idx, value: value))
    }

    @inline(__always) func read8(_ addr: u16) -> u8 {
        let a = Int(addr)
        if iplEnabled, a >= IPLROM.base, a < (IPLROM.base + IPLROM.size) { return IPLROM.read(a) }
        switch a {
        case 0x00F4...0x00F7: return apuReadPort(a - 0x00F4)
        case 0x00FD: return timers.readCounter(0)
        case 0x00FE: return timers.readCounter(1)
        case 0x00FF: return timers.readCounter(2)
        case 0x00F0...0x00FF: return dsp.read(reg: a & 0x7F)
        default: return ram[a]
        }
    }

    @inline(__always) func write8(_ addr: u16, _ value: u8) {
        let a = Int(addr)
        switch a {
        case 0x00F4...0x00F7:
            apuWritePort(a - 0x00F4, value: value)
        case 0x00F1:
            timers.writeControl(value)
            if (value & 0x10) != 0 {
                cpuToApu[0] = 0
                cpuToApu[1] = 0
                cpuToApuPending[0] = 0
                cpuToApuPending[1] = 0
                cpuToApuPendingMask &= ~0x03
            }
            if (value & 0x20) != 0 {
                cpuToApu[2] = 0
                cpuToApu[3] = 0
                cpuToApuPending[2] = 0
                cpuToApuPending[3] = 0
                cpuToApuPendingMask &= ~0x0C
            }
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

    @inline(__always) func pullAudio(into buffer: inout [Int16]) {
        audio.pull(into: &buffer)
    }
}
