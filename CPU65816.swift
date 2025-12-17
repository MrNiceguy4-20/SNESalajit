import Foundation

final class CPU65816 {
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

    private(set) var nmiLine: Bool = false
    private(set) var irqLine: Bool = false

    func attach(bus: Bus) { self.bus = bus }

    func reset() {
        r = Registers()
        r.emulationMode = true
        forceEmulationFlags()

        let lo = read8(0x00, 0xFFFC)
        let hi = read8(0x00, 0xFFFD)
        r.pb = 0x00
        r.pc = make16(lo, hi)

        nmiLine = false
        irqLine = false

        interpreter.reset()
        jit.reset()
    }

    func setNMI(_ asserted: Bool) { nmiLine = asserted }
    func setIRQ(_ asserted: Bool) { irqLine = asserted }

    func step(cycles: Int) {
        guard let bus else { return }
        if useJIT {
            jit.setEnabled(true)
            jit.step(cpu: self, bus: bus, cycles: cycles)
        } else {
            jit.setEnabled(false)
            interpreter.step(cpu: self, bus: bus, cycles: cycles)
        }
    }

    // MARK: - Bus access (safe wrappers)

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

    // MARK: - Fetch helpers (ONLY these should advance PC from outside this file)

    /// Read from the current program bank at PC (does not modify PC).
    @inline(__always) func peek8() -> u8 {
        read8(r.pb, r.pc)
    }

    /// Fetch byte at PB:PC and increment PC.
    @inline(__always) func fetch8() -> u8 {
        let v = read8(r.pb, r.pc)
        r.pc &+= 1
        return v
    }

    /// Fetch 16-bit little-endian value at PB:PC and increment PC by 2.
    @inline(__always) func fetch16() -> u16 {
        let lo = fetch8()
        let hi = fetch8()
        return make16(lo, hi)
    }

    /// Fetch opcode (alias of fetch8 for clarity).
    @inline(__always) func fetchOpcode() -> u8 { fetch8() }

    /// Advance PC by N bytes (used by decode paths that pre-skip operands).
    @inline(__always) func advancePC(_ count: Int) {
        r.pc &+= u16(truncatingIfNeeded: count)
    }

    // MARK: - Flag helpers

    @inline(__always) func flag(_ f: Status) -> Bool { (r.p.rawValue & f.rawValue) != 0 }

    @inline(__always) func setFlag(_ f: Status, _ on: Bool) {
        if on { r.p = Status(rawValue: r.p.rawValue | f.rawValue) }
        else  { r.p = Status(rawValue: r.p.rawValue & ~f.rawValue) }
    }

    @inline(__always) func forceEmulationFlags() {
        // In emulation mode, M and X are forced set (8-bit A and 8-bit index registers).
        r.p = Status(rawValue: r.p.rawValue | Status.mem8.rawValue | Status.index8.rawValue)
        // SP high byte forced to 0x01.
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

    // MARK: - Stack helpers

    /// Push a byte on the current stack (bank $00). Updates SP.
    func push8(_ v: u8) {
        if r.emulationMode {
            let addr = u16(0x0100) | (r.sp & 0x00FF)
            write8(0x00, addr, v)
            r.sp = (r.sp & 0xFF00) | ((r.sp &- 1) & 0x00FF)
        } else {
            write8(0x00, r.sp, v)
            r.sp &-= 1
        }
    }

    /// Pull a byte from the current stack (bank $00). Updates SP.
    func pull8() -> u8 {
        if r.emulationMode {
            r.sp = (r.sp & 0xFF00) | ((r.sp &+ 1) & 0x00FF)
            let addr = u16(0x0100) | (r.sp & 0x00FF)
            return read8(0x00, addr)
        } else {
            r.sp &+= 1
            return read8(0x00, r.sp)
        }
    }

    func push16(_ v: u16) {
        // 65xx pushes high then low.
        push8(hi8(v))
        push8(lo8(v))
    }

    func pull16() -> u16 {
        // Pull low then high (reverse of push).
        let lo = pull8()
        let hi = pull8()
        return make16(lo, hi)
    }

    // MARK: - Register mutation API (used by instruction handlers)

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

    /// Read P for pushes (forces bit5=1; in emulation, bit4 is the "B" bit when pushed for BRK/IRQ).
    @inline(__always) func pForPush(brk: Bool) -> u8 {
        var p = r.p.rawValue | 0x20
        if r.emulationMode {
            if brk { p |= 0x10 } else { p &= 0xEF }
        }
        return p
    }

    /// Set P from pulls (bit5 ignored/forced to 1; in emulation mode also force M/X set).
    @inline(__always) func setPFromPull(_ v: u8) {
        r.p = Status(rawValue: v | 0x20)
        if r.emulationMode { forceEmulationFlags() }
    }

    // MARK: - Interrupt entry (Phase 1 minimal)

    enum InterruptKind { case nmi, irq, brk }

    func serviceInterrupt(_ kind: InterruptKind) {
        // For Phase 1 we implement emulation-style vectors; native mode also uses bank 0 vectors.
        // Push return address and status.
        // On 65C816, in emulation mode, pushes PC (hi, lo) then P.
        push8(hi8(r.pc))
        push8(lo8(r.pc))
        push8(pForPush(brk: kind == .brk))

        setFlag(.irqDis, true)

        let vectorAddr: u16
        switch kind {
        case .nmi: vectorAddr = 0xFFFA
        case .irq, .brk: vectorAddr = 0xFFFE
        }
        let lo = read8(0x00, vectorAddr)
        let hi = read8(0x00, vectorAddr &+ 1)
        r.pb = 0x00
        r.pc = make16(lo, hi)
    }

    // MARK: - REP/SEP and XCE

    func rep(_ mask: u8) {
        r.p = Status(rawValue: r.p.rawValue & ~mask)
        if r.emulationMode { forceEmulationFlags() }
        // If switching to 8-bit index, truncate X/Y.
        if xIs8() {
            r.x = u16(u8(truncatingIfNeeded: r.x))
            r.y = u16(u8(truncatingIfNeeded: r.y))
        }
        // If switching to 8-bit A, truncate A.
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
        // Exchange carry and emulation mode flag.
        let c = flag(.carry)
        let e = r.emulationMode
        r.emulationMode = c
        setFlag(.carry, e)
        if r.emulationMode { forceEmulationFlags() }
    }
}
