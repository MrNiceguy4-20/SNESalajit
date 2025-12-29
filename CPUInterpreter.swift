import Foundation

final class CPUInterpreter {
    private var cycleDebt: Int = 0
    private var nmiLatched: Bool = false

    func reset() {
        cycleDebt = 0
        nmiLatched = false
    }

    func step(cpu: CPU65816, bus: Bus, cycles: Int) {
        if cpu.isWaiting && !cpu.nmiPending && !cpu.irqLine {
            return
        }

        cycleDebt += cycles

        while cycleDebt > 0 {
            let stalled = bus.consumeDMAStall(masterCycles: cycleDebt)
            if stalled > 0 {
                cycleDebt -= stalled
                continue
            }

            let pb = cpu.r.pb
            let pc = cpu.r.pc

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

            if cpu.irqLine && !cpu.flag(.irqDis) {
                cpu.recordEvent(pb: pb, pc: pc, text: "<IRQ>", usedJIT: false)
                cpu.serviceInterrupt(.irq)
                cycleDebt -= 7
                continue
            }

            let b0 = cpu.read8(pb, pc)
            let b1 = cpu.read8(pb, pc &+ 1)
            let b2 = cpu.read8(pb, pc &+ 2)
            let b3 = cpu.read8(pb, pc &+ 3)
            let preview: [UInt8] = [b0, b1, b2, b3]

            let opcode = cpu.fetchOpcode()

            cpu.recordInstruction(
                pb: pb,
                pc: pc,
                bytes: preview,
                text: CPUInstructionTables.mnemonic(opcode: opcode),
                usedJIT: false
            )

            let cost = CPUInstructionTables.execute(opcode: opcode, cpu: cpu, bus: bus)

            cycleDebt -= max(1, cost)
        }
    }
}
