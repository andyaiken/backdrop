import AppKit
import ProspectCore
import QuartzCore

/// Image cues: a photograph arriving as a grid of tiles that flip over, or
/// sharpen.
///
/// Each tile is a 3D layer with two faces. The back is black, so the cue opens
/// on nothing; the front shows its share of the picture. The clock says when each tile starts. A flip is a Core
/// Animation animation with its own duration; a sharpen steps through ever
/// finer blocks of the picture on the clock's frames, over the same time.
@MainActor
public final class ImageRenderer: CueRenderer, ReportsProblems {
    public let isInstant = false
    public var onProblem: ((String) -> Void)?

    /// The viewing distance of the tile grid's perspective, in points.
    nonisolated static let perspective: CGFloat = 1600

    private var random: AnyUnitRandom
    private let loader: ImageLoader
    private let media: (String) -> URL?

    private var cue: Cue?
    private var settings: ImageSettings?
    /// Bumped whenever the cue changes, so a slow load for an earlier cue
    /// can't land on a later one.
    private var token = 0
    private(set) var plan: Plan?
    /// The last frame the clock asked for, kept so tiles can catch up when a
    /// slow picture arrives.
    private var lastFrame: Int?
    private var fresh = true
    private var trees: [ObjectIdentifier: Tree] = [:]

    /// Called when a cue's picture is ready and its tiles are built.
    var onReady: (() -> Void)?

    struct Plan {
        let image: CGImage
        let schedule: TileSchedule
        let flipFrames: Int
        let flipDuration: CFTimeInterval
        let reveal: TileReveal
        /// For a sharpen: the picture in ever finer blocks, coarsest first.
        let levels: [CGImage]
        /// What a sharpening reveal opens on: the whole picture's average colour.
        let average: RGB
        /// For quarters: when each rectangle splits, and the colour of each.
        let quarters: Quarters?

        struct Quarters {
            let schedule: QuarterSchedule
            let colours: [RGB]
            /// The frame the finished picture starts to come up over the pieces.
            var finalStart: Int { schedule.lastStart + 1 }
        }

        /// A picture just shown is settled before it starts.
        var settleFrame: Int {
            if reveal == .show { return Int.min }
            return (quarters?.finalStart ?? schedule.lastStart) + flipFrames
        }
    }

    final class Tree {
        let surface: SurfaceLayer
        let root = StillLayer()
        let grid = StillLayer()
        var tiles: [TileLayer] = []
        /// For quarters: a layer for every rectangle that can ever show, and the
        /// finished picture over them.
        var blocks: [StillLayer] = []
        let picture = StillLayer()

        init(surface: SurfaceLayer) {
            self.surface = surface
            root.isHidden = true
            var perspective = CATransform3DIdentity
            perspective.m34 = -1 / ImageRenderer.perspective
            grid.sublayerTransform = perspective
            root.addSublayer(grid)
        }
    }

    /// - Parameters:
    ///   - media: Finds a cue's image file from its path in the show.
    ///   - random: Shuffles the random order, and jitters starts.
    public init(
        media: @escaping (String) -> URL? = { _ in nil },
        loader: ImageLoader = ImageLoader(),
        random: some UnitRandom = SystemUnitRandom()
    ) {
        self.media = media
        self.loader = loader
        self.random = AnyUnitRandom(random)
    }

    func tree(for surface: SurfaceLayer) -> Tree? {
        trees[ObjectIdentifier(surface)]
    }

    // MARK: CueRenderer

    public func mount(on surface: SurfaceLayer) {
        let tree = Tree(surface: surface)
        trees[ObjectIdentifier(surface)] = tree
        surface.inset.addSublayer(tree.root)
        if plan != nil {
            build(tree)
            if let lastFrame { apply(lastFrame, animated: false) }
        }
        fit(surface)
    }

    public func unmount(from surface: SurfaceLayer) {
        trees.removeValue(forKey: ObjectIdentifier(surface))?.root.removeFromSuperlayer()
    }

    public func setVisible(_ visible: Bool, on surface: SurfaceLayer) {
        tree(for: surface)?.root.isHidden = !visible
    }

