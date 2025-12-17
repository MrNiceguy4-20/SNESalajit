import SwiftUI
import MetalKit

struct MetalEmulatorView: NSViewRepresentable {
    var framebuffer: Framebuffer

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false

        context.coordinator.renderer = MetalRenderer(view: view)
        view.delegate = context.coordinator.renderer
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.update(framebuffer: framebuffer)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: MetalRenderer?
    }
}
