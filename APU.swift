import Foundation

final class APU {
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
    private var iplEnabled: Bool = true
    private enum StubIPLState { case initClear, waitCommand, recvBlock, jumped }
    private enum StubHandshakePhase { case powerOnSignature, zeroAckCountdown, zeroAckLatched, echo }
    private var stubIPLState: StubIPLState = .initClear
    private var stubIPLClearIndex: Int = 0
    private var stubIPLCmd: u8 = 0
    private var stubIPLPtr: u16 = 0
    private var stubIPLExpected: u8 = 0
    private var stubIPLLastCpuP0: u8 = 0
    private var stubIPLZeroAckCountdown: Int = 0
    private var stubIPLZeroAckRequested: Bool = false
    private var stubHandshakePhase: StubHandshakePhase = .powerOnSignature
    private var stubIPLPort0HardZeroLock: Bool = false
    private var stubIPLZeroAckHoldCountdown: Int = 0
    private var stubIPLDidOneShotEchoRestore: Bool = false
    private var stubIPLSuppressPowerOnSignature: Bool = false
    private var stubIPLHasPresentedPowerOnSignature: Bool = false

    @inline(__always)
    private var usingStubIPL: Bool {
        for b in IPLROM.bytes { if b != 0xFF { return false } }
        return true
    }

    @inline(__always)
    private func signedGreater(_ a: u8, _ b: u8) -> Bool {
        Int8(bitPattern: a) > Int8(bitPattern: b)
    }

