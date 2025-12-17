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
    
    var globalLogHandler: ((String, String) -> Void)?
    private var emulator = Emulator()
    
    private var timer: Timer?
    private var lastFrameTime: CFTimeInterval = 0
    
    init() {
        globalLogHandler = { [weak self] message, level in
            self?.log(message, level: level)
        }
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
    }
    
    private func log(_ message: String, level: String = "INFO") {
        let timestamp = DateFormatter.cached.string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)"
        
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
