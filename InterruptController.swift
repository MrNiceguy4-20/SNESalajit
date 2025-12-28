import Foundation

/// Owns NMI/IRQ state and the CPU-visible flags (RDNMI/TIMEUP), plus a small rolling trace log.
final class InterruptController {
    // $4200 NMITIMEN bits
    private(set) var nmiEnable: Bool = false
    private(set) var hIrqEnable: Bool = false
    private(set) var vIrqEnable: Bool = false
    private(set) var autoJoypadEnable: Bool = false

    private(set) var nmitimen: u8 = 0

    // $4207-420A
    var hTime: Int = 0       // 9-bit (0..511)
    var vTime: Int = 0       // 9-bit (0..511)

    // CPU-visible flags
    // $4210: bit7 = NMI occurred. Set at the start of VBlank even if NMI is disabled in $4200.
    // bits0-3 contain a CPU version nibble (commonly reads as 0x2).
    private(set) var rdnmi: u8 = 0x02
    // $4211: bit7 = IRQ occurred.
    private(set) var timeup: u8 = 0x00

    // Lines to CPU
    private(set) var nmiLine: Bool = false
    private(set) var irqLine: Bool = false

    // Edge tracking
    private var nmiLatchedThisVBlank: Bool = false

    // Rolling trace
    private var recentEvents: [String] = []
    private let maxRecentEvents: Int = 200

    func reset() {
        nmiEnable = false
        hIrqEnable = false
        vIrqEnable = false
        autoJoypadEnable = false

        hTime = 0
        vTime = 0

        // Preserve the version nibble on reset.
        rdnmi = 0x02
        timeup = 0x00

        nmiLine = false
        irqLine = false
        nmiLatchedThisVBlank = false

        recentEvents.removeAll(keepingCapacity: true)
        pushEvent("[SL:0 DOT:0] [reset] NMI/HV/AutoJoy cleared")
    }

    // MARK: - Timing hooks (called by Bus/VideoTiming)

    func onEnterVBlank(dot: Int, scanline: Int) {
        rdnmi |= 0x80
        pushEvent(dot: dot, scanline: scanline, "VBlank enter → RDNMI bit7 set (RDNMI=\(hex8(rdnmi)))")

        if nmiEnable {
            nmiLine = true
            nmiLatchedThisVBlank = true
            pushEvent(dot: dot, scanline: scanline, "NMI line ↑ (enabled)")
        }
    }

    func onLeaveVBlank(dot: Int, scanline: Int) {
        if nmiLine {
            pushEvent(dot: dot, scanline: scanline, "NMI line ↓ (VBlank leave)")
        }
        nmiLatchedThisVBlank = false
        pushEvent(dot: dot, scanline: scanline, "VBlank leave")
    }

    func pollHVMatch(dot: Int, scanline: Int) {
        let match: Bool

        if hIrqEnable && vIrqEnable {
            match = (scanline == vTime) && (dot == hTime)
        } else if vIrqEnable {
            match = (scanline == vTime) && dot == 0
        } else if hIrqEnable {
            match = (dot == hTime)
        } else {
            match = false
        }

        if match {
            timeup |= 0x80
            if !irqLine {
                pushEvent(dot: dot, scanline: scanline, "IRQ match → TIMEUP bit7 set (TIMEUP=\(hex8(timeup)))")
            }
            irqLine = true
        }
    }

    // MARK: - $4200 NMITIMEN

