import Foundation

/// JIT wrapper. Phase 5 will generate x86_64 for hot basic blocks.
/// For now, it uses CPU65816 helpers to keep register mutations encapsulated.
final class CPUJIT {
    private let execMem = JITExecutableMemory()
    private let assembler = X64Assembler()
    private var enabled: Bool = false
    private var cycleDebt: Int = 0
    private var nmiLatched: Bool = false

    func reset() {
        enabled = false
        execMem.reset()
        cycleDebt = 0
        nmiLatched = false
    }

    func step(cpu: CPU65816, bus: Bus, cycles: Int) {
        cycleDebt += cycles

        // Phase 1/2 shim: execute using the same path as the interpreter but keep the JIT
        // wrapper active so we can layer hot block compilation later.
        while cycleDebt > 0 {

            // NMI: service on rising edge of nmiLine.
            if cpu.nmiLine {
                if !nmiLatched {
                    nmiLatched = true
                    cpu.serviceInterrupt(.nmi)
                    cycleDebt -= 7
                    continue
                }
            } else {
                nmiLatched = false
            }

            // IRQ: level-sensitive and gated by I flag.
            if cpu.irqLine && !cpu.flag(.irqDis) {
                cpu.serviceInterrupt(.irq)
                cycleDebt -= 7
                continue
            }

            let opcode = cpu.fetchOpcode()
            let cost = CPUInstructionTables.execute(opcode: opcode, cpu: cpu, bus: bus)
            cycleDebt -= max(1, cost)
        }
    }
}
