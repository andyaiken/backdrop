import AppKit
import BackdropCore
import QuartzCore

/// Layered image cues: one picture assembled from full-frame layers that
/// arrive one at a time, each on its own GO.
///
/// Opacity, saturation and compositing are all Core Animation's own, so this
/// renderer paints nothing between the clock's frames. State is set, not
/// accumulated: painting step k asks `layers(after:)` for the standing set and
/// sets every layer to match, animated when the step is taken normally and
/// outright when the playhead has jumped. A false step is the same animation
/// with the target at zero.
@MainActor
public final class LayeredRenderer: CueRenderer, WaitsForGO, ReportsProblems {
    public let isInstant = false
    public var onProblem: ((String) -> Void)?

    private let loader: ImageLoader
    private let media: (String) -> URL?

    private var cue: Cue?
    private var content: LayeredContent?
    private var settings: LayeredSettings?
    private var token = 0
    private(set) var plan: Plan?
    private var lastFrame: Int?
    /// The step the layers stand at now, -1 for the base alone.
    private var shownStep = -1
    /// Set when the picture must be put straight to `shownStep` rather than
    /// animated to it: a jump, or a cue put up finished.
    private var snapping = true
    private var trees: [ObjectIdentifier: Tree] = [:]
    /// Whether the camera has pulled back out for the end of the cue.
    private var cameraSettled = false
    var onReady: (() -> Void)?
    private var pending: [(inout GoTimeline) -> Void] = []

    struct Plan {
        let cuePlan: LayeredCuePlan
        var timeline: GoTimeline
        let base: CGImage?
        /// Nil for a layer whose file is missing: it is skipped, its step still happens.
        let images: [CGImage?]
        let bounds: [PictureRect?]
        let edges: [CGImage?]
        let aspect: Double
        /// The frame at the end of each step.
        var frames: [PictureRect]
    }

    final class Tree {
        let surface: SurfaceLayer
        let root = StillLayer()
        /// The picture's own rect, which holds the base and every layer.
        let picture = StillLayer()
        /// Everything the camera moves: the base, the layers and what is drawn on them.
        let zoomer = StillLayer()
        let base = StillLayer()
        /// Each layer's picture, which moves as it arrives.
        var layers: [StillLayer] = []
        /// What holds each picture: the picture's whole rect, never moving,
        /// with its Core Image filters and its blend. A filter drawn on a
        /// layer that is moving shifts it by a pixel as it lands, so the
        /// filters stay out here and the motion stays inside.
        var holders: [StillLayer] = []
        var edges: [StillLayer] = []
        let spotlight = CAGradientLayer()

        init(surface: SurfaceLayer) {
            self.surface = surface
            root.isHidden = true
            root.addSublayer(picture)
            picture.masksToBounds = true
            picture.addSublayer(zoomer)
            zoomer.addSublayer(base)
            base.opacity = 0
            spotlight.type = .radial
            spotlight.opacity = 0
            spotlight.actions = ["opacity": NSNull()]
        }
    }

    public init(media: @escaping (String) -> URL? = { _ in nil }, loader: ImageLoader = ImageLoader()) {
        self.media = media
        self.loader = loader
    }

    func tree(for surface: SurfaceLayer) -> Tree? { trees[ObjectIdentifier(surface)] }

    // MARK: CueRenderer

    public func mount(on surface: SurfaceLayer) {
        let tree = Tree(surface: surface)
        trees[ObjectIdentifier(surface)] = tree
        surface.inset.addSublayer(tree.root)
        if plan != nil {
            build(tree)
            setState(after: shownStep, on: tree)
        }
        fit(surface)
    }

    public func unmount(from surface: SurfaceLayer) {
        trees.removeValue(forKey: ObjectIdentifier(surface))?.root.removeFromSuperlayer()
    }

    public func setVisible(_ visible: Bool, on surface: SurfaceLayer) {
        tree(for: surface)?.root.isHidden = !visible
    }