    /// Tiles from the previous image would otherwise stay face-up while the
    /// next one loads.
    public func clear(_ surface: SurfaceLayer) {
        token += 1
        cue = nil
        plan = nil
        lastFrame = nil
        guard let tree = tree(for: surface) else { return }
        tree.tiles.forEach { $0.removeFromSuperlayer() }
        tree.tiles = []
    }

    public func prepare(_ cue: Cue, show: ShowSettings) {
        guard case .image(let content) = cue.content else { return }
        token += 1
        self.cue = cue
        settings = content.settings
        plan = nil
        lastFrame = nil
        fresh = true
        let token = self.token
        let (source, problem) = source(for: cue, content)
        if let problem { onProblem?(problem) }
        loader.load(source, maxPixels: maxPixels) { [weak self] result in
            guard let self, token == self.token else { return }
            switch result {
            case .success(let image):
                self.ready(image)
            case .failure(let failure):
                self.onProblem?(Self.describe(failure, cue: cue, src: content.src))
                self.loader.load(.label(content.text), maxPixels: self.maxPixels) { [weak self] result in
                    guard let self, token == self.token, case .success(let image) = result else { return }
                    self.ready(image)
                }
            }
        }
    }

    public func frame(_ f: Int) -> Bool {
        lastFrame = f
        guard let plan else { return false }
        // A cue put up finished, as on resuming after a crash, lands without
        // animation; tiles catching up after a slow load still flip.
        apply(f, animated: !(fresh && f >= plan.settleFrame))
        fresh = false
        return f >= plan.settleFrame
    }

    public func fit(_ surface: SurfaceLayer) {
        guard let tree = tree(for: surface), let plan else { return }
        let W = surface.inset.bounds.width, H = surface.inset.bounds.height
        guard W > 0, H > 0 else { return }
        tree.root.frame = surface.inset.bounds

        // The grid fits 90% of the picture area, keeping the image's shape.
        let aspect = CGFloat(plan.schedule.grid.aspect)
        let w = min(W * 0.9, H * 0.9 * aspect).rounded(), h = (w / aspect).rounded()
        tree.grid.frame = CGRect(x: ((W - w) / 2).rounded(), y: ((H - h) / 2).rounded(), width: w, height: h)

        // Tile edges land on whole device pixels, so neighbouring tiles meet
        // exactly. Between pixels they could leave a hairline of the black
        // output showing through the picture.
        let grid = plan.schedule.grid
        let scale = max(surface.contentsScale, 1)
        func edge(_ i: Int, of n: Int, across length: CGFloat) -> CGFloat {
            (CGFloat(i) * length / CGFloat(n) * scale).rounded() / scale
        }
        if let quarters = plan.quarters {
            for (node, block) in tree.blocks.enumerated() {
                let r = QuarterSchedule.rect(of: node)
                // Rectangle edges on whole device pixels, so the pieces meet.
                let left = (CGFloat(r.x) * w * scale).rounded() / scale, right = (CGFloat(r.x + r.width) * w * scale).rounded() / scale
                let top = (CGFloat(r.y) * h * scale).rounded() / scale, bottom = (CGFloat(r.y + r.height) * h * scale).rounded() / scale
                block.frame = CGRect(x: left, y: h - bottom, width: right - left, height: bottom - top)
            }
            _ = quarters
            tree.picture.frame = CGRect(x: 0, y: 0, width: w, height: h)
        }
        for (i, tile) in tree.tiles.enumerated() {
            let x = i % grid.columns, y = i / grid.columns
            let left = edge(x, of: grid.columns, across: w), right = edge(x + 1, of: grid.columns, across: w)
            let top = edge(y, of: grid.rows, across: h), bottom = edge(y + 1, of: grid.rows, across: h)
            tile.bounds = CGRect(x: 0, y: 0, width: right - left, height: bottom - top)
            // Row 0 is the top row; Core Animation measures from the bottom.
            tile.position = CGPoint(x: (left + right) / 2, y: h - (top + bottom) / 2)
            tile.layoutFaces()
        }
    }

    public func preload(_ cue: Cue, show: ShowSettings) {
        guard case .image(let content) = cue.content else { return }
        loader.load(source(for: cue, content).source, maxPixels: maxPixels) { _ in }
    }

