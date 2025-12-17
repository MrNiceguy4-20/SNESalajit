import Foundation

/// Interpreter loop (Phase 2).
///
/// - Decodes and executes a minimal 65C816 subset via `CPUInstructionTables`.
/// - Services NMI (edge) and IRQ (level, gated by I flag) between instructions.
/// - Uses per-opcode cycle costs and a simple cycle-debt model for deterministic stepping.
///
/// IMPORTANT: do not mutate `cpu.r` directly here; use `CPU65816` helpers.
final class CPUInterpreter {
    private var cycleDebt: Int = 0

    /// Edge latch so a level-held NMI line won't re-enter every instruction.
    private var nmiLatched: Bool = false

    func reset() {
        cycleDebt = 0
        nmiLatched = false
    }

    func step(cpu: CPU65816, bus: Bus, cycles: Int) {
        cycleDebt += cycles

        while cycleDebt > 0 {

            // NMI: service on rising edge of nmiLine (as modeled by bus/controller).
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

            // IRQ: service if line asserted and I flag is clear.
            if cpu.irqLine && !cpu.flag(.irqDis) {
                cpu.serviceInterrupt(.irq)
                cycleDebt -= 7
                continue
            }

            let opcode = cpu.fetchOpcode()
            let cost = CPUInstructionTables.execute(opcode: opcode, cpu: cpu, bus: bus)

            // Prevent lock-ups if an unimplemented handler accidentally returns 0.
            cycleDebt -= max(1, cost)
        }
    }
}
