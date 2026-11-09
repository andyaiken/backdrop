import AppKit
import Metal
import BackdropCore
import QuartzCore

/// Morph cues: one picture becoming another, and that one the next, a stage
/// at a time. Matched points slide from their places on one picture to their
/// places on the next, the pictures stretch with them, and the one dissolves
/// into the other.
///
/// Drawn with Metal: each stage's triangle mesh (`MorphMesh`), each vertex
/// carrying where it falls on both pictures, so one pass draws both, warped,
/// and mixes them. It paints on every display refresh, not just on the
/// clock's frames, so the stretch is smooth.
///
/// The stages run on a `GoTimeline`, so a cue can wait for GO before each,
/// and jump to any. Only the two pictures of the stage on stage are kept,
/// with the next loading ahead, however many the cue has.
///
/// Each picture is fitted to 90% of the stage, keeping its shape, as an
/// image cue fits its grid: a morph from a picture an image cue has just
/// shown starts exactly where that picture is.
@MainActor
public final class MorphRenderer: PaintsBetweenFrames, ReportsProblems, WaitsForGO, Snapshots {
    public let isInstant = false
    public var onProblem: ((String) -> Void)?

    private let media: (String) -> URL?
    private let loader: ImageLoader
    private let gpu: MorphGPU?
    /// Draws to the surfaces' own layers. Tests draw offscreen instead.
    private let onScreen: Bool

    /// What a prepared cue draws: its stages, where each picture comes from,
    /// and when each stage was let go.
    struct Plan {
        let cue: MorphCuePlan
        /// Each picture's source, and how problems name it.
        let sources: [ImageSource]
        let paths: [String]
        let label: String
        let number: String
        var timeline: GoTimeline
    }

    struct Picture {
        let texture: MTLTexture
        /// Width over height.
        let aspect: Double
    }