    public func clear(_ surface: SurfaceLayer) {
        token += 1
        cue = nil
        content = nil
        plan = nil
        pending = []
        lastFrame = nil
        shownStep = -1
        snapping = true
        guard let tree = tree(for: surface) else { return }
        tree.holders.forEach { $0.removeFromSuperlayer() }
        tree.edges.forEach { $0.removeFromSuperlayer() }
        tree.spotlight.removeFromSuperlayer()
        tree.layers = []
        tree.holders = []
        tree.edges = []
        tree.base.contents = nil
        tree.base.opacity = 0
        tree.zoomer.removeAllAnimations()
        tree.zoomer.transform = CATransform3DIdentity
    }

    public func prepare(_ cue: Cue, show: ShowSettings) {
        guard case .layered(let content) = cue.content else { return }
        token += 1
        self.cue = cue
        self.content = content
        let settings = content.settings
        self.settings = settings
        plan = nil
        pending = []
        lastFrame = nil
        shownStep = -1
        snapping = true
        let token = self.token

        // The whole set is asked for at once, so no layer is decoded halfway
        // through the speech.
        var base: CGImage?
        var images = [CGImage?](repeating: nil, count: content.layers.count)
        var outstanding = 1 + content.layers.count
        func done() {
            outstanding -= 1
            guard outstanding == 0, token == self.token else { return }
            self.ready(base: base, images: images)
        }
        load(content.base, what: "base picture", cue: cue) { image in base = image; done() }
        for (i, layer) in content.layers.enumerated() {
            load(layer.src, what: "layer \(i + 1), \(layer.displayName)", cue: cue) { image in images[i] = image; done() }
        }
    }

    public func frame(_ f: Int) -> Bool {
        lastFrame = f
        guard let plan else { return false }
        let reached = plan.cuePlan.reached(at: f, timeline: plan.timeline)
        let finished = plan.cuePlan.isFinished(at: f, timeline: plan.timeline)
        if snapping {
            // A jump, or a cue put up finished: straight to the picture, with
            // nothing animating. For a jump, the step it lands on is left to run.
            snapping = false
            shownStep = finished ? reached : reached - 1
            setState(after: shownStep, settled: finished)
            cameraSettled = finished
        }
        if reached > shownStep {
            // Whatever was missed, as while loading, lands outright; the
            // latest step animates.
            if reached - 1 > shownStep {
                shownStep = reached - 1
                setState(after: shownStep)
            }
            take(reached)
            shownStep = reached
        } else if reached < shownStep {
            shownStep = reached
            setState(after: reached)
        }
        if finished != cameraSettled {
            // The speech lands on the whole painting: the frame pulls back out.
            cameraSettled = finished
            if finished { moveCamera(to: LayeredFraming.whole, via: nil) }
        }
        return finished
    }

    public func fit(_ surface: SurfaceLayer) {
        guard let tree = tree(for: surface), let plan else { return }
        let W = surface.inset.bounds.width, H = surface.inset.bounds.height
        guard W > 0, H > 0 else { return }
        tree.root.frame = surface.inset.bounds
        // 90% of the stage, keeping the picture's shape, as an image cue does.
        let aspect = CGFloat(max(plan.aspect, 0.01))
        let w = min(W * 0.9, H * 0.9 * aspect).rounded(), h = (w / aspect).rounded()
        tree.picture.frame = CGRect(x: ((W - w) / 2).rounded(), y: ((H - h) / 2).rounded(), width: w, height: h)
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        tree.zoomer.bounds = full
        tree.zoomer.anchorPoint = CGPoint(x: 0, y: 1)
        tree.zoomer.position = CGPoint(x: 0, y: h)
        tree.base.frame = full
        for (i, layer) in tree.layers.enumerated() {
            tree.holders[i].frame = full
            place(layer, bounds: plan.bounds[i], in: tree.holders[i].bounds)
            place(tree.edges[i], bounds: plan.bounds[i], in: full)
        }
        tree.spotlight.frame = full
        if tree.zoomer.animation(forKey: "camera") == nil {
            tree.zoomer.transform = transform(for: frame(after: shownStep, settled: cameraSettled), in: tree)
        }
    }

    public func preload(_ cue: Cue, show: ShowSettings) {
        guard case .layered(let content) = cue.content else { return }
        for path in content.mediaPaths {
            guard let url = media(path) else { continue }
            loader.load(.file(url), maxPixels: maxPixels) { _ in }
        }
    }

