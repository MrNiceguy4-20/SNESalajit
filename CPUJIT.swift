import Foundation

/// CPU JIT router.
///
/// Phase 13: unify interrupt-boundary semantics between interpreter and JIT.
/// For now, the 65C816 "JIT" layer is a thin wrapper that delegates to the same
/// interpreter stepping logic, so IRQ/NMI delivery and cycle-debt behavior stay
/// identical regardless of `cpu.useJIT`.
final class CPUJIT {
    private let execMem = JITExecutableMemory()
    private let assembler = X64Assembler()

    private var enabled: Bool = false

    /// Shared stepping logic (also used by the non-JIT path).
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
            // Flush any partial JIT state so re-enabling starts clean.
            execMem.reset()
            shim.reset()
        }
    }

    func step(cpu: CPU65816, bus: Bus, cycles: Int) {

// If the CPU is in WAI, it must not execute any instructions until an IRQ/NMI is pending.
if cpu.isWaiting && !cpu.nmiPending && !cpu.irqLine {
    return
}
        guard enabled else { return }

        // Phase 13: keep semantics identical to interpreter (IRQ/NMI between instructions,
        // deterministic cycle debt, and NMI edge latch).
        shim.step(cpu: cpu, bus: bus, cycles: cycles)
    }
}
