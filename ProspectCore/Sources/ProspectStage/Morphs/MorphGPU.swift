import AppKit
import Metal
import QuartzCore

/// One vertex as the shader reads it.
struct MorphVertex {
    var position: SIMD2<Float>
    var first: SIMD2<Float>
    var second: SIMD2<Float>
}

/// The Metal side: the device, the one pipeline, and drawing a mesh.
@MainActor
final class MorphGPU {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState

    /// The shader, compiled when the renderer is made: each vertex carries
    /// its place on both pictures, so one pass warps both and mixes them.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Vertex { float2 position; float2 first; float2 second; };
    struct Fragment { float4 position [[position]]; float2 first; float2 second; };

    vertex Fragment morph_vertex(const device Vertex *vertices [[buffer(0)]], uint id [[vertex_id]]) {
        Vertex v = vertices[id];
        Fragment f;
        f.position = float4(v.position, 0, 1);
        f.first = v.first;
        f.second = v.second;
        return f;
    }

    fragment float4 morph_fragment(Fragment f [[stage_in]],
                                   texture2d<float> first [[texture(0)]],
                                   texture2d<float> second [[texture(1)]],
                                   sampler s [[sampler(0)]],
                                   constant float &mix_ [[buffer(0)]]) {
        float4 colour = mix(first.sample(s, f.first), second.sample(s, f.second), mix_);
        return float4(colour.rgb, 1);
    }
    """

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.source, options: nil) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "morph_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "morph_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.sampler = sampler
    }

    /// A picture as a texture, with mipmaps so it shrinks cleanly. It is
    /// drawn first into a plain sRGB bitmap, so whatever its colour space or
    /// byte order, the texture holds the colours the stage's other layers
    /// would show. Metal's own texture loader swapped colour channels on
    /// some pictures and shifted the colours of others.
    func texture(from image: CGImage) -> MTLTexture? {
        let w = image.width, h = image.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: true)
        descriptor.usage = .shaderRead
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: descriptor), let bytes = ctx.data else { return nil }
        // A bitmap holds its top row first, as a texture does.
        texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: bytes, bytesPerRow: w * 4)
        if let buffer = queue.makeCommandBuffer(), let blit = buffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            buffer.commit()
        }
        return texture
    }

    func draw(vertices: [MorphVertex], indices: [Int], first: MTLTexture, second: MTLTexture, mix: Double,
              into target: MTLTexture, present drawable: CAMetalDrawable?) {
        guard !vertices.isEmpty, !indices.isEmpty, let buffer = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var vertices = vertices
        var mix = Float(mix)
        let indexes = indices.map { UInt16($0) }
        guard let vertexBuffer = device.makeBuffer(bytes: &vertices, length: MemoryLayout<MorphVertex>.stride * vertices.count),
              let indexBuffer = device.makeBuffer(bytes: indexes, length: MemoryLayout<UInt16>.stride * indexes.count) else {
            encoder.endEncoding()
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(first, index: 0)
        encoder.setFragmentTexture(second, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&mix, length: MemoryLayout<Float>.size, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexes.count, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
        encoder.endEncoding()
        if let drawable { buffer.present(drawable) }
        buffer.commit()
    }

    /// Draws offscreen and reads the result back as a picture.
    func image(width: Int, height: Int, draw: (MTLTexture) -> Void) -> CGImage? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: max(width, 1), height: max(height, 1),
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        // A Mac whose graphics have their own memory can't share a texture
        // with the processor; it keeps a copy that is synchronised instead.
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let target = device.makeTexture(descriptor: descriptor) else { return nil }
        draw(target)
        // Wait for the drawing, then read it.
        guard let wait = queue.makeCommandBuffer() else { return nil }
        if target.storageMode == .managed, let blit = wait.makeBlitCommandEncoder() {
            blit.synchronize(resource: target)
            blit.endEncoding()
        }
        wait.commit()
        wait.waitUntilCompleted()
        let bytesPerRow = target.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * target.height)
        target.getBytes(&bytes, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, target.width, target.height), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: target.width, height: target.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }
}