    // MARK: Pictures

    private func source(for cue: Cue, _ content: ImageContent) -> (source: ImageSource, problem: String?) {
        let label = ImageSource.label(content.text)
        guard !content.src.isEmpty else { return (label, nil) }
        guard let url = media(content.src) else {
            return (label, Self.describe(.init(reason: .missing), cue: cue, src: content.src))
        }
        return (.file(url), nil)
    }

    private static func describe(_ failure: ImageLoader.Failure, cue: Cue, src: String) -> String {
        let name = (src as NSString).lastPathComponent
        switch failure.reason {
        case .missing:
            return "Cue \(cue.number)\u{2019}s image, \(name), is missing from the show, so it is showing its label on black."
        case .undecodable:
            return "Cue \(cue.number)\u{2019}s image, \(name), couldn\u{2019}t be read, so it is showing its label on black."
        }
    }

    /// The longest side, in pixels, any surface will show the picture at,
    /// rounded up so nearby sizes share a decode.
    private var maxPixels: Int {
        let needed = trees.values.map { tree -> CGFloat in
            let b = tree.surface.inset.bounds
            return max(b.width, b.height) * 0.9 * max(tree.surface.contentsScale, 1)
        }.max() ?? 2048
        let bucket = 512
        return min(max(Int((needed / CGFloat(bucket)).rounded(.up)) * bucket, 1024), 8192)
    }

    private func ready(_ image: CGImage) {
        guard let settings else { return }
        let grid = TileGrid(imageWidth: Double(image.width), imageHeight: Double(image.height), columns: settings.gridColumns)
        // Quarters belongs to a reveal that sharpens; a flip has no quarters.
        let sharpens = settings.reveal == .sharpen
        let quartered = sharpens && settings.order == .quarters
        let tileOrder = settings.order == .quarters ? TileOrder.random : settings.order
        let schedule = TileSchedule(grid: grid, order: tileOrder, wave: settings.waveTicks, random: &random)
        let average = Self.averages(of: image, columns: 1, rows: 1).first ?? Palette.slate
        var quarters: Plan.Quarters?
        if quartered {
            let depth = QuarterSchedule.depth(forColumns: settings.gridColumns)
            let split = QuarterSchedule(depth: depth, step: settings.waveTicks, random: &random)
            quarters = Plan.Quarters(schedule: split, colours: Self.quarterColours(of: image, depth: depth))
        }
        plan = Plan(
            image: image,
            schedule: schedule,
            flipFrames: schedule.settleFrame(flipMs: settings.flipMs, clockMs: settings.clockMs) - schedule.lastStart,
            flipDuration: CFTimeInterval(settings.flipMs) / 1000,
            reveal: settings.reveal,
            levels: sharpens && !quartered ? Self.sharpeningLevels(of: image, grid: grid) : [],
            average: average,
            quarters: quarters
        )
        for tree in trees.values {
            build(tree)
            fit(tree.surface)
        }
        if let lastFrame {
            _ = frame(lastFrame)
        }
        onReady?()
    }

