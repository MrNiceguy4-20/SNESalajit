import Foundation
import Metal
import MetalKit

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private var texture: MTLTexture?

    private var latestFramebuffer: Framebuffer?

    init?(view: MTKView) {
        guard let device = view.device,
              let queue = device.makeCommandQueue()
        else { return nil }

        self.device = device
        self.queue = queue

        // Load shaders from default library
        let library = device.makeDefaultLibrary()
        let vfn = library?.makeFunction(name: "vs_main")
        let ffn = library?.makeFunction(name: "fs_main")

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat

        do {
            self.pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            NSLog("Pipeline creation failed: \(error)")
            return nil
        }

        let samp = MTLSamplerDescriptor()
        samp.minFilter = .nearest
        samp.magFilter = .nearest
        self.sampler = device.makeSamplerState(descriptor: samp)!

        super.init()
    }

    func update(framebuffer: Framebuffer) {
        latestFramebuffer = framebuffer
        ensureTexture(width: framebuffer.width, height: framebuffer.height)
        upload(framebuffer: framebuffer)
    }

    private func ensureTexture(width: Int, height: Int) {
        if let tex = texture, tex.width == width, tex.height == height { return }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                         width: width,
                                                         height: height,
                                                         mipmapped: false)
        td.usage = [.shaderRead]
        texture = device.makeTexture(descriptor: td)
    }

    private func upload(framebuffer: Framebuffer) {
        guard let tex = texture else { return }
        var fb = framebuffer
        fb.pixels.withUnsafeMutableBytes { raw in
            let region = MTLRegionMake2D(0, 0, fb.width, fb.height)
            tex.replace(region: region,
                        mipmapLevel: 0,
                        withBytes: raw.baseAddress!,
                        bytesPerRow: fb.width * 4)
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass)
        else { return }

        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(texture, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)

        // Fullscreen triangle (no vertex buffer).
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}
