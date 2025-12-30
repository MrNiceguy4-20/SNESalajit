import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
final class DebugViewModel: ObservableObject {
    @Published private(set) var snapshot: EmulatorDebugSnapshot
    @Published private(set) var diffText: String = ""
    private var previousSnapshot: EmulatorDebugSnapshot? = nil

    private unowned let emulatorVM: EmulatorViewModel
    private var timerCancellable: AnyCancellable?

    init(emulatorVM: EmulatorViewModel) {
        self.emulatorVM = emulatorVM
        self.snapshot = emulatorVM.makeDebugSnapshot()
        self.previousSnapshot = self.snapshot
        self.diffText = "<no previous snapshot>"
        start()
    }

    deinit {
        timerCancellable?.cancel()
    }

    @inline(__always) func refreshNow() {
        snapshot = emulatorVM.makeDebugSnapshot()
    }

    private static func computeDiff(prev: EmulatorDebugSnapshot, now: EmulatorDebugSnapshot) -> String {
        var out: [String] = []

        // CPU diffs
        let a = prev.cpu, b = now.cpu
        if a.a != b.a || a.x != b.x || a.y != b.y || a.sp != b.sp || a.dp != b.dp || a.db != b.db || a.pb != b.pb || a.pc != b.pc || a.p != b.p {
            out.append("CPU: A \(Hex.u16(a.a))→\(Hex.u16(b.a))  X \(Hex.u16(a.x))→\(Hex.u16(b.x))  Y \(Hex.u16(a.y))→\(Hex.u16(b.y))")
            out.append("     PB:PC \(Hex.u24(bank: a.pb, addr: a.pc))→\(Hex.u24(bank: b.pb, addr: b.pc))  SP \(Hex.u16(a.sp))→\(Hex.u16(b.sp))  DP \(Hex.u16(a.dp))→\(Hex.u16(b.dp))  DB \(Hex.u8(a.db))→\(Hex.u8(b.db))  P \(Hex.u8(a.p))→\(Hex.u8(b.p))")
        }

        // IRQ/NMI line changes
        if prev.bus.nmiLine != now.bus.nmiLine || prev.bus.irqLine != now.bus.irqLine {
            out.append("Lines: NMI \(prev.bus.nmiLine)→\(now.bus.nmiLine)  IRQ \(prev.bus.irqLine)→\(now.bus.irqLine)")
        }

        // DMA enable changes
        if prev.bus.mdmaEnabled != now.bus.mdmaEnabled || prev.bus.hdmaEnabled != now.bus.hdmaEnabled {
            out.append("DMA: MDMAEN \(Hex.u8(prev.bus.mdmaEnabled))→\(Hex.u8(now.bus.mdmaEnabled))  HDMAEN \(Hex.u8(prev.bus.hdmaEnabled))→\(Hex.u8(now.bus.hdmaEnabled))")
        }

        // Fault changes
        let pf = prev.bus.lastFault?.message
        let nf = now.bus.lastFault?.message
        if pf != nf, let nf {
            out.append("Fault: \(nf)")
        }

        return out.isEmpty ? "<no changes detected>" : out.joined(separator: "\n")
    }

    // MARK: - Save Snapshot

