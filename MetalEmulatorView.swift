import SwiftUI
import MetalKit
import AppKit

struct MetalEmulatorView: NSViewRepresentable {
    var framebuffer: Framebuffer

    typealias NSViewType = NSView

    @inline(__always) func makeNSView(context: Context) -> NSView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return MetalUnavailableView.make(message: "Metal is unavailable on this device.")
        }

        let view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false

        guard let renderer = MetalRenderer(view: view) else {
            return MetalUnavailableView.make(message: "Failed to initialize Metal renderer.")
        }

        context.coordinator.renderer = renderer
        view.delegate = renderer
        return view
    }

    @inline(__always) func updateNSView(_ nsView: NSView, context: Context) {
        guard let mtkView = nsView as? MTKView else { return }
        context.coordinator.renderer?.update(framebuffer: framebuffer)
        mtkView.isPaused = false
    }

    @inline(__always) func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: MetalRenderer?
    }
}

private enum MetalUnavailableView {
    @inline(__always) static func make(message: String) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        let label = NSTextField(labelWithString: message)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8)
        ])

        return container
    }
}