    /// Write handler for $4200 NMITIMEN.
    /// If NMI is enabled while already in VBlank, the NMI flag/line must assert immediately.
    func setNMITIMEN(_ value: u8, video: VideoTiming, dot: Int, scanline: Int) {
        nmitimen = value
        let newNMIEnable = (value & 0x80) != 0
            let newVIRQEnable = (value & 0x20) != 0
            let newHIRQEnable = (value & 0x10) != 0
            let newAutoJoyEnable = (value & 0x01) != 0

        if newNMIEnable != nmiEnable {
            pushEvent(dot: dot, scanline: scanline, "NMI EN \(newNMIEnable ? 1 : 0)  (write $4200=\(hex8(value)))")
        }
        if newHIRQEnable != hIrqEnable {
            pushEvent(dot: dot, scanline: scanline, "H-IRQ EN \(newHIRQEnable ? 1 : 0)  (write $4200=\(hex8(value)))")
        }
        if newVIRQEnable != vIrqEnable {
            pushEvent(dot: dot, scanline: scanline, "V-IRQ EN \(newVIRQEnable ? 1 : 0)  (write $4200=\(hex8(value)))")
        }
        if newAutoJoyEnable != autoJoypadEnable {
            pushEvent(dot: dot, scanline: scanline, "AutoJoy EN \(newAutoJoyEnable ? 1 : 0)  (write $4200=\(hex8(value)))")
        }

        // If enabling NMI while we're already in VBlank and the VBlank edge has already happened,
        // hardware asserts NMI immediately.
        if newNMIEnable && !nmiEnable && video.inVBlank {
            rdnmi |= 0x80
            nmiLine = true
            nmiLatchedThisVBlank = true
            pushEvent(dot: dot, scanline: scanline, "Enable NMI during VBlank → NMI line ↑, RDNMI bit7 set")
        }

        nmiEnable = newNMIEnable
            vIrqEnable = newVIRQEnable
            hIrqEnable = newHIRQEnable
            autoJoypadEnable = newAutoJoyEnable
    }

    func reapplyLatchedNMITIMEN(dot: Int, scanline: Int) {
        let value = nmitimen
        nmiEnable = (value & 0x80) != 0
        vIrqEnable = (value & 0x20) != 0
        hIrqEnable = (value & 0x10) != 0
        autoJoypadEnable = (value & 0x01) != 0
    }
    
    func clearIRQLine(dot: Int, scanline: Int) {
        if irqLine {
            pushEvent(dot: dot, scanline: scanline, "IRQ line ↓ (manual clear)")
        }
        irqLine = false
    }

    // MARK: - MMIO reads

    func readRDNMI(dot: Int, scanline: Int) -> u8 {
        let v = rdnmi
        rdnmi &= 0x7F
        if (v & 0x80) != 0 {
            pushEvent(dot: dot, scanline: scanline, "RDNMI read → \(hex8(v)) (clears bit7, NMI line ↓)")
        } else {
            pushEvent(dot: dot, scanline: scanline, "RDNMI read → \(hex8(v))")
        }
        nmiLine = false
        return v
    }

    func readTIMEUP(dot: Int, scanline: Int) -> u8 {
        let v = timeup
        timeup &= 0x7F
        if (v & 0x80) != 0 {
            pushEvent(dot: dot, scanline: scanline, "TIMEUP read → \(hex8(v)) (clears bit7, IRQ line ↓)")
        } else {
            pushEvent(dot: dot, scanline: scanline, "TIMEUP read → \(hex8(v))")
        }
        irqLine = false
        return v
    }

    func logHVBJOYRead(value: u8, dot: Int, scanline: Int) {
        pushEvent(dot: dot, scanline: scanline, "HVBJOY read → \(hex8(value))")
    }

    // MARK: - Debug

    struct InterruptDebugState {
        let nmiEnable: Bool
        let hIrqEnable: Bool
        let vIrqEnable: Bool
        let autoJoypadEnable: Bool

        let hTime: Int
        let vTime: Int

        let rdnmi: u8
        let timeup: u8

        let nmiLine: Bool
        let irqLine: Bool

        let recentEvents: [String]
    }

    func debugSnapshot() -> InterruptDebugState {
        InterruptDebugState(
            nmiEnable: nmiEnable,
            hIrqEnable: hIrqEnable,
            vIrqEnable: vIrqEnable,
            autoJoypadEnable: autoJoypadEnable,
            hTime: hTime,
            vTime: vTime,
            rdnmi: rdnmi,
            timeup: timeup,
            nmiLine: nmiLine,
            irqLine: irqLine,
            recentEvents: recentEvents
        )
    }

    // MARK: - Trace helpers

    private func pushEvent(dot: Int, scanline: Int, _ message: String) {
        pushEvent("[SL:\(scanline) DOT:\(dot)] \(message)")
    }

    private func pushEvent(_ message: String) {
        recentEvents.append(message)
        if recentEvents.count > maxRecentEvents {
            recentEvents.removeFirst(recentEvents.count - maxRecentEvents)
        }
    }

    private func hex8(_ v: u8) -> String {
        String(format: "$%02X", Int(v))
    }
}