    @discardableResult
    func stepStubIPL(_ cpu: SPC700) -> Int {
        guard iplEnabled, usingStubIPL else { return 0 }
        if cpu.pc < u16(IPLROM.base) { cpu.pc = u16(IPLROM.base) }

        let p0 = cpuToApu[0]
        let p1 = cpuToApu[1]
        let p2 = cpuToApu[2]
        let p3 = cpuToApu[3]

        switch stubIPLState {
        case .initClear:
            if stubIPLClearIndex <= 0x00EF {
                ram[stubIPLClearIndex] = 0x00
                stubIPLClearIndex += 1
                return 2
            }
            if stubIPLPort0HardZeroLock {
                apuToCpu = [0x00, 0xBB, 0x00, 0x00]
                lastApuToCpuWrite = [0x00, 0xBB, 0x00, 0x00]
                pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 0, value: 0x00))
                pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 1, value: 0xBB))
            } else {
                apuToCpu = [0xAA, 0xBB, 0x00, 0x00]
                stubIPLHasPresentedPowerOnSignature = true
                lastApuToCpuWrite = [0xAA, 0xBB, 0x00, 0x00]
                if !stubIPLPort0HardZeroLock { pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 0, value: 0xAA)) }
                pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 1, value: 0xBB))
            }
            pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 2, value: 0x00))
            pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 3, value: 0x00))
            stubIPLState = .waitCommand
            stubIPLLastCpuP0 = p0

            if !stubIPLSuppressPowerOnSignature {
                stubHandshakePhase = .powerOnSignature
                stubIPLPort0HardZeroLock = false
                stubIPLZeroAckHoldCountdown = 0
                stubIPLDidOneShotEchoRestore = false
            }
            
            if stubIPLZeroAckRequested {
                stubHandshakePhase = .zeroAckCountdown
                stubIPLZeroAckCountdown = 256
                stubIPLZeroAckRequested = false

                if apuToCpu[0] != 0x00 || apuToCpu[1] != 0xBB {
                    apuToCpu = [0x00, 0xBB, 0x00, 0x00]
                    lastApuToCpuWrite = [0x00, 0xBB, 0x00, 0x00]
                    pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 0, value: 0x00))
                    pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 1, value: 0xBB))
                }
            } else {
                stubIPLZeroAckCountdown = 0
                stubIPLZeroAckRequested = false
                stubHandshakePhase = .powerOnSignature
                stubIPLPort0HardZeroLock = false
                stubIPLZeroAckHoldCountdown = 0
                stubIPLDidOneShotEchoRestore = false
                stubIPLSuppressPowerOnSignature = false
                stubIPLHasPresentedPowerOnSignature = false
            }

            return 6

        case .waitCommand:
            switch stubHandshakePhase {
            case .powerOnSignature:
                if !stubIPLSuppressPowerOnSignature && !stubIPLPort0HardZeroLock && (apuToCpu[0] != 0xAA || apuToCpu[1] != 0xBB) {
                    if stubIPLPort0HardZeroLock {
                        apuToCpu = [0x00, 0xBB, 0x00, 0x00]
                        lastApuToCpuWrite = [0x00, 0xBB, 0x00, 0x00]
                        pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 0, value: 0x00))
                        pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 1, value: 0xBB))
                    } else {
                        apuToCpu = [0xAA, 0xBB, 0x00, 0x00]
                        stubIPLHasPresentedPowerOnSignature = true
                        lastApuToCpuWrite = [0xAA, 0xBB, 0x00, 0x00]
                        if !stubIPLPort0HardZeroLock { pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 0, value: 0xAA)) }
                        pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 1, value: 0xBB))
                    }
                }

                if stubIPLZeroAckRequested && stubIPLZeroAckCountdown == 0 {
                    stubHandshakePhase = .zeroAckCountdown
                    stubIPLZeroAckCountdown = 256
                    stubIPLZeroAckRequested = false

                    apuToCpu = [0x00, 0xBB, 0x00, 0x00]
                    lastApuToCpuWrite = [0x00, 0xBB, 0x00, 0x00]
                    pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 0, value: 0x00))
                    pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 1, value: 0xBB))
                    return 4
                }

                stubIPLLastCpuP0 = p0
                return 4

            case .zeroAckCountdown:
                if stubIPLZeroAckCountdown > 0 { stubIPLZeroAckCountdown -= 1 }
                if apuToCpu[0] != 0x00 || apuToCpu[1] != 0xBB {
                    apuToCpu = [0x00, 0xBB, 0x00, 0x00]
                    lastApuToCpuWrite = [0x00, 0xBB, 0x00, 0x00]
                    pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 0, value: 0x00))
                    pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 1, value: 0xBB))
                }
                if stubIPLZeroAckCountdown == 0 {
                    stubHandshakePhase = .zeroAckLatched
                    stubIPLZeroAckHoldCountdown = 2048
                    if apuToCpu[0] != 0x00 || apuToCpu[1] != 0xBB {
                        apuToCpu = [0x00, 0xBB, 0x00, 0x00]
                        lastApuToCpuWrite = [0x00, 0xBB, 0x00, 0x00]
                        pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 0, value: 0x00))
                        pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 1, value: 0xBB))
                    }
                }

                stubIPLLastCpuP0 = p0
                return 4

            case .zeroAckLatched:
                if stubIPLPort0HardZeroLock {
                    if stubIPLZeroAckHoldCountdown > 0 { stubIPLZeroAckHoldCountdown -= 1 }
                    if stubIPLZeroAckHoldCountdown == 0 {
                        stubIPLPort0HardZeroLock = false
                    }
                }

                if !stubIPLDidOneShotEchoRestore {
                    if stubIPLPort0HardZeroLock {
                        stubIPLLastCpuP0 = p0
                        return 2
                    }
                    if cpu.pc != 0x8082 {
                        stubIPLLastCpuP0 = p0
                        return 2
                    }
                    stubIPLDidOneShotEchoRestore = true
                    stubHandshakePhase = .echo
                    apuToCpu = [0xAA, 0xBB, 0x00, 0x00]
                    stubIPLHasPresentedPowerOnSignature = true
                    lastApuToCpuWrite = [0xAA, 0xBB, 0x00, 0x00]
                    pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 0, value: 0xAA))
                    pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 1, value: 0xBB))
                    stubIPLLastCpuP0 = p0
                    return 2
                }

                if stubHandshakePhase == .echo {
                    stubIPLLastCpuP0 = p0
                    return 2
                }

                if apuToCpu[0] != 0x00 || apuToCpu[1] != 0xBB {
                    apuToCpu = [0x00, 0xBB, 0x00, 0x00]
                    lastApuToCpuWrite = [0x00, 0xBB, 0x00, 0x00]
                    pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 0, value: 0x00))
                    pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 1, value: 0xBB))
                }
                stubIPLLastCpuP0 = p0
                return 4

            case .echo:
                stubIPLLastCpuP0 = p0
            }

            stubIPLCmd = p1
            stubIPLPtr = u16(p2) | (u16(p3) << 8)
            stubIPLExpected = 0x00
            stubIPLLastCpuP0 = p0
            if stubIPLCmd == 0x00 {
                cpu.pc = stubIPLPtr
                stubIPLState = .jumped
            } else {
                stubIPLState = .recvBlock
            }
            return 8

        case .recvBlock:
            if p0 == stubIPLLastCpuP0 { return 2 }
            stubIPLLastCpuP0 = p0
            if signedGreater(p0, stubIPLExpected) {
                apuToCpu[0] = p0
                apuToCpu[1] = 0xBB
                lastApuToCpuWrite[0] = p0
                lastApuToCpuWrite[1] = 0xBB
                pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 0, value: p0))
                pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 1, value: 0xBB))
                let nextCmd = p1
                let nextPtr = u16(p2) | (u16(p3) << 8)
                if nextCmd == 0x00 {
                    cpu.pc = nextPtr
                    stubIPLState = .jumped
                } else {
                    stubIPLCmd = nextCmd
                    stubIPLPtr = nextPtr
                    stubIPLExpected = 0x00
                    stubIPLState = .recvBlock
                }
                return 8
            }
            if p0 == stubIPLExpected {
                ram[Int(stubIPLPtr)] = p1
                stubIPLPtr &+= 1
                stubIPLExpected &+= 1
            }
            apuToCpu[0] = stubIPLExpected
            apuToCpu[1] = 0xBB
            lastApuToCpuWrite[0] = stubIPLExpected
            lastApuToCpuWrite[1] = 0xBB
            pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 0, value: stubIPLExpected))
            pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: 1, value: 0xBB))
            return 6

        case .jumped:
            return 0
        }
    }

    @inline(__always)
    private func pushPortEvent(_ e: APUHandshakeEvent) {
        portEventRing[portEventHead] = e
        portEventHead = (portEventHead + 1) % portEventRing.count
        portEventCount = min(portEventCount + 1, portEventRing.count)
    }

    private func recentPortEvents() -> [APUHandshakeEvent] {
        guard portEventCount > 0 else { return [] }
        let start = (portEventHead - portEventCount + portEventRing.count) % portEventRing.count
        return (0..<portEventCount).map { portEventRing[(start + $0) % portEventRing.count] }
    }

    func debugSnapshot() -> APUDebugSnapshot {
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

    func attach(bus: Bus) { self.bus = bus }

    func reset() {
        portEventHead = 0
        portEventCount = 0
        cpuToApu = [0, 0, 0, 0]
        cpuToApuPending = [0, 0, 0, 0]
        cpuToApuPendingMask = 0
        apuToCpu = [0x00, 0x00, 0x00, 0x00]
        lastCpuToApuWrite = [0, 0, 0, 0]
        lastApuToCpuWrite = [0x00, 0x00, 0x00, 0x00]
        stubIPLState = .initClear
        stubIPLClearIndex = 0
        stubIPLCmd = 0
        stubIPLPtr = 0
        stubIPLExpected = 0
        stubIPLLastCpuP0 = 0
        stubIPLZeroAckCountdown = 0
        stubIPLZeroAckRequested = false
        stubHandshakePhase = .powerOnSignature
        stubIPLPort0HardZeroLock = false
        stubIPLZeroAckHoldCountdown = 0
        stubIPLDidOneShotEchoRestore = false
        stubIPLSuppressPowerOnSignature = false
        stubIPLHasPresentedPowerOnSignature = false
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
        if usingStubIPL, iplEnabled {
            if stepStubIPL(spc) > 0 { return }
        }
        applyPendingCpuPorts()
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

    @inline(__always)
    private func wakeSPCIfHalted() {
        if spc.halted { spc.resume() }
    }

    func cpuReadPort(_ i: Int) -> u8 { apuToCpu[i & 3] }

    func cpuWritePort(_ i: Int, value: u8) {
        if iplEnabled && usingStubIPL && i == 0 {
            if value != 0x00 {
                stubIPLSuppressPowerOnSignature = true
                stubHandshakePhase = .echo
                stubIPLPort0HardZeroLock = false

                apuWritePort(1, value: 0xBB)
                apuWritePort(0, value: value)
                lastCpuToApuWrite[i] = value
                return
            }
        }
        let idx = i & 3
        cpuToApuPending[idx] = value
        cpuToApuPendingMask |= (1 << idx)
        applyPendingCpuPorts()

        if iplEnabled && usingStubIPL {
            if idx == 0 && value == 0x00 {
                if stubHandshakePhase == .powerOnSignature && stubIPLHasPresentedPowerOnSignature {
                    stubIPLPort0HardZeroLock = true
                    stubIPLZeroAckRequested = true
                    stubIPLSuppressPowerOnSignature = true
                }
            }

            if value != 0x00 && stubHandshakePhase == .zeroAckLatched {
                stubHandshakePhase = .echo
                stubIPLPort0HardZeroLock = false
                stubIPLZeroAckHoldCountdown = 0
                stubIPLDidOneShotEchoRestore = false
            }

            if stubHandshakePhase == .echo {
                apuWritePort(idx, value: value)
            }
        }
        lastCpuToApuWrite[idx] = value
        pushPortEvent(APUHandshakeEvent(direction: .cpuToApu, port: idx, value: value))
        wakeSPCIfHalted()
    }

    func apuReadPort(_ i: Int) -> u8 { cpuToApu[i & 3] }

    func apuWritePort(_ i: Int, value: u8) {
        let idx = i & 3
        apuToCpu[idx] = value
        lastApuToCpuWrite[idx] = value
        pushPortEvent(APUHandshakeEvent(direction: .apuToCpu, port: idx, value: value))
    }

    func read8(_ addr: u16) -> u8 {
        let a = Int(addr)
        if iplEnabled && a >= IPLROM.base && a < (IPLROM.base + IPLROM.size) {
            return IPLROM.read(a)
        }
        switch a {
        case 0x00F4...0x00F7: return apuReadPort(a - 0x00F4)
        case 0x00FD: return timers.readCounter(0)
        case 0x00FE: return timers.readCounter(1)
        case 0x00FF: return timers.readCounter(2)
        case 0x00F0...0x00FF: return dsp.read(reg: a & 0x7F)
        default: return ram[a]
        }
    }

    func write8(_ addr: u16, _ value: u8) {
        let a = Int(addr)
        switch a {
        case 0x00F4...0x00F7: apuWritePort(a - 0x00F4, value: value)
        case 0x00F1:
            timers.writeControl(value)
            if (value & 0x80) != 0 {
                iplEnabled = false
            }
        case 0x00FA: timers.writeTarget(0, value)
        case 0x00FB: timers.writeTarget(1, value)
        case 0x00FC: timers.writeTarget(2, value)
        case 0x00F0...0x00FF: dsp.write(reg: a & 0x7F, value: value)
        default: ram[a] = value
        }
    }

    func pullAudio(into buffer: inout [Int16]) {
        audio.pull(into: &buffer)
    }
}
