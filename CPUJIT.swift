import Foundation

/// JIT wrapper. Phase 5 will generate x86_64 for hot basic blocks.
/// For now, it uses CPU65816 helpers to keep register mutations encapsulated.
final class CPUJIT {
    private let execMem = JITExecutableMemory()
    private let assembler = X64Assembler()
    private var enabled: Bool = false

    func reset() {
        enabled = false
        execMem.reset()
    }

    func step(cpu: CPU65816, bus: Bus, cycles: Int) {
        _ = bus
        // Phase 0/1/2: no actual JIT yet.
        var debt = cycles
        while debt > 0 {
            let opcode = cpu.fetchOpcode()
            _ = opcode
            debt -= 2
        }
    }
}