    // MARK: WaitsForGO

    public func isWaiting(at f: Int) -> Bool { plan?.timeline.isWaiting(at: f) == true }

    public func carryOn(at f: Int) { change { $0.carryOn(at: f) } }

    public func carryOnToEnd() { change { $0.carryOnToEnd() } }

    /// GO point k lets go step k, in part k + 1; part 0 is the base standing.
    public func goTo(_ point: Int, at f: Int) {
        change { $0.jump(toPart: point + 1, at: f) }
        snapping = true
        shownStep = -2
    }

    /// Changes the timeline, or keeps the change for when the pictures have
    /// loaded and there is one: a cue put up at a GO point, or finished,
    /// is told so before it is ready.
    private func change(_ edit: @escaping (inout GoTimeline) -> Void) {
        if plan != nil { edit(&plan!.timeline) } else { pending.append(edit) }
    }

    // MARK: Loading

    private func load(_ path: String, what: String, cue: Cue, _ completion: @escaping (CGImage?) -> Void) {
        guard !path.isEmpty else { completion(nil); return }
        let name = (path as NSString).lastPathComponent
        guard let url = media(path) else {
            onProblem?("Cue \(cue.number)\u{2019}s \(what), \(name), is missing from the show, so it is left out.")
            completion(nil)
            return
        }
        loader.load(.file(url), maxPixels: maxPixels) { [weak self] result in
            switch result {
            case .success(let image): completion(image)
            case .failure(let failure):
                let why = failure.reason == .missing ? "is missing from the show" : "couldn\u{2019}t be read"
                self?.onProblem?("Cue \(cue.number)\u{2019}s \(what), \(name), \(why), so it is left out.")
                completion(nil)
            }
        }
    }

    /// The longest side, in pixels, any surface will show the picture at.
    var maxPixels: Int {
        // A camera that pushes in needs the picture that much wider, or it
        // softens; a still one pays nothing for it.
        let depth = settings.map { $0.camera == .still ? 1 : $0.zoom } ?? 1
        let needed = trees.values.map { tree -> CGFloat in
            let b = tree.surface.inset.bounds
            return max(b.width, b.height) * 0.9 * max(tree.surface.contentsScale, 1)
        }.max() ?? 2048
        let bucket = 512
        return min(max(Int((needed * CGFloat(depth) / CGFloat(bucket)).rounded(.up)) * bucket, 1024), 8192)
    }

    private func ready(base: CGImage?, images: [CGImage?]) {
        guard let content, let settings else { return }
        let cuePlan = LayeredCuePlan(content, settings: settings)
        var aspect = 16.0 / 9
        if let first = ([base] + images).compactMap({ $0 }).first {
            aspect = Double(first.width) / Double(max(first.height, 1))
        }
        // Registration is the artwork's: every layer is the base's size, or
        // its parts won't line up. Said once, and the layer still plays.
        if let cue, let reference = base ?? nil {
            let shape = Double(reference.width) / Double(max(reference.height, 1))
            for (i, image) in images.enumerated() {
                guard let image else { continue }
                let layerShape = Double(image.width) / Double(max(image.height, 1))
                if abs(layerShape / shape - 1) > 0.01 {
                    onProblem?("Cue \(cue.number)\u{2019}s layer \(i + 1), \(content.layers[i].displayName), isn\u{2019}t the same shape as the base picture, so it won\u{2019}t line up. Every layer must be the base\u{2019}s size.")
                }
            }
        }
        let wantsOutline = settings.entrance.contains(.outline) || content.layers.contains { $0.highlight?.entrance?.contains(.outline) == true }
        var built = Plan(
            cuePlan: cuePlan, timeline: GoTimeline(parts: cuePlan.parts), base: base, images: images,
            bounds: images.map { $0.flatMap { LayerImages.opaqueBounds(of: $0) } },
            edges: images.map { image in image.flatMap { wantsOutline ? LayerImages.edge(of: $0, colour: Palette.brass.cgColor(alpha: 1)) : nil } },
            aspect: aspect,
            frames: []
        )
        built.frames = content.frames(bounds: built.bounds, camera: settings.camera, zoom: settings.zoom)
        plan = built
        for edit in pending { edit(&plan!.timeline) }
        pending = []
        for tree in trees.values {
            build(tree)
            fit(tree.surface)
        }
        snapping = true
        shownStep = -2
        if let lastFrame { _ = frame(lastFrame) }
        onReady?()
    }

