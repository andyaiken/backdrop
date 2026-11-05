import AppKit
import Metal
import ProspectCore
import QuartzCore

/// Morph cues: one picture becoming another. Matched points slide from
/// their places on the first picture to their places on the second, the
/// pictures stretch with them, and the first dissolves into the second.
///
/// Drawn with Metal: the model's triangle mesh (`MorphMesh`), each vertex
/// carrying where it falls on both pictures, so one pass draws both, warped,
/// and mixes them. It paints on every display refresh, not just on the
/// clock's frames, so the stretch is smooth.
///
/// Each picture is fitted to 90% of the stage, keeping its shape, as an
/// image cue fits its grid: a morph from a picture an image cue has just
/// shown starts exactly where that picture is.
@MainActor
public final class MorphRenderer: PaintsBetweenFrames, ReportsProblems {
    public let isInstant = false
    public var onProblem: ((String) -> Void)?

    private let media: (String) -> URL?
    private let loader: ImageLoader
    private let gpu: MorphGPU?
    /// Draws to the surfaces' own layers. Tests draw offscreen instead.
    private let onScreen: Bool

    /// What a prepared cue draws: its mesh, timing, and both pictures once
    /// they are decoded.
    struct Plan {
        let mesh: MorphMesh
        let clockMs: Int
        let morphMs: Int
        var first: Picture?
        var second: Picture?
        var isReady: Bool { first != nil && second != nil }
    }

    struct Picture {
        let texture: MTLTexture
        /// Width over height.
        let aspect: Double
    }

    private(set) var plan: Plan?
    /// How far through the morph the stage is, from 0 to 1.
    private(set) var progress = 0.0
    private var token = 0
    private var trees: [ObjectIdentifier: Tree] = [:]

    /// - Parameters:
    ///   - media: Where a path in the show's package is on disk.
    ///   - onScreen: False to draw only offscreen, for tests.
    public init(media: @escaping (String) -> URL? = { _ in nil }, loader: ImageLoader = ImageLoader(), onScreen: Bool = true) {
        self.media = media
        self.loader = loader
        self.onScreen = onScreen
        gpu = MorphGPU()
    }

    /// Called when a cue's pictures are ready to draw.
    var onReady: (() -> Void)?

    /// One surface's layers.
    final class Tree {
        let surface: SurfaceLayer
        let root = StillLayer()
        let metal = CAMetalLayer()

        init(surface: SurfaceLayer, device: MTLDevice?) {
            self.surface = surface
            root.isHidden = true
            metal.device = device
            metal.pixelFormat = .bgra8Unorm
            // Colour-managed as every other layer on stage is.
            metal.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            metal.framebufferOnly = true
            metal.isOpaque = true
            metal.backgroundColor = CGColor.black
            metal.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
            metal.isHidden = true
            root.addSublayer(metal)
        }
    }

    func tree(for surface: SurfaceLayer) -> Tree? {
        trees[ObjectIdentifier(surface)]
    }

    // MARK: CueRenderer

    public func mount(on surface: SurfaceLayer) {
        let tree = Tree(surface: surface, device: gpu?.device)
        trees[ObjectIdentifier(surface)] = tree
        surface.inset.addSublayer(tree.root)
        fit(surface)
    }

    public func unmount(from surface: SurfaceLayer) {
        trees.removeValue(forKey: ObjectIdentifier(surface))?.root.removeFromSuperlayer()
    }

    public func setVisible(_ visible: Bool, on surface: SurfaceLayer) {
        tree(for: surface)?.root.isHidden = !visible
    }

    /// The last cue's last frame must never show while the next one loads.
    public func clear(_ surface: SurfaceLayer) {
        token += 1
        plan = nil
        progress = 0
        tree(for: surface)?.metal.isHidden = true
    }

    public func prepare(_ cue: Cue, defaults: ShowSettings) {
        guard case .morph(let content) = cue.content else { return }
        token += 1
        let settings = defaults.resolved(content.overrides)
        plan = Plan(mesh: MorphMesh(pairs: content.pairs), clockMs: settings.clockMs, morphMs: settings.morphMs)
        progress = 0
        guard let gpu else {
            onProblem?("This Mac can\u{2019}t draw morphs: it has no Metal graphics.")
            return
        }
        let token = self.token
        for (path, isFirst) in [(content.src, true), (content.into, false)] {
            let which = isFirst ? "first" : "second"
            let (source, problem) = source(path, label: content.text, cue: cue, which: which)
            if let problem { onProblem?(problem) }
            loader.load(source, maxPixels: maxPixels) { [weak self] result in
                guard let self, token == self.token else { return }
                switch result {
                case .success(let image):
                    self.received(image, first: isFirst, gpu: gpu)
                case .failure:
                    // Unreadable: the label on black, as an image cue does.
                    let name = (path as NSString).lastPathComponent
                    self.onProblem?("Cue \(cue.number)\u{2019}s \(which) picture, \(name), couldn\u{2019}t be read, so it is showing its label on black.")
                    self.loader.load(.label(content.text), maxPixels: self.maxPixels) { [weak self] result in
                        guard let self, token == self.token, case .success(let image) = result else { return }
                        self.received(image, first: isFirst, gpu: gpu)
                    }
                }
            }
        }
    }

