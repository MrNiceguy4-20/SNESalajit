import Foundation

final class CPUJIT {
    private let execMem = JITExecutableMemory()
    private let assembler = X64Assembler()

    private var enabled: Bool = false

    private let shim = CPUInterpreter()

    func reset() {
        enabled = false
        execMem.reset()
        shim.reset()
    }

    func setEnabled(_ flag: Bool) {
        if enabled == flag { return }
        enabled = flag

        if !flag {
            execMem.reset()
            shim.reset()
        }
    }

    func step(cpu: CPU65816, bus: Bus, cycles: Int) {
        if cpu.isWaiting && !cpu.nmiPending && !cpu.irqLine {
            return
        }
        
        guard enabled else { return }

        shim.step(cpu: cpu, bus: bus, cycles: cycles)
    }
}