    // MARK: Layers

    private func build(_ tree: Tree) {
        guard let plan, let content else { return }
        tree.holders.forEach { $0.removeFromSuperlayer() }
        tree.edges.forEach { $0.removeFromSuperlayer() }
        tree.layers = []
        tree.holders = []
        tree.edges = []
        tree.base.contents = plan.base
        tree.base.opacity = 0
        for (i, layer) in content.layers.enumerated() {
            let h = StillLayer()
            // The blend goes with the filters, on the holder, so the picture
            // still blends with what is under it while a filter is on.
            switch layer.blend {
            case .normal: break
            case .screen: h.compositingFilter = "screenBlendMode"
            case .multiply: h.compositingFilter = "multiplyBlendMode"
            }
            let l = StillLayer()
            l.contents = plan.images[i]
            l.opacity = 0
            l.isHidden = plan.images[i] == nil
            h.addSublayer(l)
            tree.zoomer.addSublayer(h)
            tree.layers.append(l)
            tree.holders.append(h)
            let e = StillLayer()
            e.contents = plan.edges[i]
            e.opacity = 0
            tree.zoomer.addSublayer(e)
            tree.edges.append(e)
        }
        tree.zoomer.addSublayer(tree.spotlight)
    }

    /// Fills the picture's rect, but anchored at the centre of the layer's own
    /// part, so a magnified entrance settles about it rather than the middle.
    private func place(_ layer: StillLayer, bounds part: PictureRect?, in full: CGRect) {
        let cx = part.map { $0.x + $0.width / 2 } ?? 0.5, cy = part.map { $0.y + $0.height / 2 } ?? 0.5
        layer.bounds = CGRect(origin: .zero, size: full.size)
        // Core Animation measures from the bottom.
        layer.anchorPoint = CGPoint(x: cx, y: 1 - cy)
        layer.position = CGPoint(x: full.minX + full.width * cx, y: full.minY + full.height * (1 - cy))
    }

    private func level(_ layer: ImageLayer) -> Float { Float(layer.level ?? 100) / 100 }

    // MARK: State

    /// Every layer as it stands once step `k` has run, outright.
    private func setState(after k: Int, settled: Bool = false) {
        for tree in trees.values { setState(after: k, settled: settled, on: tree) }
    }

    private func setState(after k: Int, settled: Bool = false, on tree: Tree) {
        guard let content, let settings else { return }
        let standing = Set(content.layers(after: k))
        tree.base.removeAllAnimations()
        tree.base.opacity = Float(settings.baseLevel) / 100
        tree.base.filters = nil
        for (i, layer) in tree.layers.enumerated() {
            layer.removeAllAnimations()
            layer.transform = CATransform3DIdentity
            tree.holders[i].removeAllAnimations()
            tree.holders[i].filters = nil
            layer.opacity = standing.contains(i) ? level(content.layers[i]) : 0
            tree.edges[i].removeAllAnimations()
            tree.edges[i].opacity = 0
        }
        tree.spotlight.removeAllAnimations()
        tree.spotlight.opacity = 0
        tree.zoomer.removeAllAnimations()
        tree.zoomer.transform = transform(for: frame(after: k, settled: settled), in: tree)
    }

    /// Where the camera stands once step `k` has run: on its part, and once
    /// the cue has settled, pulled back out to the whole picture.
    private func frame(after k: Int, settled: Bool) -> PictureRect {
        guard let content, let plan, !settled else { return LayeredFraming.whole }
        return content.frame(after: k, frames: plan.frames)
    }

    /// The transform that makes the picture's rect show `frame`.
    private func transform(for frame: PictureRect, in tree: Tree) -> CATransform3D {
        let size = tree.picture.bounds.size
        let k = 1 / CGFloat(max(frame.width, 0.01))
        // Scaled about the top left, then slid so the frame's corner lands there.
        let affine = CGAffineTransform(scaleX: k, y: k)
            .concatenating(CGAffineTransform(translationX: -CGFloat(frame.x) * size.width * k, y: CGFloat(frame.y) * size.height * k))
        return CATransform3DMakeAffineTransform(affine)
    }