    /// The average colour of each cell of a grid laid over the picture, from
    /// the picture drawn at a whole multiple of the grid's size: every pixel
    /// counts equally. Row by row from the top left.
    static func averages(of image: CGImage, columns: Int, rows: Int) -> [RGB] {
        let k = 8, w = columns * k, h = rows * k
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return Array(repeating: Palette.slate, count: columns * rows)
        }
        // Without interpolation, so a smoothing filter doesn't bleed
        // neighbours into a cell's average.
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Bitmap memory holds the top row first.
        let bytes = Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: w * h * 4))
        let averages = TileFaces.blockAverages(rgba: bytes, width: w, height: h, columns: columns, rows: rows)
        return stride(from: 0, to: averages.count - 3, by: 4).map { RGB(averages[$0], averages[$0 + 1], averages[$0 + 2]) }
    }

    /// The colour of every rectangle quarters can show: the smallest from the
    /// picture itself, each larger the mean of its four.
    static func quarterColours(of image: CGImage, depth: Int) -> [RGB] {
        let n = Int(pow(2, Double(depth)))
        let leaves = averages(of: image, columns: n, rows: n)
        let count = QuarterSchedule.nodeCount(depth: depth)
        var colours = [RGB](repeating: Palette.slate, count: count)
        for node in stride(from: count - 1, through: 0, by: -1) {
            if QuarterSchedule.level(of: node) == depth {
                let r = QuarterSchedule.rect(of: node)
                colours[node] = leaves[min(Int(r.y * Double(n) + 0.5), n - 1) * n + min(Int(r.x * Double(n) + 0.5), n - 1)]
            } else {
                let kids = QuarterSchedule.children(of: node).map { colours[$0] }
                func mean(_ channel: KeyPath<RGB, UInt8>) -> UInt8 { UInt8(kids.map { Int($0[keyPath: channel]) }.reduce(0, +) / 4) }
                colours[node] = RGB(mean(\.r), mean(\.g), mean(\.b))
            }
        }
        return colours
    }

    /// The steps a tile sharpens through: its part of the picture as one
    /// block, then 2 x 2, 3 x 3, 5 x 5, 8 x 8 and on through the Fibonacci
    /// numbers while a block is still at least two of the picture's pixels
    /// across. Each level is drawn down from the next finer one.
    static func sharpeningLevels(of image: CGImage, grid: TileGrid) -> [CGImage] {
        let tilePixels = Double(image.width) / Double(grid.columns)
        var counts: [Int] = []
        var (blocks, next) = (1, 2)
        while Double(blocks * 2) <= tilePixels, blocks <= 512 {
            counts.append(blocks)
            (blocks, next) = (next, blocks + next)
        }
        var levels: [CGImage] = []
        var source = image
        for blocks in counts.reversed() {
            let w = grid.columns * blocks, h = grid.rows * blocks
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
            ctx.interpolationQuality = .high
            ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let level = ctx.makeImage() else { return [] }
            levels.insert(level, at: 0)
            source = level
        }
        return levels
    }

    // MARK: Tiles

    private func build(_ tree: Tree) {
        guard let plan else { return }
        tree.tiles.forEach { $0.removeFromSuperlayer() }
        tree.tiles = []
        tree.blocks.forEach { $0.removeFromSuperlayer() }
        tree.blocks = []
        tree.picture.removeFromSuperlayer()

        if let quarters = plan.quarters {
            tree.blocks = quarters.colours.map { colour in
                let block = StillLayer()
                block.backgroundColor = colour.cgColor
                block.isHidden = true
                tree.grid.addSublayer(block)
                return block
            }
            tree.picture.contents = plan.image
            tree.picture.opacity = 0
            tree.grid.addSublayer(tree.picture)
            return
        }

        let grid = plan.schedule.grid
        // A reveal that sharpens opens on one flat colour; one that flips,
        // on nothing.
        let back = plan.reveal == .sharpen ? plan.average.cgColor : CGColor(gray: 0, alpha: 1)
        tree.tiles = (0..<grid.count).map { i in
            let tile = TileLayer()
            tile.picture = plan.image
            tile.front.contents = plan.image
            tile.front.contentsRect = Self.contentsRect(column: i % grid.columns, row: i / grid.columns, of: grid)
            tile.back.backgroundColor = back
            tree.grid.addSublayer(tile)
            return tile
        }
    }

    /// The share of the picture tile (column, row) shows. Core Animation
    /// measures contents from the image's bottom-left; rows count from the top.
    static func contentsRect(column: Int, row: Int, of grid: TileGrid) -> CGRect {
        let w = 1 / CGFloat(grid.columns), h = 1 / CGFloat(grid.rows)
        return CGRect(x: CGFloat(column) * w, y: CGFloat(grid.rows - 1 - row) * h, width: w, height: h)
    }

    private func apply(_ f: Int, animated: Bool) {
        guard let plan else { return }
        for tree in trees.values {
            if let quarters = plan.quarters {
                applyQuarters(quarters, plan: plan, tree: tree, f, animated: animated)
                continue
            }
            for (i, tile) in tree.tiles.enumerated() {
                let start = plan.schedule.starts[i]
                if plan.reveal == .show || f >= start + plan.flipFrames {
                    tile.finish()
                } else if f >= start {
                    switch plan.reveal {
                    case .flip:
                        tile.flip(duration: plan.flipDuration, animated: animated)
                    case .sharpen:
                        // Each level in turn, spread across the tile's time,
                        // and each for a frame at least: a time too short for
                        // them all leaves out the finest, the least missed.
                        let shown = min(plan.levels.count, plan.flipFrames)
                        let progress = Double(f - start) / Double(max(plan.flipFrames, 1))
                        let step = Int(progress * Double(shown))
                        if animated, step < shown {
                            tile.sharpen(to: plan.levels[step])
                        } else {
                            tile.finish()
                        }
                    case .show:
                        tile.finish()
                    }
                }
            }
        }
    }

    /// Quarters at frame `f`: every rectangle is shown from when its parent
    /// split until it splits itself, a pure function of the frame, so a jump
    /// or a late surface lands on the same picture. Then the finished picture
    /// comes up over the smallest.
    private func applyQuarters(_ quarters: Plan.Quarters, plan: Plan, tree: Tree, _ f: Int, animated: Bool) {
        for (node, block) in tree.blocks.enumerated() {
            let born = quarters.schedule.birthFrame(of: node)
            let split = quarters.schedule.splitFrame(of: node) ?? Int.max
            block.isHidden = !(f >= born && f < split)
        }
        let picture = tree.picture
        if f >= quarters.finalStart {
            guard picture.opacity < 1 else { return }
            picture.removeAllAnimations()
            picture.opacity = 1
            if animated, f < plan.settleFrame {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.toValue = 1
                fade.duration = plan.flipDuration
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                picture.add(fade, forKey: "come-up")
            }
        } else {
            picture.removeAllAnimations()
            picture.opacity = 0
        }
    }
}

