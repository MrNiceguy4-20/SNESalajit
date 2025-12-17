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

                Picker("Log Level", selection: $vm.logLevel) {
                    ForEach(LogLevel.allCases) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            DebugConsoleView(lines: vm.debugLines)
        }
        .padding(16)
        .onAppear { vm.startIfNeeded() }
    }
}

private struct DebugConsoleView: View {
    var lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Debug Output")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(lines.indices, id: \.self) { idx in
                        Text(verbatim: lines[idx])
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