    /// Step `k` taken normally: what leaves goes briskly, what arrives comes
    /// up, and the layers already standing take the context treatment.
    private func take(_ k: Int) {
        guard let content, let settings, let plan, plan.cuePlan.steps.indices.contains(k) else { return }
        let step = plan.cuePlan.steps[k].step
        let standing = Set(content.layers(after: k - 1)).subtracting(step.leaving)
        let first = step.arriving.first.map { content.layers[$0] }
        let context = first?.highlight?.context ?? settings.context
        let contextSeconds = Double(settings.contextTicks * settings.clockMs) / 1000
        if settings.camera != .still, plan.frames.indices.contains(k) {
            moveCamera(to: plan.frames[k], via: settings.camera == .push ? LayeredFraming.whole : nil)
        }
        for tree in trees.values {
            for i in step.leaving {
                animate(tree.layers[i], to: 0, seconds: Double(plan.cuePlan.leaveMs(of: i)) / 1000)
            }
            for i in step.arriving where plan.images[i] != nil {
                let layer = content.layers[i]
                let entrance = layer.highlight?.entrance ?? settings.entrance
                enter(tree, i, layer, entrance: entrance, seconds: Double(plan.cuePlan.arriveMs(of: i)) / 1000)
            }
            // The first layer has nothing standing to treat but the base.
            guard !step.arriving.isEmpty, !standing.isEmpty, contextSeconds > 0, settings.contextLevel > 0 else { continue }
            treat(tree, context: context, standing: standing, arriving: step.arriving, seconds: contextSeconds,
                  strength: Float(settings.contextLevel) / 100, bounds: first.flatMap { _ in plan.bounds[step.arriving[0]] })
        }
    }

    /// The camera travelling to `frame`, by way of `via` if there is one: a
    /// push pulls back to the whole picture on the way, a travel goes straight.
    private func moveCamera(to frame: PictureRect, via: PictureRect?) {
        guard let settings else { return }
        let seconds = Double(settings.cameraMs) / 1000
        for tree in trees.values {
            let from = tree.zoomer.presentation()?.transform ?? tree.zoomer.transform
            let to = transform(for: frame, in: tree)
            tree.zoomer.removeAnimation(forKey: "camera")
            tree.zoomer.transform = to
            guard seconds > 0 else { continue }
            let a = CAKeyframeAnimation(keyPath: "transform")
            var values = [NSValue(caTransform3D: from)]
            if let via { values.append(NSValue(caTransform3D: transform(for: via, in: tree))) }
            values.append(NSValue(caTransform3D: to))
            a.values = values
            a.duration = seconds
            a.calculationMode = .linear
            a.timingFunctions = values.dropFirst().map { _ in CAMediaTimingFunction(name: .easeInEaseOut) }
            tree.zoomer.add(a, forKey: "camera")
        }
    }

    private func animate(_ layer: CALayer, to target: Float, seconds: Double) {
        let from = layer.presentation()?.opacity ?? layer.opacity
        layer.removeAnimation(forKey: "opacity")
        layer.opacity = target
        guard seconds > 0 else { return }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from
        a.toValue = target
        a.duration = seconds
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(a, forKey: "opacity")
    }

    /// How much larger than life a magnified part arrives before it eases
    /// back to size.
    static let magnification: CGFloat = 1.1
    /// How far a blooming part flares past itself, in stops of exposure.
    static let bloomStops = 1.0