/// One tile: a 3D layer holding a front face and a back face, each hidden
/// from behind, turning about its vertical axis.
final class TileLayer: CATransformLayer {
    enum State {
        /// Back face up.
        case waiting
        case flipping
        /// Front face up, and the back face hidden.
        case done
    }

    let front = StillLayer()
    let back = StillLayer()
    /// The tile's share of the picture, which the front shows when done.
    var picture: CGImage?
    private(set) var state = State.waiting

    override init() {
        super.init()
        for face in [back, front] {
            face.isDoubleSided = false
            addSublayer(face)
        }
        back.transform = CATransform3DMakeRotation(.pi, 0, 1, 0)
        // Waiting tiles show only their back. Faces that couldn't be seen are
        // hidden outright, which also keeps offscreen rendering honest.
        front.isHidden = true
        setValue(Double.pi, forKeyPath: "transform.rotation.y")
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func action(forKey event: String) -> (any CAAction)? {
        nil
    }

    func layoutFaces() {
        for face in [front, back] {
            face.bounds = bounds
            face.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }

    func flip(duration: CFTimeInterval, animated: Bool) {
        guard state == .waiting else { return }
        guard animated else {
            finish()
            return
        }
        state = .flipping
        front.isHidden = false
        setValue(0.0, forKeyPath: "transform.rotation.y")
        let turn = CABasicAnimation(keyPath: "transform.rotation.y")
        turn.fromValue = Double.pi
        turn.toValue = 0.0
        turn.duration = duration
        // The flip eases in slowly and lands softly: cubic-bezier(.35, 0, .25, 1).
        turn.timingFunction = CAMediaTimingFunction(controlPoints: 0.35, 0, 0.25, 1)
        add(turn, forKey: "flip")
    }

    /// One step of a sharpen: the front, square on, showing the picture in
    /// blocks, kept crisp rather than smoothed.
    func sharpen(to level: CGImage) {
        guard state != .done else { return }
        state = .flipping
        front.isHidden = false
        back.isHidden = true
        setValue(0.0, forKeyPath: "transform.rotation.y")
        front.contents = level
        front.magnificationFilter = .nearest
    }

    func finish() {
        guard state != .done else { return }
        state = .done
        front.isHidden = false
        back.isHidden = true
        setValue(0.0, forKeyPath: "transform.rotation.y")
        if let picture {
            front.contents = picture
            front.magnificationFilter = .linear
        }
    }
}
