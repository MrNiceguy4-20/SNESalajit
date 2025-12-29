import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
final class DebugViewModel: ObservableObject {
    @Published private(set) var snapshot: EmulatorDebugSnapshot

    private unowned let emulatorVM: EmulatorViewModel
    private var timerCancellable: AnyCancellable?

    init(emulatorVM: EmulatorViewModel) {
        self.emulatorVM = emulatorVM
        self.snapshot = emulatorVM.makeDebugSnapshot()
        start()
    }

    deinit {
        timerCancellable?.cancel()
    }

    func refreshNow() {
        snapshot = emulatorVM.makeDebugSnapshot()
    }

    // MARK: - Save Snapshot

    func saveSnapshot() {
        let text = makeWindowFormattedDebugReport()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.nameFieldStringValue = "debug_snapshot.txt"

        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Window-Formatted Export

    func makeWindowFormattedDebugReport() -> String {
        var out: [String] = []

        out.append("==== CPU ====")
        out.append(cpuText)
        out.append("")

        out.append("==== CPU TRACE ====")
        out.append(cpuTraceText)
        out.append("")

        out.append("==== BUS / IRQ / DMA ====")
        out.append(busText)
        out.append("")

        out.append("==== IRQ / NMI TRACE ====")
        out.append(irqTraceText)
        out.append("")

        out.append("==== APU HANDSHAKE ====")
        out.append(apuHandshakeText)
        out.append("")

        out.append("==== APU/SPC700 ====")
        out.append(apuText)
        out.append("")

        out.append("==== PPU ====")
        out.append(ppuText)
        out.append("")

        out.append("==== PPU TRACE ====")
        out.append(ppuTraceText)

        return out.joined(separator: "\n")
    }

    // MARK: - Formatted Debug Sections

    var cpuText: String {
        let s = snapshot
        return """
PC  \(Hex.u24(bank: s.cpu.pb, addr: s.cpu.pc))   DB \(Hex.u8(s.cpu.db))   DP \(Hex.u16(s.cpu.dp))   SP \(Hex.u16(s.cpu.sp))
A   \(Hex.u16(s.cpu.a))   X  \(Hex.u16(s.cpu.x))   Y  \(Hex.u16(s.cpu.y))   P  \(Hex.u8(s.cpu.p))
E   \(s.cpu.emulationMode ? 1 : 0)   M \(s.cpu.mem8 ? 1 : 0)   X \(s.cpu.index8 ? 1 : 0)   NMI \(s.cpu.nmiLine ? 1 : 0)   IRQ \(s.cpu.irqLine ? 1 : 0)   JIT \(s.cpu.useJIT ? 1 : 0)
"""
    }

    var cpuTraceText: String {
        var out: [String] = []

        if let last = snapshot.cpuLastInstruction {
            let bytes = last.bytes.prefix(4).map { Hex.u8($0) }.joined(separator: " ")
            out.append("Last:  \(Hex.u24(bank: last.pb, addr: last.pc))  \(bytes)  \(last.text)")
            out.append("")
        }

        for e in snapshot.cpuTrace.suffix(200) {
            let bytes = e.bytes.prefix(4).map { Hex.u8($0) }.joined(separator: " ")
            out.append("\(Hex.u24(bank: e.pb, addr: e.pc))  \(bytes)  \(e.text)")
        }

        return out.joined(separator: "\n")
    }

    var busText: String {
        let b = snapshot.bus
        let i = b.irq

        return """
dot \(b.dot)   scanline \(b.scanline)   vblank \(b.inVBlank ? 1 : 0)   autoJoyBusy \(b.autoJoypadBusy ? 1 : 0)
NMI EN \(i.nmiEnable ? 1 : 0)  H-IRQ EN \(i.hIrqEnable ? 1 : 0)  V-IRQ EN \(i.vIrqEnable ? 1 : 0)  AutoJoy EN \(i.autoJoypadEnable ? 1 : 0)
HTIME \(i.hTime)  VTIME \(i.vTime)  NMI line \(i.nmiLine ? 1 : 0)  IRQ line \(i.irqLine ? 1 : 0)
RDNMI \(Hex.u8(i.rdnmi))  TIMEUP \(Hex.u8(i.timeup))
Reads: HVBJOY \(b.hvbjoyReadCount) last \(Hex.u8(b.lastHVBJOY))   RDNMI \(b.rdnmiReadCount) last \(Hex.u8(b.lastRDNMI))   TIMEUP \(b.timeupReadCount) last \(Hex.u8(b.lastTIMEUP))   NMITIMEN \(b.nmitimenWriteCount) last \(Hex.u8(b.lastNMITIMEN))
MDMAEN \(Hex.u8(b.mdmaEnabled))  HDMAEN \(Hex.u8(b.hdmaEnabled))  DMA stall \(b.dmaStallCycles)
AutoJoy1 \(Hex.u16(b.autoJoy1))  AutoJoy2 \(Hex.u16(b.autoJoy2))
"""
    }

    var irqTraceText: String {
        let events = snapshot.bus.irq.recentEvents
        return events.isEmpty ? "<no events>" : events.suffix(80).joined(separator: "\n")
    }

    var apuHandshakeText: String {
        let a = snapshot.spc

        func ports(_ label: String, _ p: [u8]) -> String {
            let q = p + Array(repeating: 0, count: max(0, 4 - p.count))
            return "\(label) 0:\(Hex.u8(q[0]))  1:\(Hex.u8(q[1]))  2:\(Hex.u8(q[2]))  3:\(Hex.u8(q[3]))"
        }

        var out: [String] = []
        out.append(ports("CPU→APU latched", a.cpuToApu))
        out.append(ports("CPU→APU lastWr", a.lastCpuToApuWrite))
        out.append(String(format: "PendingMask 0x%02X", Int(a.cpuToApuPendingMask)))
        out.append("")
        out.append(ports("APU→CPU latched", a.apuToCpu))
        out.append(ports("APU→CPU lastWr", a.lastApuToCpuWrite))
        out.append("")
        if a.recentPortEvents.isEmpty {
            out.append("Recent: <none>")
        } else {
            out.append("Recent:")
            for e in a.recentPortEvents.suffix(16) {
                let dir = (e.direction == .cpuToApu) ? "CPU→APU" : "APU→CPU"
                out.append("  \(dir)[\(e.port)] = \(Hex.u8(e.value))")
            }
        }
        return out.joined(separator: "\n")
    }

    var apuText: String {
        let a = snapshot.spc

        return """
A \(Hex.u8(a.spcA))  X \(Hex.u8(a.spcX))  Y \(Hex.u8(a.spcY))  SP \(Hex.u8(a.spcSP))  PC \(Hex.u16(a.spcPC))  PSW \(Hex.u8(a.spcPSW))
Halted \(a.spcHalted ? 1 : 0) (\(a.spcHaltReason))  IPL \(a.iplEnabled ? 1 : 0)  SPC JIT \(a.spcJITEnabled ? 1 : 0)
CPU→APU \(a.cpuToApu.map { Hex.u8($0) }.joined(separator: " "))
APU→CPU \(a.apuToCpu.map { Hex.u8($0) }.joined(separator: " "))
"""
    }

    var ppuText: String {
        let p = snapshot.ppu

        return """
ForcedBlank \(p.forcedBlank ? 1 : 0)  Brightness \(p.brightness)
BGMODE \(p.bgMode)  BG3 Priority \(p.bg3Priority ? 1 : 0)
TM \(Hex.u8(p.tmMain))  TS \(Hex.u8(p.tsSub))
VRAM Addr \(Hex.u16(p.vramAddr))  CGRAM Addr \(Hex.u8(p.cgramAddr))
Framebuffer \(p.framebufferWidth)x\(p.framebufferHeight)
"""
    }

    var ppuTraceText: String {
        let e = snapshot.ppu.recentTrace
        return e.isEmpty ? "<no events>" : e.suffix(120).joined(separator: "\n")
    }

    // MARK: - Timer

    func start() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 0.10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshNow()
            }
    }
}
