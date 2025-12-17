import Foundation

/// Owns NMI/IRQ state and the CPU-visible flags (RDNMI/TIMEUP).
final class InterruptController {
    // $4200 NMITIMEN bits
    var nmiEnable: Bool = false
    var hIrqEnable: Bool = false
    var vIrqEnable: Bool = false
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
        hIrqEnable = false
        vIrqEnable = false
        autoJoypadEnable = false
        hTime = 0
        vTime = 0
        rdnmi = 0x00
        timeup = 0x00
        nmiLine = false
        irqLine = false
        nmiLatchedThisVBlank = false
    }

    func onEnterVBlank() { latchNMIIfNeeded() }

    func onLeaveVBlank() {
        // Drop line; clear per-vblank latch.
        nmiLine = false
        nmiLatchedThisVBlank = false
    }

    func pollHVMatch(dot: Int, scanline: Int) {
        let match: Bool

        if hIrqEnable && vIrqEnable {
            match = (scanline == vTime) && (dot == hTime)
        } else if vIrqEnable {
            // V-IRQ triggers at dot 0 on the selected scanline.
            match = (scanline == vTime) && dot == 0
        } else if hIrqEnable {
            // H-IRQ triggers when dot == hTime (any scanline).
            match = (dot == hTime)
        } else {
            match = false
        }

        if match {
            timeup |= 0x80
            irqLine = true
        }
    }

    /// Write handler for $4200 NMITIMEN.
    /// If NMI is enabled while already in VBlank, the NMI flag/line must assert immediately.
    func setNMITIMEN(_ value: u8, video: VideoTiming) {
        let newNMIEnable = (value & 0x80) != 0
        if newNMIEnable && !nmiEnable && video.inVBlank {
            rdnmi |= 0x80
            nmiLine = true
            nmiLatchedThisVBlank = true
        }
        nmiEnable = newNMIEnable

        hIrqEnable = (value & 0x10) != 0
        vIrqEnable = (value & 0x20) != 0
        autoJoypadEnable = (value & 0x01) != 0
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

    // MARK: - Private helpers

    private func latchNMIIfNeeded() {
        if nmiEnable && !nmiLatchedThisVBlank {
            rdnmi |= 0x80
            nmiLine = true
            nmiLatchedThisVBlank = true
        }
    }
}
