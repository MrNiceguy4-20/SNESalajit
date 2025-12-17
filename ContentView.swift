import SwiftUI

struct ContentView: View {
    @StateObject private var vm = EmulatorViewModel()

    var body: some View {
        VStack(spacing: 12) {
            MetalEmulatorView(framebuffer: vm.framebuffer)
                .frame(width: 512, height: 448) // 2x SNES 256x224
                .background(Color.black)
                .cornerRadius(12)

            HStack(spacing: 10) {
                Button(vm.isRunning ? "Stop" : "Run") {
                    vm.toggleRun()
                }
                Button("Reset") {
                    vm.reset()
                }
                Button("Load ROM…") {
                    vm.pickROM()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
        .padding(16)
        .onAppear { vm.startIfNeeded() }
    }
}