    private(set) var plan: Plan?
    /// The pictures loaded, by their place in the cue.
    private var pictures: [Int: Picture] = [:]
    /// Those on their way.
    private var loading: Set<Int> = []
    /// Those already said to be unreadable, so going back doesn't say so again.
    private var reported: Set<Int> = []
    /// What is on stage: the stage, and how far through it is.
    private(set) var shown = MorphCuePlan.Shown(stage: nil, progress: 0)
    /// How far through its stage the stage is, from 0 to 1.
    var progress: Double { shown.progress }
    /// Counts prepares, so a picture arriving for an earlier cue is dropped.
    private var token = 0
    private var trees: [ObjectIdentifier: Tree] = [:]
    /// A mesh with no points, for the first picture standing alone.
    private static let still = MorphMesh(pairs: [])

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
        reset()
        tree(for: surface)?.metal.isHidden = true
    }

    private func reset() {
        token += 1
        plan = nil
        pictures = [:]
        loading = []
        reported = []
        shown = MorphCuePlan.Shown(stage: nil, progress: 0)
    }

    public func prepare(_ cue: Cue, show: ShowSettings) {
        guard case .morph(let content) = cue.content else { return }
        reset()
        let settings = content.settings
        let cuePlan = MorphCuePlan(content, settings: settings)
        // With no pictures at all, the label on black, standing.
        let paths = content.pictures.isEmpty ? [""] : content.pictures.map(\.src)
        var sources: [ImageSource] = []
        for (i, path) in paths.enumerated() {
            let (source, problem) = source(path, label: content.text, number: cue.number, which: Self.ordinal(i))
            if let problem { onProblem?(problem) }
            sources.append(source)
        }
        plan = Plan(cue: cuePlan, sources: sources, paths: paths, label: content.text, number: cue.number,
                    timeline: GoTimeline(parts: cuePlan.parts))
        guard gpu != nil else {
            onProblem?("This Mac can\u{2019}t draw morphs: it has no Metal graphics.")
            return
        }
        keep(around: shown)
    }

    /// Which picture "first", "second" and on, for problems to name it by.
    static func ordinal(_ i: Int) -> String {
        let words = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]
        return i < words.count ? words[i] : "\(i + 1)th"
    }

    /// The two pictures a moment shows, and the one after, loaded; any
    /// others let go.
    private func keep(around shown: MorphCuePlan.Shown) {
        guard let plan, let gpu else { return }
        let wanted = Set([shown.from, shown.to, shown.to + 1].filter(plan.sources.indices.contains))
        pictures = pictures.filter { wanted.contains($0.key) }
        for i in wanted.subtracting(pictures.keys).subtracting(loading).sorted() {
            loading.insert(i)
            load(i, from: plan.sources[i], gpu: gpu)
        }
    }

    private func load(_ i: Int, from source: ImageSource, gpu: MorphGPU) {
        let token = self.token
        loader.load(source, maxPixels: maxPixels) { [weak self] result in
            guard let self, token == self.token, let plan = self.plan else { return }
            switch result {
            case .success(let image):
                self.received(image, at: i, gpu: gpu)
            case .failure:
                // Unreadable: the label on black, as an image cue does.
                if !self.reported.contains(i) {
                    self.reported.insert(i)
                    let name = (plan.paths[i] as NSString).lastPathComponent
                    self.onProblem?("Cue \(plan.number)\u{2019}s \(Self.ordinal(i)) picture, \(name), couldn\u{2019}t be read, so it is showing its label on black.")
                }
                self.load(i, from: .label(plan.label), gpu: gpu)
            }
        }
    }

    private func received(_ image: CGImage, at i: Int, gpu: MorphGPU) {
        loading.remove(i)
        guard let texture = gpu.texture(from: image) else { return }
        // Let go while it was on its way.
        guard Set([shown.from, shown.to, shown.to + 1]).contains(i) else { return }
        let wasReady = isReady
        pictures[i] = Picture(texture: texture, aspect: Double(image.width) / Double(max(image.height, 1)))
        if isReady, !wasReady {
            drawAll()
            onReady?()
        }
    }

    /// Both pictures of what is on stage are here to draw.
    var isReady: Bool {
        plan != nil && pictures[shown.from] != nil && pictures[shown.to] != nil
    }

    public func preload(_ cue: Cue, show: ShowSettings) {
        guard case .morph(let content) = cue.content else { return }
        for (i, picture) in content.pictures.prefix(3).enumerated() {
            loader.load(source(picture.src, label: content.text, number: cue.number, which: Self.ordinal(i)).source, maxPixels: maxPixels) { _ in }
        }
    }

    public func frame(_ f: Int) -> Bool {
        paint(at: Double(f))
    }

    public func paint(at position: Double) -> Bool {
        guard let plan else { return true }
        let now = plan.cue.shown(at: position, timeline: plan.timeline)
        let moved = now.stage != shown.stage
        if now != shown || trees.values.contains(where: { $0.metal.isHidden }) {
            shown = now
            if moved { keep(around: now) }
            drawAll()
        }
        // Not finished while its pictures are still on their way, so nothing
        // continues from a black stage.
        return isReady && plan.cue.isFinished(at: position, timeline: plan.timeline)
    }

    // MARK: WaitsForGO

    public func isWaiting(at f: Int) -> Bool {
        plan?.timeline.isWaiting(at: f) == true
    }

    public func carryOn(at f: Int) {
        plan?.timeline.carryOn(at: f)
    }

    public func carryOnToEnd() {
        plan?.timeline.carryOnToEnd()
    }

    /// GO point k lets go stage k, in part k + 1; part 0 is the first
    /// picture standing.
    public func goTo(_ point: Int, at f: Int) {
        plan?.timeline.jump(toPart: point + 1, at: f)
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

    /// What is on stage, ready to draw: the mesh, and both pictures.
    private var current: (mesh: MorphMesh, first: Picture, second: Picture)? {
        guard let plan, let first = pictures[shown.from], let second = pictures[shown.to] else { return nil }
        return (shown.stage.map { plan.cue.stages[$0].mesh } ?? Self.still, first, second)
    }

    /// Draws the current moment into a surface's layer.
    private func draw(_ tree: Tree) {
        guard onScreen, let gpu, let (mesh, first, second) = current else { return }
        let size = tree.surface.inset.bounds.size
        guard size.width > 0, size.height > 0, let drawable = tree.metal.nextDrawable() else { return }
        gpu.draw(vertices: Self.vertices(mesh, first: first.aspect, second: second.aspect, at: progress, in: size), indices: mesh.triangles,
                 first: first.texture, second: second.texture, mix: progress, into: drawable.texture, present: drawable)
        tree.metal.isHidden = false
    }

    public func snapshot(size: CGSize) -> CGImage? { image(size: size) }

    /// The current moment, drawn offscreen at a size.
    func image(size: CGSize) -> CGImage? {
        guard let gpu, let (mesh, first, second) = current else { return nil }
        return gpu.image(width: Int(size.width), height: Int(size.height)) { target in
            gpu.draw(vertices: Self.vertices(mesh, first: first.aspect, second: second.aspect, at: progress, in: size), indices: mesh.triangles,
                     first: first.texture, second: second.texture, mix: progress, into: target, present: nil)
        }
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

    private func source(_ path: String, label: String, number: String, which: String) -> (source: ImageSource, problem: String?) {
        let fallback = ImageSource.label(label)
        guard !path.isEmpty else { return (fallback, nil) }
        guard let url = media(path) else {
            let name = (path as NSString).lastPathComponent
            return (fallback, "Cue \(number)\u{2019}s \(which) picture, \(name), is missing from the show, so it is showing its label on black.")
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
