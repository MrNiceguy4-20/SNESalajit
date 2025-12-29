import SwiftUI

struct DebugWindow: View {
    @ObservedObject var debugVM: DebugViewModel

    var body: some View {
        let s = debugVM.snapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(s.wallClock, style: .time)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)
                Text("running=\(s.isRunning ? 1 : 0)")
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Refresh") { debugVM.refreshNow() }
                Button("Save Snapshot…") { debugVM.saveSnapshot() }
            }

            TabView {
                StateTab(snapshot: s)
                    .tabItem { Text("State") }
                LogsTab(logs: s.recentLogs)
                    .tabItem { Text("Logs") }
            }
        }
        .padding(12)
        .frame(minWidth: 820, minHeight: 620)
    }
}

private struct StateTab: View {
    let snapshot: EmulatorDebugSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("CPU") {
                    Text(cpuText)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("CPU Trace") {
                    Text(cpuTraceText)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Bus / IRQ / DMA") {
                    Text(busText)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                
                
                
                GroupBox("IRQ / NMI Trace") {
                    Text(irqTraceText)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

GroupBox("APU Handshake") {
                    Text(apuHandshakeText)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

GroupBox("APU / SPC700") {
                    Text(apuText)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("PPU") {
                    Text(ppuText)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("PPU Trace") {
                    Text(ppuTraceText)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }

    private var cpuText: String {
        let c = snapshot.cpu
        return [
            "PC  \(Hex.u24(bank: c.pb, addr: c.pc))   DB \(Hex.u8(c.db))   DP \(Hex.u16(c.dp))   SP \(Hex.u16(c.sp))",
            "A   \(Hex.u16(c.a))   X  \(Hex.u16(c.x))   Y  \(Hex.u16(c.y))   P  \(Hex.u8(c.p))",
            "E   \(c.emulationMode ? 1 : 0)   M \(c.mem8 ? 1 : 0)   X \(c.index8 ? 1 : 0)   NMI \(c.nmiLine ? 1 : 0)   IRQ \(c.irqLine ? 1 : 0)   JIT \(c.useJIT ? 1 : 0)"
        ].joined(separator: "\n")
    }

    private var cpuTraceText: String {
        let last = snapshot.cpuLastInstruction
        let trace = snapshot.cpuTrace

        func fmtBytes(_ bytes: [u8]) -> String {
            if bytes.isEmpty { return "" }
            return bytes.prefix(4).map { Hex.u8($0) }.joined(separator: " ")
        }

        var lines: [String] = []

        if let last {
            lines.append("Last:  \(Hex.u24(bank: last.pb, addr: last.pc))  \(fmtBytes(last.bytes))  \(last.text)  \(last.usedJIT ? "[JIT]" : "")")
            lines.append("")
        } else {
            lines.append("Last: <none>")
            lines.append("")
        }

        if trace.isEmpty {
            lines.append("<trace empty>")
            return lines.joined(separator: "\n")
        }

        let tail = trace.suffix(200)
        for e in tail {
            lines.append("\(Hex.u24(bank: e.pb, addr: e.pc))  \(fmtBytes(e.bytes))  \(e.text)")
        }
        return lines.joined(separator: "\n")
    }

    private var busText: String {
        let b = snapshot.bus
        let i = b.irq

        let lines: [String] = [
            "dot \(b.dot)   scanline \(b.scanline)   vblank \(b.inVBlank ? 1 : 0)   autoJoyBusy \(b.autoJoypadBusy ? 1 : 0)",
            "NMI EN \(i.nmiEnable ? 1 : 0)  H-IRQ EN \(i.hIrqEnable ? 1 : 0)  V-IRQ EN \(i.vIrqEnable ? 1 : 0)  AutoJoy EN \(i.autoJoypadEnable ? 1 : 0)",
            "HTIME \(i.hTime)  VTIME \(i.vTime)  NMI line \(i.nmiLine ? 1 : 0)  IRQ line \(i.irqLine ? 1 : 0)",
            "RDNMI \(Hex.u8(i.rdnmi))  TIMEUP \(Hex.u8(i.timeup))",
            "Reads: HVBJOY \(b.hvbjoyReadCount) last \(Hex.u8(b.lastHVBJOY))  RDNMI \(b.rdnmiReadCount)  TIMEUP \(b.timeupReadCount)  Writes: NMITIMEN \(b.nmitimenWriteCount) last \(Hex.u8(b.lastNMITIMEN))",
            "MDMAEN \(Hex.u8(b.mdmaEnabled))  HDMAEN \(Hex.u8(b.hdmaEnabled))  DMA stall \(b.dmaStallCycles)",
            "AutoJoy1 \(Hex.u16(b.autoJoy1))  AutoJoy2 \(Hex.u16(b.autoJoy2))"
        ]
        return lines.joined(separator: "\n")
    }

    
    private var irqTraceText: String {
        let e = snapshot.bus.irq.recentEvents
        if e.isEmpty { return "<no events yet>" }
        return e.suffix(80).joined(separator: "\n")
    }

private var apuHandshakeText: String {
        let a = snapshot.spc

        func portsLine(_ label: String, _ ports: [u8]) -> String {
            let p = ports + Array(repeating: 0, count: max(0, 4 - ports.count))
            return "\(label) 0:\(Hex.u8(p[0]))  1:\(Hex.u8(p[1]))  2:\(Hex.u8(p[2]))  3:\(Hex.u8(p[3]))"
        }

        let pending = String(format: "PendingMask 0x%02X", Int(a.cpuToApuPendingMask))

        var lines: [String] = []
        lines.append(portsLine("CPU→APU latched", a.cpuToApu))
        lines.append(portsLine("CPU→APU lastWr", a.lastCpuToApuWrite))
        lines.append(pending)
        lines.append("")
        lines.append(portsLine("APU→CPU latched", a.apuToCpu))
        lines.append(portsLine("APU→CPU lastWr", a.lastApuToCpuWrite))
        lines.append("")
        if a.recentPortEvents.isEmpty {
            lines.append("Recent: <none>")
        } else {
            lines.append("Recent:")
            for e in a.recentPortEvents.suffix(16) {
                let dir = (e.direction == .cpuToApu) ? "CPU→APU" : "APU→CPU"
                lines.append("  \(dir)[\(e.port)] = \(Hex.u8(e.value))")
            }
        }
        return lines.joined(separator: "\n")
    }


    private var apuText: String {
        let a = snapshot.spc
        return [
            "A \(Hex.u8(a.spcA))  X \(Hex.u8(a.spcX))  Y \(Hex.u8(a.spcY))  SP \(Hex.u8(a.spcSP))  PC \(Hex.u16(a.spcPC))  PSW \(Hex.u8(a.spcPSW))",
            "Halted \(a.spcHalted ? 1 : 0) (\(a.spcHaltReason))  IPL \(a.iplEnabled ? 1 : 0)  SPC JIT \(a.spcJITEnabled ? 1 : 0)",
            "CPU→APU \(a.cpuToApu.map { Hex.u8($0) }.joined(separator: " "))",
            "APU→CPU \(a.apuToCpu.map { Hex.u8($0) }.joined(separator: " "))"
        ].joined(separator: "\n")
    }

    private var ppuText: String {
        let p = snapshot.ppu
        return [
            "ForcedBlank \(p.forcedBlank ? 1 : 0)  Brightness \(p.brightness)",
            "BGMODE \(p.bgMode)  BG3 Priority \(p.bg3Priority ? 1 : 0)",
            "TM \(Hex.u8(p.tmMain))  TS \(Hex.u8(p.tsSub))",
            "VRAM Addr \(Hex.u16(p.vramAddr))  CGRAM Addr \(Hex.u8(p.cgramAddr))",
            "Framebuffer \(p.framebufferWidth)x\(p.framebufferHeight)"
        ].joined(separator: "\n")
    }

    private var ppuTraceText: String {
        let e = snapshot.ppu.recentTrace
        if e.isEmpty { return "<no events yet>" }
        return e.suffix(120).joined(separator: "\n")
    }

}

private struct LogsTab: View {
    let logs: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(logs.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 8)
        }
    }
}
