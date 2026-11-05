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