    @inline(__always) func saveSnapshot() {
        let text = makeWindowFormattedDebugReport()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.nameFieldStringValue = "debug_snapshot.txt"

        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Window-Formatted Export

    @inline(__always)     func makeWindowFormattedDebugReport() -> String {
        var out: [String] = []

        out.append("==== REPRO / CONTEXT ====")
        out.append(reproHeaderText)
        out.append("")
        out.append("==== CHANGES SINCE LAST REFRESH ====")
        out.append(diffText)
        out.append("")
        out.append("==== LAST FAULT ====")
        out.append(faultText)
        out.append("")

        out.append("==== CPU ====")
        out.append(cpuText)
        out.append("")

        out.append("==== CPU TRACE (WITH REGS) ====")
        out.append(cpuTraceText)
        out.append("")

        out.append("==== BUS / IRQ / DMA ====")
        out.append(busText)
        out.append("")

        out.append("==== BUS TRANSACTIONS (LAST 200) ====")
        out.append(busTransactionsText)
        out.append("")

        out.append("==== IO WRITE HISTORY (PPU/IRQ/DMA/APU) ====")
        out.append(ioWriteHistoryText)
        out.append("")

        out.append("==== IRQ / NMI TRACE ====")
        out.append(irqTraceText)
        out.append("")

        out.append("==== APU / SPC ====")
        out.append(apuText)
        out.append("")

        out.append("==== APU HANDSHAKE ====")
        out.append(apuHandshakeText)
        out.append("")

        out.append("==== PPU ====")
        out.append(ppuText)
        out.append("")

        out.append("==== PPU TRACE ====")
        out.append(ppuTraceText)
        out.append("")

        out.append("==== RECENT LOGS ====")
        out.append(logsText)

        return out.joined(separator: "\n")


    }

    // MARK: - Formatted Debug Sections

    var logsText: String {
        let lines = snapshot.logs
        return lines.isEmpty ? "<none>" : lines.joined(separator: "\n")
    }
    
    var reproHeaderText: String {
        let s = snapshot
        let b = s.bus
        var out: [String] = []
        out.append("WallClock: \(s.wallClock)")
        out.append("Running: \(s.isRunning)")
        if let name = s.romName { out.append("ROM: \(name)") }
        if let sha1 = s.romSHA1 { out.append("SHA1: \(sha1)") }
        out.append("Cartridge mapping: \(String(describing: b.cartridgeMapping))")
        if let ov = b.vectorMappingOverride {
            out.append("Vector mapping override: \(String(describing: ov))")
        }
        out.append("MasterCycles: \(b.masterCycleCounter)")
        return out.joined(separator: "\n")
    }

    var faultText: String {
        guard let f = snapshot.bus.lastFault else { return "<none>" }
        var out: [String] = []
        out.append("\(f.component): \(f.message)")
        if let pc = f.pc24 {
            out.append("PC: \(String(format: "$%06X", pc))")
        }
        if let c = f.masterCycle {
            out.append("MasterCycle: \(c)")
        }
        if let sl = f.scanline, let dot = f.dot {
            out.append("Video: scanline \(sl) dot \(dot)")
        }
        out.append("At: \(f.wallClock)")
        return out.joined(separator: "\n")
    }

    var busTransactionsText: String {
        let tx = snapshot.bus.transactions
        if tx.isEmpty { return "<none>" }
        var out: [String] = []
        for t in tx.suffix(200) {
            let pc = t.cpuPC24.map { String(format: "$%06X", $0) } ?? "------"
            let rw = t.isWrite ? "W" : "R"
            out.append(String(format: "%10llu  %3d:%3d  %@ %@  %02X:%04X = %02X  PC %@",
                              t.masterCycle, t.scanline, t.dot,
                              t.source.rawValue, rw,
                              t.bank, t.addr, t.value, pc))
        }
        return out.joined(separator: "\n")
    }

    var ioWriteHistoryText: String {
        let tx = snapshot.bus.transactions.filter { $0.isWrite }
        if tx.isEmpty { return "<none>" }
        func isPPU(_ a: u16) -> Bool { a >= 0x2100 && a <= 0x21FF }
        func isIRQ(_ a: u16) -> Bool { a >= 0x4200 && a <= 0x421F }
        func isDMA(_ a: u16) -> Bool { a >= 0x4300 && a <= 0x437F }
        func isAPU(_ a: u16) -> Bool { a >= 0x2140 && a <= 0x2143 }

        let ppu = tx.filter { $0.bank == 0x00 && isPPU($0.addr) }.suffix(64)
        let irq = tx.filter { $0.bank == 0x00 && isIRQ($0.addr) }.suffix(64)
        let dma = tx.filter { $0.bank == 0x00 && isDMA($0.addr) }.suffix(64)
        let apu = tx.filter { $0.bank == 0x00 && isAPU($0.addr) }.suffix(64)

        var out: [String] = []
        func emit(_ title: String, _ list: ArraySlice<Bus.BusTransaction>) {
            out.append("-- \(title) --")
            if list.isEmpty { out.append("<none>"); return }
            for t in list {
                let pc = t.cpuPC24.map { String(format: "$%06X", $0) } ?? "------"
                out.append(String(format: "%10llu  %@  %02X:%04X = %02X  PC %@",
                                  t.masterCycle, t.source.rawValue, t.bank, t.addr, t.value, pc))
            }
        }
        emit("PPU $2100-$21FF", ppu)
        out.append("")
        emit("IRQ/TIMING $4200-$421F", irq)
        out.append("")
        emit("DMA $4300-$437F", dma)
        out.append("")
        emit("APU PORTS $2140-$2143", apu)
        return out.joined(separator: "\n")
    }

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
            out.append(String(format: "%@  %@  %@  | A=%@ X=%@ Y=%@ SP=%@ DP=%@ DB=%@ P=%@ E=%@ M=%@ X=%@  cyc=%llu",
                              Hex.u24(bank: e.pb, addr: e.pc),
                              bytes,
                              e.text,
                              Hex.u16(e.a), Hex.u16(e.x), Hex.u16(e.y), Hex.u16(e.sp), Hex.u16(e.dp), Hex.u8(e.db), Hex.u8(e.p),
                              e.emulationMode ? "1" : "0", e.mem8 ? "1" : "0", e.index8 ? "1" : "0",
                              e.masterCycle))
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

    @inline(__always) func start() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 0.10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshNow()
            }
    }
}
