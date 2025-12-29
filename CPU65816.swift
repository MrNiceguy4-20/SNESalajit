import Foundation

final class CPU65816 {
    private static let forceEmulationOnly: Bool = true

    struct Registers {
        var a: u16 = 0
        var x: u16 = 0
        var y: u16 = 0
        var sp: u16 = 0x01FF
        var dp: u16 = 0
        var db: u8 = 0
        var pb: u8 = 0
        var pc: u16 = 0
        var p: Status = .init()
        var emulationMode: Bool = true
    }

    struct Status: OptionSet {
        let rawValue: u8
        init(rawValue: u8 = 0x34) { self.rawValue = rawValue }

        static let carry    = Status(rawValue: 1 << 0)
        static let zero     = Status(rawValue: 1 << 1)
        static let irqDis   = Status(rawValue: 1 << 2)
        static let decimal  = Status(rawValue: 1 << 3)
        static let index8   = Status(rawValue: 1 << 4)
        static let mem8     = Status(rawValue: 1 << 5)
        static let overflow = Status(rawValue: 1 << 6)
        static let negative = Status(rawValue: 1 << 7)
    }

    private(set) var r = Registers()
    private weak var bus: Bus?

    private let interpreter = CPUInterpreter()
    private let jit = CPUJIT()

    var useJIT: Bool = false
    private var lastLoggedUseJIT: Bool?

    private(set) var nmiLine: Bool = false
    private(set) var irqLine: Bool = false

    var nmiPending: Bool = false
    private(set) var isWaiting: Bool = false

    func attach(bus: Bus) { self.bus = bus }

    func reset() {
        r = Registers()
        r.emulationMode = true
        forceEmulationFlags()

        let lo0 = read8(0x00, 0xFFFC)
        let hi0 = read8(0x00, 0xFFFD)
        var pc0 = make16(lo0, hi0)

        if pc0 == 0xFFFF || pc0 < 0x8000 {
            let lo1 = read8(0x80, 0xFFFC)
            let hi1 = read8(0x80, 0xFFFD)
            let pc1 = make16(lo1, hi1)
            if pc1 != 0xFFFF && pc1 >= 0x8000 {
                pc0 = pc1
            }
        }

        if pc0 == 0xFFFF || pc0 < 0x8000 {
            pc0 = 0x8000
        }

        r.pb = 0x00
        r.pc = pc0

        nmiLine = false
        irqLine = false
        nmiPending = false
        isWaiting = false

        interpreter.reset()
        jit.reset()
        lastLoggedUseJIT = nil
    }

    func setNMI(_ asserted: Bool) {
        if asserted && !nmiLine {
            nmiPending = true
        }
        nmiLine = asserted
    }

    func setIRQ(_ asserted: Bool) {
        irqLine = asserted
    }

    func step(cycles: Int) {
        if isWaiting && !nmiPending && !irqLine { return }

        guard let bus else { return }

        var remaining = cycles

        while remaining > 0 {
            if nmiPending {
                isWaiting = false
                nmiPending = false
                serviceInterrupt(.nmi)
                continue
            }

            if irqLine && !flag(.irqDis) {
                isWaiting = false
                serviceInterrupt(.irq)
                irqLine = false
                continue
            }

            if isWaiting {
                remaining -= 1
                continue
            }

            let before = remaining

            if useJIT {
                jit.step(cpu: self, bus: bus, cycles: remaining)
            } else {
                interpreter.step(cpu: self, bus: bus, cycles: remaining)
            }

            if remaining == before {
                remaining -= 1
            }
        }
    }

    @inline(__always) func read8(_ bank: u8, _ addr: u16) -> u8 {
        bus?.read8(bank: bank, addr: addr) ?? 0xFF
    }

    @inline(__always) func write8(_ bank: u8, _ addr: u16, _ value: u8) {
        bus?.write8(bank: bank, addr: addr, value: value)
    }

    @inline(__always) func read16(_ bank: u8, _ addr: u16) -> u16 {
        let lo = read8(bank, addr)
        let hi = read8(bank, addr &+ 1)
        return make16(lo, hi)
    }

    @inline(__always) func write16(_ bank: u8, _ addr: u16, _ value: u16) {
        write8(bank, addr, lo8(value))
        write8(bank, addr &+ 1, hi8(value))
    }

    @inline(__always) func peek8() -> u8 {
        read8(r.pb, r.pc)
    }

    @inline(__always) func fetch8() -> u8 {
        if isWaiting && !nmiPending && !irqLine {
            return 0xEA
        }
        let v = read8(r.pb, r.pc)
        r.pc &+= 1
        return v
    }

    @inline(__always) func fetch16() -> u16 {
        let lo = fetch8()
        let hi = fetch8()
        return make16(lo, hi)
    }

    @inline(__always) func fetchOpcode() -> u8 { fetch8() }

    @inline(__always) func advancePC(_ count: Int) {
        r.pc &+= u16(truncatingIfNeeded: count)
    }

