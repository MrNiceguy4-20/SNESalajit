import Foundation
import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class EmulatorViewModel: ObservableObject {
    @Published var framebuffer = Framebuffer(width: 256, height: 224)
    @Published var isRunning: Bool = false
    @Published var debugLines: [String] = []
    @Published var logLevel: LogLevel = .info
    
    private var emulator = Emulator()
    
    private var timer: Timer?
    private var frameCounter: Int = 0
    private var lastFrameLogTime: CFTimeInterval = 0
    private var lastFrameTime: CFTimeInterval = 0
    
    init() {
        globalLogHandler = { [weak self] message, level in
            self?.log(message, level: level)
        }
    }

    // MARK: - Debug window

    func openDebugWindow() {
        DebugWindowController.shared.open(with: self)
    }

    func makeDebugSnapshot() -> EmulatorDebugSnapshot {
        let cpu = emulator.cpu
        let bus = emulator.bus
        let ppu = emulator.ppu
        let apu = emulator.apu
        
        return EmulatorDebugSnapshot(
            wallClock: Date(),
            isRunning: isRunning,
            cpu: CPU65816DebugSnapshot(cpu: cpu),
            cpuLastInstruction: cpu.lastInstruction,
            cpuTrace: cpu.instructionTrace(),
            bus: bus.debugSnapshot(),
            ppu: ppu.debugSnapshot(),
            ppuFramebufferSize: (ppu.framebuffer.width, ppu.framebuffer.height),
            spc: apu.debugSnapshot(),
            recentLogs: Array(debugLines.suffix(200))
        )
    }

    func makeFullDebugReport() -> String {
        let s = makeDebugSnapshot()
        var out: [String] = []
        out.append("==== CPU ====")
        out.append("\(s.cpu)")
        out.append("")
        out.append("==== BUS / IRQ / DMA ====")
        out.append("\(s.bus)")
        out.append("")
        out.append("==== PPU ====")
        out.append("\(s.ppu)")
        out.append("")
        out.append("==== APU / SPC ====")
        out.append("\(s.spc)")
        out.append("")
        out.append("==== RECENT LOGS ====")
        out.append(contentsOf: s.recentLogs)
        return out.joined(separator: "\n")
    }

    func startIfNeeded() {
        timer?.invalidate()
        lastFrameTime = 0
        
        timer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 60.0,
            repeats: true
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.tick(inNow: CVTimeStamp(), out: CVTimeStamp())
            }
        }
        
        RunLoop.current.add(timer!, forMode: .common)
        log("Display timer started")
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    func toggleRun() {
        isRunning.toggle()
        if !isRunning { emulator.saveSRAM() }
        log("Emulator \(isRunning ? "resumed" : "paused")")
    }
    
    func reset() {
        emulator.reset()
        log("Reset emulator state")
    }
    
    func pickROM() {
        let panel = NSOpenPanel()
        
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try emulator.loadROM(url: url)
                log("Loaded ROM: \(url.lastPathComponent)")
            } catch {
                NSLog("ROM load failed: \(error)")
                log("ROM load failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func tick(inNow: CVTimeStamp, out: CVTimeStamp) {
        guard isRunning else { return }
        
        let hostTime = CFAbsoluteTimeGetCurrent()
        let dt = lastFrameTime == 0 ? (1.0 / 60.0) : (hostTime - lastFrameTime)
        lastFrameTime = hostTime
        
        let clamped = min(max(dt, 0.0), 1.0 / 15.0)
        
        emulator.step(seconds: clamped)
        
        let fb = emulator.ppu.framebuffer
        self.framebuffer = fb
        frameCounter += 1
        logFrameProgress(at: hostTime)
        
    }
    
    private func logFrameProgress(at hostTime: CFTimeInterval) {
        if lastFrameLogTime == 0 {
            lastFrameLogTime = hostTime
            return
        }

        let elapsed = hostTime - lastFrameLogTime
        guard elapsed >= 1.0 else { return }

        log(
            "UI received \(frameCounter) frame(s) in \(String(format: "%.2f", elapsed))s",
            level: .debug
        )

        frameCounter = 0
        lastFrameLogTime = hostTime
    }

    private func log(_ message: String, level: LogLevel = .info) {
        guard level >= logLevel else { return }
        
        let timestamp = DateFormatter.cached.string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue)] \(message)"
        
        debugLines.append(line)
        if debugLines.count > 200 {
            debugLines.removeFirst(debugLines.count - 200)
        }
        
        print(line)
    }
}
    

private extension DateFormatter {
    static let cached: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