    /// Layer `i` arriving: it fades up to its level, and the entrance's
    /// effects go with it, each on its own animation so any mix plays.
    private func enter(_ tree: Tree, _ i: Int, _ layer: ImageLayer, entrance: LayerEntrance, seconds: Double) {
        let l = tree.layers[i], e = tree.edges[i]
        animate(l, to: level(layer), seconds: seconds)
        let outlined = entrance.contains(.outline) && e.contents != nil
        if outlined {
            // The brass edge flares as the part comes up, then fades.
            e.removeAllAnimations()
            e.opacity = 0
            let k = CAKeyframeAnimation(keyPath: "opacity")
            k.values = [0, 1, 0]
            k.keyTimes = [0, 0.4, 1]
            k.duration = max(seconds * 2, 0.4)
            e.add(k, forKey: "outline")
        }
        if entrance.contains(.magnify) {
            // It comes up larger than life, about its own centre, held there
            // while it fades up so the magnification is seen; once it has
            // arrived it eases slowly back to where the faint base has it.
            // One move that never turns back. Its outline moves with it.
            let total = max(seconds * 2.5, 0.6)
            let k = CAKeyframeAnimation(keyPath: "transform.scale")
            k.values = [Self.magnification, Self.magnification, 1]
            k.keyTimes = [0, NSNumber(value: min(seconds / total, 0.9)), 1]
            k.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeInEaseOut)]
            k.duration = total
            l.add(k, forKey: "magnify")
            if outlined { e.add(k, forKey: "magnify") }
        }
        if entrance.contains(.bloom), let filter = CIFilter(name: "CIExposureAdjust") {
            // Brighter rather than more opaque, so a layer at full level
            // blooms too. It peaks as the part lands. On the holder, as the
            // picture may be magnifying.
            filter.name = "bloom"
            filter.setValue(0, forKey: kCIInputEVKey)
            let h = tree.holders[i]
            setFilter(filter, on: h)
            let k = CAKeyframeAnimation(keyPath: "filters.bloom.inputEV")
            k.values = [0, Self.bloomStops, 0]
            k.keyTimes = [0, 0.5, 1]
            k.duration = max(seconds * 1.6, 0.4)
            h.add(k, forKey: "bloom")
        }
    }

    /// Puts `filter` on the layer in place of any of the same name, keeping
    /// the others: a part still blooming can be drained of colour by the
    /// next one's arrival.
    private func setFilter(_ filter: CIFilter, on layer: CALayer) {
        layer.filters = (layer.filters ?? []).filter { ($0 as? CIFilter)?.name != filter.name } + [filter as Any]
    }

    /// What happens to the layers already standing while one arrives: a beat
    /// of the treatment, then everything comes back.
    private func treat(_ tree: Tree, context: LayerContext, standing: Set<Int>, arriving: [Int], seconds: Double,
                       strength: Float, bounds: PictureRect?) {
        switch context {
        case .none:
            return
        case .dim:
            let targets: [(CALayer, Float)] = [(tree.base, tree.base.opacity)] + standing.map { (tree.layers[$0], tree.layers[$0].opacity) }
            for (layer, rest) in targets where rest > 0 {
                let k = CAKeyframeAnimation(keyPath: "opacity")
                k.values = [rest, rest * (1 - strength), rest]
                k.keyTimes = [0, 0.25, 1]
                k.duration = seconds
                layer.add(k, forKey: "context")
            }
        case .desaturate:
            // On the holders: a layer standing may still be magnifying.
            let layers = [tree.base] + standing.map { tree.holders[$0] }
            for layer in layers {
                // The animation finds the filter by this name, one to a layer.
                guard let filter = CIFilter(name: "CIColorControls") else { return }
                filter.name = "colorControls"
                setFilter(filter, on: layer)
                let k = CAKeyframeAnimation(keyPath: "filters.colorControls.inputSaturation")
                k.values = [1, 1 - strength, 1]
                k.keyTimes = [0, 0.25, 1]
                k.duration = seconds
                layer.add(k, forKey: "context")
            }
        case .spotlight:
            let part = bounds ?? PictureRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
            let centre = CGPoint(x: part.x + part.width / 2, y: 1 - (part.y + part.height / 2))
            let reach = CGFloat(max(part.width, part.height) * 0.75 + 0.15)
            tree.spotlight.colors = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: CGFloat(strength))]
            tree.spotlight.locations = [0, 0.5, 1]
            tree.spotlight.startPoint = centre
            tree.spotlight.endPoint = CGPoint(x: centre.x + reach, y: centre.y + reach)
            let k = CAKeyframeAnimation(keyPath: "opacity")
            k.values = [0, 1, 0]
            k.keyTimes = [0, 0.25, 1]
            k.duration = seconds
            tree.spotlight.add(k, forKey: "context")
        }
    }
}