    private func received(_ image: CGImage, first isFirst: Bool, gpu: MorphGPU) {
        guard let texture = gpu.texture(from: image) else { return }
        let picture = Picture(texture: texture, aspect: Double(image.width) / Double(max(image.height, 1)))
        if isFirst { plan?.first = picture } else { plan?.second = picture }
        if plan?.isReady == true {
            drawAll()
            onReady?()
        }
    }

    public func preload(_ cue: Cue, defaults: ShowSettings) {
        guard case .morph(let content) = cue.content else { return }
        for path in [content.src, content.into] {
            loader.load(source(path, label: content.text, cue: cue, which: "").source, maxPixels: maxPixels) { _ in }
        }
    }

    public func frame(_ f: Int) -> Bool {
        paint(at: Double(f))
    }

    public func paint(at position: Double) -> Bool {
        guard let plan else { return true }
        let ms = max(0, position) * Double(plan.clockMs)
        let t = MorphTiming.progress(ms: ms, morphMs: plan.morphMs)
        if t != progress || trees.values.contains(where: { $0.metal.isHidden }) {
            progress = t
            drawAll()
        }
        // Not finished while its pictures are still on their way, so nothing
        // continues from a black stage.
        return plan.isReady && ms >= Double(plan.morphMs)
    }

    public func fit(_ surface: SurfaceLayer) {
        guard let tree = tree(for: surface) else { return }
        let bounds = surface.inset.bounds
        tree.root.frame = bounds
        tree.metal.frame = bounds
        let scale = max(surface.contentsScale, 1)
        tree.metal.contentsScale = scale
        tree.metal.drawableSize = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
        draw(tree)
    }

    // MARK: Drawing

    private func drawAll() {
        for tree in trees.values { draw(tree) }
    }

    /// Draws the current moment into a surface's layer.
    private func draw(_ tree: Tree) {
        guard onScreen, let gpu, let plan, let first = plan.first, let second = plan.second else { return }
        let size = tree.surface.inset.bounds.size
        guard size.width > 0, size.height > 0, let drawable = tree.metal.nextDrawable() else { return }
        gpu.draw(vertices: vertices(plan, in: size), indices: plan.mesh.triangles, first: first.texture,
                 second: second.texture, mix: progress, into: drawable.texture, present: drawable)
        tree.metal.isHidden = false
    }

    /// The current moment, drawn offscreen at a size, for tests.
    func image(size: CGSize) -> CGImage? {
        guard let gpu, let plan, let first = plan.first, let second = plan.second else { return nil }
        return gpu.image(width: Int(size.width), height: Int(size.height)) { target in
            gpu.draw(vertices: vertices(plan, in: size), indices: plan.mesh.triangles, first: first.texture,
                     second: second.texture, mix: progress, into: target, present: nil)
        }
    }

    private func vertices(_ plan: Plan, in size: CGSize) -> [MorphVertex] {
        guard let first = plan.first, let second = plan.second else { return [] }
        return Self.vertices(plan.mesh, first: first.aspect, second: second.aspect, at: progress, in: size)
    }

    /// Each vertex `t` of the way through, in Metal's clip space, with where
    /// it falls on each picture.
    static func vertices(_ mesh: MorphMesh, first: Double, second: Double, at t: Double, in size: CGSize) -> [MorphVertex] {
        let a = placement(aspect: first, in: size), b = placement(aspect: second, in: size)
        return zip(mesh.from, mesh.to).map { from, to in
            let ax = a.minX + from.x * a.width, ay = a.minY + from.y * a.height
            let bx = b.minX + to.x * b.width, by = b.minY + to.y * b.height
            let x = ax + (bx - ax) * t, y = ay + (by - ay) * t
            return MorphVertex(
                position: SIMD2(Float(x / size.width * 2 - 1), Float(1 - y / size.height * 2)),
                first: SIMD2(Float(from.x), Float(from.y)),
                second: SIMD2(Float(to.x), Float(to.y))
            )
        }
    }

    /// Where a picture sits on a stage of `size`, measured from the top
    /// left: 90% of it, keeping the picture's shape, on whole points, as an
    /// image cue places its grid.
    static func placement(aspect: Double, in size: CGSize) -> CGRect {
        let W = size.width, H = size.height, aspect = CGFloat(max(aspect, 0.01))
        let w = min(W * 0.9, H * 0.9 * aspect).rounded(), h = (w / aspect).rounded()
        return CGRect(x: ((W - w) / 2).rounded(), y: ((H - h) / 2).rounded(), width: w, height: h)
    }

    // MARK: Pictures

    private func source(_ path: String, label: String, cue: Cue, which: String) -> (source: ImageSource, problem: String?) {
        let fallback = ImageSource.label(label)
        guard !path.isEmpty else { return (fallback, nil) }
        guard let url = media(path) else {
            let name = (path as NSString).lastPathComponent
            return (fallback, "Cue \(cue.number)\u{2019}s \(which) picture, \(name), is missing from the show, so it is showing its label on black.")
        }
        return (.file(url), nil)
    }

    /// The longest side, in pixels, any surface shows a picture at, rounded
    /// up so nearby sizes share a decode.
    private var maxPixels: Int {
        let needed = trees.values.map { tree -> CGFloat in
            let b = tree.surface.inset.bounds
            return max(b.width, b.height) * 0.9 * max(tree.surface.contentsScale, 1)
        }.max() ?? 2048
        let bucket = 512
        return min(max(Int((needed / CGFloat(bucket)).rounded(.up)) * bucket, 1024), 8192)
    }
}

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
