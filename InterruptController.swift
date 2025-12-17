import Foundation

/// Owns NMI/IRQ state and the CPU-visible flags (RDNMI/TIMEUP).
final class InterruptController {
    // $4200 NMITIMEN bits
    var nmiEnable: Bool = false
    var hvIrqEnable: Bool = false
    var autoJoypadEnable: Bool = false

    // $4207-420A
    var hTime: Int = 0       // 9-bit (0..511)
    var vTime: Int = 0       // 9-bit (0..511)

    // CPU-visible flags
    private(set) var rdnmi: u8 = 0x00   // $4210 bit7 = NMI occurred; bit0 = version/unused
    private(set) var timeup: u8 = 0x00  // $4211 bit7 = IRQ occurred

    // Lines to CPU
    private(set) var nmiLine: Bool = false
    private(set) var irqLine: Bool = false

    // Edge tracking
    private var nmiLatchedThisVBlank: Bool = false

    func reset() {
        nmiEnable = false
        hvIrqEnable = false
        autoJoypadEnable = false
        hTime = 0
        vTime = 0
        rdnmi = 0x00
        timeup = 0x00
        nmiLine = false
        irqLine = false
        nmiLatchedThisVBlank = false
    }

    func onEnterVBlank() {
        // Latch NMI event at start of vblank if enabled.
        if nmiEnable && !nmiLatchedThisVBlank {
            rdnmi |= 0x80
            nmiLine = true
            nmiLatchedThisVBlank = true
        }
    }

    func onLeaveVBlank() {
        // Drop line; clear per-vblank latch.
        nmiLine = false
        nmiLatchedThisVBlank = false
    }

    func pollHVMatch(dot: Int, scanline: Int) {
        // H/V IRQ compare: when scanline == vTime and dot == hTime, assert IRQ if enabled.
        guard hvIrqEnable else { return }
        if scanline == vTime && dot == hTime {
            timeup |= 0x80
            irqLine = true
        }
    }

    func clearIRQLine() {
        irqLine = false
    }

    // MARK: - MMIO reads

    func readRDNMI() -> u8 {
        // Reading $4210 clears bit7 (NMI flag) and drops NMI line.
        let v = rdnmi
        rdnmi &= 0x7F
        nmiLine = false
        return v
    }

    func readTIMEUP() -> u8 {
        // Reading $4211 clears bit7 (IRQ flag) and drops IRQ line.
        let v = timeup
        timeup &= 0x7F
        irqLine = false
        return v
    }
}
