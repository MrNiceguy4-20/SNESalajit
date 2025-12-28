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

// If the CPU is in WAI, it must not execute any instructions until an IRQ/NMI is pending.
if cpu.isWaiting && !cpu.nmiPending && !cpu.irqLine {
    return
}
        cycleDebt += cycles

        while cycleDebt > 0 {

            // DMA: CPU is blocked while DMA engine runs (triggered by $420B).
            // Consume stall cycles before servicing interrupts or executing instructions.
            let stalled = bus.consumeDMAStall(masterCycles: cycleDebt)
            if stalled > 0 {
                cycleDebt -= stalled
                continue
            }


            // Capture instruction boundary context
            let pb = cpu.r.pb
            let pc = cpu.r.pc

            // NMI: service on rising edge of nmiLine
            if cpu.nmiLine {
                if !nmiLatched {
                    nmiLatched = true
                    cpu.recordEvent(pb: pb, pc: pc, text: "<NMI>", usedJIT: false)
                    cpu.serviceInterrupt(.nmi)
                    cycleDebt -= 7
                    continue
                }
            } else {
                nmiLatched = false
            }

            // IRQ: service if line asserted and I flag is clear
            if cpu.irqLine && !cpu.flag(.irqDis) {
                cpu.recordEvent(pb: pb, pc: pc, text: "<IRQ>", usedJIT: false)
                cpu.serviceInterrupt(.irq)
                cycleDebt -= 7
                continue
            }

            // Trace: preview up to 4 bytes at PB:PC before fetchOpcode advances PC
            let b0 = cpu.read8(pb, pc)
            let b1 = cpu.read8(pb, pc &+ 1)
            let b2 = cpu.read8(pb, pc &+ 2)
            let b3 = cpu.read8(pb, pc &+ 3)
            let preview: [u8] = [b0, b1, b2, b3]

            let opcode = cpu.fetchOpcode()

            cpu.recordInstruction(
                pb: pb,
                pc: pc,
                bytes: preview,
                text: CPUInstructionTables.mnemonic(opcode: opcode),
                usedJIT: false
            )

            let cost = CPUInstructionTables.execute(opcode: opcode, cpu: cpu, bus: bus)

            // Prevent lock-ups if an unimplemented handler accidentally returns 0.
            cycleDebt -= max(1, cost)
        }
    }
}
