import AppKit
import SwiftUI

@MainActor
final class DebugWindowController: NSObject {
    static let shared = DebugWindowController()

    private var window: NSWindow?

    @inline(__always) func open(with vm: EmulatorViewModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let debugVM = DebugViewModel(emulatorVM: vm)
        let root = DebugWindow(debugVM: debugVM)
        let hosting = NSHostingController(rootView: root)

        let w = NSWindow(contentViewController: hosting)
        w.title = "SNES Debug"
        w.setContentSize(NSSize(width: 920, height: 700))
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.isReleasedWhenClosed = false
        w.center()

        w.delegate = self
        self.window = w

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension DebugWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