    @inline(__always) func flag(_ f: Status) -> Bool { (r.p.rawValue & f.rawValue) != 0 }

    @inline(__always) func setFlag(_ f: Status, _ on: Bool) {
        if on { r.p = Status(rawValue: r.p.rawValue | f.rawValue) }
        else  { r.p = Status(rawValue: r.p.rawValue & ~f.rawValue) }
    }

    @inline(__always) func forceEmulationFlags() {
        r.p = Status(rawValue: r.p.rawValue | Status.mem8.rawValue | Status.index8.rawValue)
        r.sp = 0x0100 | (r.sp & 0x00FF)
    }

    @inline(__always) func aIs8() -> Bool { r.emulationMode || flag(.mem8) }
    @inline(__always) func xIs8() -> Bool { r.emulationMode || flag(.index8) }

    @inline(__always) func updateNZ8(_ v: u8) {
        setFlag(.zero, v == 0)
        setFlag(.negative, (v & 0x80) != 0)
    }

    @inline(__always) func updateNZ16(_ v: u16) {
        setFlag(.zero, v == 0)
        setFlag(.negative, (v & 0x8000) != 0)
    }

    func push8(_ v: u8) {
        if r.emulationMode {
            r.sp = 0x0100 | (r.sp & 0x00FF)
            let addr = u16(0x0100) | (r.sp & 0x00FF)
            write8(0x00, addr, v)
            r.sp = 0x0100 | ((r.sp &- 1) & 0x00FF)
        } else {
            write8(0x00, r.sp, v)
            r.sp &-= 1
        }
    }

    func pull8() -> u8 {
        if r.emulationMode {
            r.sp = 0x0100 | (r.sp & 0x00FF)
            r.sp = 0x0100 | ((r.sp &+ 1) & 0x00FF)
            let addr = u16(0x0100) | (r.sp & 0x00FF)
            return read8(0x00, addr)
        } else {
            r.sp &+= 1
            return read8(0x00, r.sp)
        }
    }

    func push16(_ v: u16) {
        push8(hi8(v))
        push8(lo8(v))
    }

    func pull16() -> u16 {
        let lo = pull8()
        let hi = pull8()
        return make16(lo, hi)
    }

    @inline(__always) func setPC(_ pc: u16) { r.pc = pc }
    @inline(__always) func setPB(_ pb: u8) { r.pb = pb }
    @inline(__always) func setDB(_ db: u8) { r.db = db }
    @inline(__always) func setDP(_ dp: u16) { r.dp = dp }

    @inline(__always) func setA(_ v: u16) { r.a = v }
    @inline(__always) func setX(_ v: u16) { r.x = v }
    @inline(__always) func setY(_ v: u16) { r.y = v }

    @inline(__always) func setA8(_ v: u8) { r.a = (r.a & 0xFF00) | u16(v) }
    @inline(__always) func setX8(_ v: u8) { r.x = (r.x & 0xFF00) | u16(v) }
    @inline(__always) func setY8(_ v: u8) { r.y = (r.y & 0xFF00) | u16(v) }

    @inline(__always) func setSP(_ v: u16) { r.sp = v; if r.emulationMode { forceEmulationFlags() } }
    @inline(__always) func setSPLo(_ v: u8) { r.sp = (r.sp & 0xFF00) | u16(v); if r.emulationMode { forceEmulationFlags() } }

    @inline(__always) func a8() -> u8 { u8(truncatingIfNeeded: r.a) }
    @inline(__always) func x8() -> u8 { u8(truncatingIfNeeded: r.x) }
    @inline(__always) func y8() -> u8 { u8(truncatingIfNeeded: r.y) }

    @inline(__always) func readData8(_ addr: u16) -> u8 { read8(r.db, addr) }
    @inline(__always) func writeData8(_ addr: u16, _ v: u8) { write8(r.db, addr, v) }

    @inline(__always) func readDP8(_ addr: u16) -> u8 { read8(0x00, addr) }
    @inline(__always) func writeDP8(_ addr: u16, _ v: u8) { write8(0x00, addr, v) }

    @inline(__always) func pForPush(brk: Bool) -> u8 {
        var p = r.p.rawValue
        if r.emulationMode {
            p |= 0x20
            if brk { p |= 0x10 } else { p &= 0xEF }
        }
        return p
    }

    @inline(__always) func setPFromPull(_ v: u8) {
        if r.emulationMode {
            r.p = Status(rawValue: v | 0x20)
            forceEmulationFlags()
        } else {
            r.p = Status(rawValue: v)
        }
    }

    enum InterruptKind { case nmi, irq, brk, cop }

