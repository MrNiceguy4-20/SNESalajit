import Foundation
import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class EmulatorViewModel: ObservableObject {
    @Published var framebuffer = Framebuffer(width: 256, height: 224)
    @Published var isRunning: Bool = false

    private var emulator = Emulator()

    private var timer: Timer?
    private var lastFrameTime: CFTimeInterval = 0

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
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func toggleRun() { isRunning.toggle() }

    func reset() {
        emulator.reset()
    }

    func pickROM() {
        let panel = NSOpenPanel()
        
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try emulator.loadROM(url: url)
            } catch {
                NSLog("ROM load failed: \(error)")
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
}
