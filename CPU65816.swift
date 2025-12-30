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
    var isStopped: Bool = false
    
    @inline(__always) func attach(bus: Bus) { self.bus = bus }

    @inline(__always) func reset() {
        r = Registers()
        r.emulationMode = true
        forceEmulationFlags()

        nmiLine = false
        irqLine = false
        nmiPending = false
        isWaiting = false
        isStopped = false

        guard let bus = bus else {
            // No bus attached yet; leave PC at 0.
            r.pb = 0x00
            r.pc = 0x0000
            nmiLine = false
            irqLine = false
            nmiPending = false
            isWaiting = false
            interpreter.reset()
            jit.reset()
            lastLoggedUseJIT = nil
            resetTrace()
            return
        }

        @inline(__always)
        func entryOpcodeLooksValid(_ op: u8) -> Bool {
            // Reject common "obviously wrong" entrypoints: BRK/COP/RTI/RTS/RTL/WAI/STP/BRA (and 0xFF).
            if op == 0xFF { return false }
            switch op {
            case 0x00, 0x02, 0x40, 0x60, 0x6B, 0xDB, 0x82, 0x42:
                return false
            default:
                return true
            }
        }

        // Some ROMs (or mapping ambiguities) make the reset vector readable through both $00 and $80 mirrors.
        // Validate the entry bytes in *both* mirrors and prefer the one that looks sane, to avoid landing on
        // obviously-wrong opcodes like RTI (which would immediately pull garbage from the stack after reset).
        @inline(__always)
        func entryLooksSane4(_ b0: u8, _ b1: u8, _ b2: u8, _ b3: u8) -> Bool {
            if !entryOpcodeLooksValid(b0) { return false }
            if b0 == b1 && b1 == b2 && b2 == b3 {
                // Repeated open-bus patterns show up as 0x00/0x20/0xFF runs.
                if b0 == 0x00 || b0 == 0x20 || b0 == 0xFF { return false }
            }
            return true
        }

        @inline(__always)
        func choosePBForEntry(_ pc: u16) -> u8 {
            let b80_0 = bus.read8_physical(bank: 0x80, addr: pc)
            let b80_1 = bus.read8_physical(bank: 0x80, addr: pc &+ 1)
            let b80_2 = bus.read8_physical(bank: 0x80, addr: pc &+ 2)
            let b80_3 = bus.read8_physical(bank: 0x80, addr: pc &+ 3)

            let b00_0 = bus.read8_physical(bank: 0x00, addr: pc)
            let b00_1 = bus.read8_physical(bank: 0x00, addr: pc &+ 1)
            let b00_2 = bus.read8_physical(bank: 0x00, addr: pc &+ 2)
            let b00_3 = bus.read8_physical(bank: 0x00, addr: pc &+ 3)

            if entryLooksSane4(b80_0, b80_1, b80_2, b80_3) { return 0x80 }
            if entryLooksSane4(b00_0, b00_1, b00_2, b00_3) { return 0x00 }
            // Default to $00; the CPU will still refuse low vectors below.
            return 0x00
        }

        @inline(__always)
        func readVectorCandidate(_ bank: u8, _ addr: u16) -> u16 {
            let lo = bus.read8_physical(bank: bank, addr: addr)
            let hi = bus.read8_physical(bank: bank, addr: addr &+ 1)
            return make16(lo, hi)
        }

        // Choose a plausible reset vector, trying both cartridge mappings when available.
        var chosenPC: u16 = 0x0000
        var chosenMapping: Cartridge.Mapping? = nil

        if let cart = bus.cartridge {
            let primary = cart.mapping
            let alt: Cartridge.Mapping = (primary == .hiROM) ? .loROM : (primary == .loROM ? .hiROM : .unknown)

            func tryMapping(_ mapping: Cartridge.Mapping) -> u16? {
                guard mapping != .unknown else { return nil }
                guard let vec = bus.readVector16(cart, mapping: mapping, addr: 0xFFFC) else { return nil }
                if vec == 0x0000 || vec == 0xFFFF { return nil }
                if vec < 0x8000 { return nil }
                // Validate against both mirrors; some mappings present ROM code in the $80 mirror.
                let pb = choosePBForEntry(vec)
                let op = bus.read8_physical(bank: pb, addr: vec)
                guard entryOpcodeLooksValid(op) else { return nil }
                return vec
            }

            if let v = tryMapping(primary) {
                chosenPC = v
                chosenMapping = primary
            } else if let v = tryMapping(alt) {
                chosenPC = v
                chosenMapping = alt
            }
        }

        // Fallback: use the current bus mapping (which may include overrides).
        if chosenPC == 0x0000 {
            let v0 = readVectorCandidate(0x00, 0xFFFC)
            if v0 != 0xFFFF, v0 >= 0x8000, entryOpcodeLooksValid(bus.read8_physical(bank: choosePBForEntry(v0), addr: v0)) {
                chosenPC = v0
            } else {
                let v1 = readVectorCandidate(0x80, 0xFFFC)
                if v1 != 0xFFFF, v1 >= 0x8000, entryOpcodeLooksValid(bus.read8_physical(bank: choosePBForEntry(v1), addr: v1)) {
                    chosenPC = v1
                }
            }
        }

        if chosenPC == 0x0000 {
            // Last-resort safe-ish fallback (should never happen for a valid cart).
            chosenPC = 0x8000
        }

        // If we identified a more plausible mapping than the ROM header reports,
        // force it so instruction fetches and subsequent vector reads use it.
        if let m = chosenMapping {
            bus.forceCartridgeMapping(m)
        }

        var chosenPB = choosePBForEntry(chosenPC)
        // PB fix: if reset vector in ROM space, force bank $80 so we fetch from ROM mirror.
        if chosenPC >= 0x8000 {
            chosenPB = 0x80
        }
        // Final sanity check against *actual* mapped bus fetch, not just physical reads.
        // If we would start on an obviously-wrong opcode (e.g. RTI/BRK/open-bus patterns),
        // fall back to a safe ROM-ish entry to avoid immediate BRK/RTI loops.
        let entryOp = bus.read8(bank: chosenPB, addr: chosenPC)
        if !entryOpcodeLooksValid(entryOp) {
            chosenPC = 0x8000
            chosenPB = choosePBForEntry(chosenPC)
        }

        r.pb = chosenPB
        r.pc = chosenPC

        nmiLine = false
        irqLine = false
        nmiPending = false
        isWaiting = false
        isStopped = false

        interpreter.reset()
        jit.reset()
        lastLoggedUseJIT = nil
        resetTrace()
    }

    @inline(__always) func setNMI(_ asserted: Bool) {
        if asserted && !nmiLine {
            nmiPending = true
        }
        nmiLine = asserted
    }

    @inline(__always) func setIRQ(_ asserted: Bool) {
        irqLine = asserted
    }

    @inline(__always) func step(cycles: Int) {
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

    @inline(__always) func pageCrossed(_ addr1: u16, _ addr2: u16) -> Bool {
        return (addr1 & 0xFF00) != (addr2 & 0xFF00)
    }

    @inline(__always) func dpLowBytePenalty() -> Int {
        return (r.dp & 0xFF) != 0 ? 1 : 0
    }
    
    @inline(__always) func stp() {
        self.isStopped = true
    }
    @inline(__always) func read8(_ bank: u8, _ addr: u16) -> u8 {
        bus?.read8(bank: bank, addr: addr) ?? 0xFF
    }

    // Instruction fetch should not be affected by the CPU wait/open-bus shortcut, and should
    // honor cartridge mapping rules as implemented by Bus.read8_physical.
    @inline(__always) func readInstr8(_ bank: u8, _ addr: u16) -> u8 {
        bus?.read8_physical(bank: bank, addr: addr) ?? 0xFF
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
        readInstr8(r.pb, r.pc)
    }

    @inline(__always) func fetch8() -> u8 {
        if isWaiting && !nmiPending && !irqLine {
            return 0xEA
        }
        let v = readInstr8(r.pb, r.pc)
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

    @inline(__always) func push8(_ v: u8) {
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

    @inline(__always) func pull8() -> u8 {
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

    @inline(__always) func push16(_ v: u16) {
        push8(hi8(v))
        push8(lo8(v))
    }

    @inline(__always) func pull16() -> u16 {
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

    @inline(__always) func serviceInterrupt(_ kind: InterruptKind) {
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
            // BRK/COP are two-byte instructions; skip the signature byte so RTI returns to the next instruction.
            r.pc &+= 1
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

        // Prefer cartridge-aware vector reads when possible so we respect any mapping override and
        // can apply plausibility checks (e.g. avoid vectors that land on RTI/BRK/open bus).
        @inline(__always) func fetchVectorViaBus(_ addr: u16) -> u16? {
            guard let bus = bus, let cart = bus.cartridge else { return nil }
            let mapping = bus.effectiveCartridgeMapping()
            return bus.readVector16(cart, mapping: mapping, addr: addr)
        }

        @inline(__always) func fetchVector(_ vectorAddr: u16) -> u16 {
            if let v = fetchVectorViaBus(vectorAddr) { return v }

            // Fallback: direct memory reads with a bank $80 mirror probe.
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

        // Choose a program bank for the interrupt vector entry point. On real hardware the vector table
        // is in bank $00, but depending on Bus mapping/physical mirroring, ROM code may be physically visible
        // through the $80 mirror. Prefer $80 when the entry bytes there look sane.
        @inline(__always) func entryLooksSane(_ b0: u8, _ b1: u8, _ b2: u8, _ b3: u8) -> Bool {
            if b0 == 0xFF { return false }
            switch b0 {
            case 0x00, 0x02, 0x40, 0x60, 0x6B, 0xCB, 0xDB, 0x82, 0x42:
                return false
            default:
                break
            }
            if b0 == b1 && b1 == b2 && b2 == b3 {
                if b0 == 0x00 || b0 == 0x20 || b0 == 0xFF { return false }
            }
            return true
        }

        // If the vector is obviously bogus, don't jump into low WRAM/open-bus space.
        if vec == 0xFFFF || vec < 0x8000 {
            // Keep the CPU in a safe ROM-ish region; this avoids BRK/RTI loops when vectors are mis-mapped.
            vec = 0x8000
        }

        var chosenPB: u8 = 0x00
        if let bus = bus {
            let b80_0 = bus.read8_physical(bank: 0x80, addr: vec)
            let b80_1 = bus.read8_physical(bank: 0x80, addr: vec &+ 1)
            let b80_2 = bus.read8_physical(bank: 0x80, addr: vec &+ 2)
            let b80_3 = bus.read8_physical(bank: 0x80, addr: vec &+ 3)

            let b00_0 = bus.read8_physical(bank: 0x00, addr: vec)
            let b00_1 = bus.read8_physical(bank: 0x00, addr: vec &+ 1)
            let b00_2 = bus.read8_physical(bank: 0x00, addr: vec &+ 2)
            let b00_3 = bus.read8_physical(bank: 0x00, addr: vec &+ 3)

            if entryLooksSane(b80_0, b80_1, b80_2, b80_3) {
                chosenPB = 0x80
            } else if entryLooksSane(b00_0, b00_1, b00_2, b00_3) {
                chosenPB = 0x00
            }
        }

        r.pb = chosenPB
        r.pc = vec
    }
    
    @inline(__always) func wai() {
        isWaiting = true
    }

    @inline(__always) func rep(_ mask: u8) {
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

    @inline(__always) func sep(_ mask: u8) {
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

    @inline(__always) func xce() {
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

        // Pre-instruction CPU state (captured at record time).
        let a: u16
        let x: u16
        let y: u16
        let sp: u16
        let dp: u16
        let db: u8
        let p: u8
        let emulationMode: Bool
        let mem8: Bool
        let index8: Bool
        let masterCycle: UInt64
    }

    private var traceBuf: [InstructionTraceEntry] = Array(
        repeating: InstructionTraceEntry(pb: 0, pc: 0, bytes: [], text: "", usedJIT: false, a: 0, x: 0, y: 0, sp: 0, dp: 0, db: 0, p: 0, emulationMode: true, mem8: true, index8: true, masterCycle: 0),
        count: 256
    )
    private var traceHead: Int = 0
    private var traceCount: Int = 0
    private var traceLast: InstructionTraceEntry?

    @inline(__always) private func resetTrace() {
        traceHead = 0
        traceCount = 0
        traceLast = nil
    }

    @inline(__always) func recordInstruction(pb: u8, pc: u16, bytes: [u8], text: String, usedJIT: Bool) {
        let cyc: UInt64 = bus?.masterCycles ?? 0
        let regs = r
        let entry = InstructionTraceEntry(
            pb: pb, pc: pc, bytes: bytes, text: text, usedJIT: usedJIT,
            a: regs.a, x: regs.x, y: regs.y, sp: regs.sp, dp: regs.dp, db: regs.db,
            p: regs.p.rawValue, emulationMode: regs.emulationMode,
            mem8: regs.p.contains(.mem8), index8: regs.p.contains(.index8),
            masterCycle: cyc
        )
        traceBuf[traceHead] = entry
        traceHead = (traceHead + 1) & (traceBuf.count - 1)
        traceCount = min(traceCount + 1, traceBuf.count)
        traceLast = entry
    }

    @inline(__always) func recordEvent(pb: u8, pc: u16, text: String, usedJIT: Bool) {
        recordInstruction(pb: pb, pc: pc, bytes: [], text: text, usedJIT: usedJIT)
    }

    var lastInstruction: InstructionTraceEntry? { traceLast }

    @inline(__always) func instructionTrace() -> [InstructionTraceEntry] {
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