    func serviceInterrupt(_ kind: InterruptKind) {
        let vectorAddr: u16
        if r.emulationMode {
            switch kind {
            case .nmi: vectorAddr = 0xFFFA
            case .irq, .brk: vectorAddr = 0xFFFE
            case .cop: vectorAddr = 0xFFF4
            }
        } else {
            switch kind {
            case .nmi: vectorAddr = 0xFFEA
            case .irq: vectorAddr = 0xFFEE
            case .brk: vectorAddr = 0xFFE6
            case .cop: vectorAddr = 0xFFE4
            }
        }

        if r.emulationMode {
            r.sp = 0x0100 | (r.sp & 0x00FF)
        }

        let isBrkLike = (kind == .brk || kind == .cop)

        if isBrkLike {
            _ = fetch8()
        }

        if !r.emulationMode {
            push8(r.pb)
        }
        let retPC: u16 = r.pc
        push8(hi8(retPC))
        push8(lo8(retPC))
        push8(pForPush(brk: isBrkLike))

        setFlag(.irqDis, true)
        setFlag(.decimal, false)

        func fetchVector(_ vectorAddr: u16) -> u16 {
            var lo = read8(0x00, vectorAddr)
            var hi = read8(0x00, vectorAddr &+ 1)
            var vec = make16(lo, hi)

            if vec == 0xFFFF || vec < 0x8000 {
                let lo1 = read8(0x80, vectorAddr)
                let hi1 = read8(0x80, vectorAddr &+ 1)
                let vec1 = make16(lo1, hi1)
                if vec1 != 0xFFFF && vec1 >= 0x8000 {
                    lo = lo1
                    hi = hi1
                    vec = vec1
                }
            }
            return vec
        }

        var vec = fetchVector(vectorAddr)

        if !r.emulationMode, kind == .brk, (vec == 0xFFFF || vec < 0x8000) {
            vec = fetchVector(0xFFEE)
            if vec == 0xFFFF || vec < 0x8000 {
                vec = fetchVector(0xFFFE)
            }
        }

        r.pb = 0x00
        r.pc = vec
    }
    
    func wai() {
        isWaiting = true
    }

    func rep(_ mask: u8) {
        r.p = Status(rawValue: r.p.rawValue & ~mask)
        if r.emulationMode { forceEmulationFlags() }
        if xIs8() {
            r.x = u16(u8(truncatingIfNeeded: r.x))
            r.y = u16(u8(truncatingIfNeeded: r.y))
        }
        if aIs8() {
            r.a = u16(u8(truncatingIfNeeded: r.a))
        }
    }

    func sep(_ mask: u8) {
        r.p = Status(rawValue: r.p.rawValue | mask)
        if r.emulationMode { forceEmulationFlags() }
        if xIs8() {
            r.x = u16(u8(truncatingIfNeeded: r.x))
            r.y = u16(u8(truncatingIfNeeded: r.y))
        }
        if aIs8() {
            r.a = u16(u8(truncatingIfNeeded: r.a))
        }
    }

    func xce() {
        let c = flag(.carry)
        let e = r.emulationMode

        if CPU65816.forceEmulationOnly {
            r.emulationMode = true
            setFlag(.carry, e)
            forceEmulationFlags()
            r.sp = 0x0100 | (r.sp & 0x00FF)
            return
        }

        r.emulationMode = c
        setFlag(.carry, e)

        if r.emulationMode {
            forceEmulationFlags()
            r.sp = 0x0100 | (r.sp & 0x00FF)
        }
    }

    struct InstructionTraceEntry: Sendable {
        let pb: u8
        let pc: u16
        let bytes: [u8]
        let text: String
        let usedJIT: Bool
    }

    private var traceBuf: [InstructionTraceEntry] = Array(
        repeating: InstructionTraceEntry(pb: 0, pc: 0, bytes: [], text: "", usedJIT: false),
        count: 256
    )
    private var traceHead: Int = 0
    private var traceCount: Int = 0
    private var traceLast: InstructionTraceEntry?

    private func resetTrace() {
        traceHead = 0
        traceCount = 0
        traceLast = nil
    }

    func recordInstruction(pb: u8, pc: u16, bytes: [u8], text: String, usedJIT: Bool) {
        let entry = InstructionTraceEntry(pb: pb, pc: pc, bytes: bytes, text: text, usedJIT: usedJIT)
        traceBuf[traceHead] = entry
        traceHead = (traceHead + 1) & (traceBuf.count - 1)
        traceCount = min(traceCount + 1, traceBuf.count)
        traceLast = entry
    }

    func recordEvent(pb: u8, pc: u16, text: String, usedJIT: Bool) {
        recordInstruction(pb: pb, pc: pc, bytes: [], text: text, usedJIT: usedJIT)
    }

    var lastInstruction: InstructionTraceEntry? { traceLast }

    func instructionTrace() -> [InstructionTraceEntry] {
        guard traceCount > 0 else { return [] }
        let start = (traceHead - traceCount + traceBuf.count) & (traceBuf.count - 1)
        var out: [InstructionTraceEntry] = []
        out.reserveCapacity(traceCount)
        for i in 0..<traceCount {
            out.append(traceBuf[(start + i) & (traceBuf.count - 1)])
        }
        return out
    }
}
