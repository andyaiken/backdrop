import AppKit
import BackdropCore
import QuartzCore

/// Map cues: a police tracking terminal. The map, treated to phosphor green,
/// slides beneath a blinking red dot fixed at the middle of the stage as the
/// dot follows its route; a fading red trail marks where it has been. A jump
/// loses the signal, cuts to the new place and finds it again. Text types
/// itself out: the cue's own header, the status, the place, and the live
/// coordinates.
///
/// The model (`MapCuePlan`) says where everything is at any moment; this
/// lays the layers out to match, on every display refresh, so the map
/// slides smoothly. Stops can wait for GO, as an anagram's steps can.
@MainActor
public final class MapRenderer: PaintsBetweenFrames, ReportsProblems, WaitsForGO {
    public let isInstant = false
    public var onProblem: ((String) -> Void)?

    private let media: (String) -> URL?
    private let loader: ImageLoader

    /// What a prepared cue draws.
    struct Plan {
        var cue: MapCuePlan
        let content: MapContent
        let settings: MapSettings
        let number: String
        var timeline: GoTimeline
        /// The treated map, once it is here.
        var map: CGImage?
        /// Width over height, from the map once loaded.
        var aspect: Double
        /// Nothing more to wait for: the map arrived, or there is none.
        var isReady: Bool
    }

    private(set) var plan: Plan?
    /// What was last painted.
    private(set) var state: MapCuePlan.State?
    private var lastPosition: Double?
    private var token = 0
    private var trees: [ObjectIdentifier: Tree] = [:]
    /// Treated maps, by path and size: the one on stage and the one coming.
    private var treated: [String: CGImage] = [:]
    private var treating: [String: [(CGImage?) -> Void]] = [:]

    /// Called when a cue's map is ready to draw.
    public var onReady: (() -> Void)?

    public init(media: @escaping (String) -> URL? = { _ in nil }, loader: ImageLoader = ImageLoader()) {
        self.media = media
        self.loader = loader
    }

    /// One surface's layers, bottom to top.
    final class Tree {
        let surface: SurfaceLayer
        let root = StillLayer()
        let map = StillLayer()
        /// The trail in bands, oldest and faintest first.
        let trail: [CAShapeLayer]
        let ring = CAShapeLayer()
        let dot = CAShapeLayer()
        let overlay = StillLayer()
        let header = TextLayer()
        let coordinates = TextLayer()
        let status = TextLayer()
        let place = TextLayer()
        var overlaySize = CGSize.zero
        var fonts: (small: CTFont, status: CTFont)?

        init(surface: SurfaceLayer) {
            self.surface = surface
            root.isHidden = true
            root.backgroundColor = CGColor(gray: 0, alpha: 1)
            root.masksToBounds = true
            map.contentsGravity = .resize
            map.magnificationFilter = .linear
            map.minificationFilter = .trilinear
            trail = (0..<MapRenderer.bands).map { _ in CAShapeLayer() }
            // Square ends where one band meets the next, so they don't
            // overlap into beads.
            for band in trail {
                band.fillColor = nil
                band.strokeColor = MapLook.dot.cgColor
                band.lineCap = .butt
                band.lineJoin = .round
            }
            // Text reads over a bright road.
            for text in [header, coordinates, status, place] {
                text.shadowColor = CGColor(gray: 0, alpha: 1)
                text.shadowOpacity = 0.9
                text.shadowRadius = 4
                text.shadowOffset = .zero
            }
            ring.fillColor = nil
            ring.strokeColor = MapLook.dot.cgColor
            dot.fillColor = MapLook.dot.cgColor
            dot.shadowColor = MapLook.dot.cgColor
            dot.shadowOffset = .zero
            for layer in [map] + trail + [ring, dot, overlay, header, coordinates, status, place] as [CALayer] {
                layer.actions = ["position": NSNull(), "bounds": NSNull(), "path": NSNull(), "opacity": NSNull(), "contents": NSNull(),
                                 "hidden": NSNull(), "lineWidth": NSNull(), "shadowRadius": NSNull(), "shadowOpacity": NSNull()]
                root.addSublayer(layer)
            }
        }
    }

    nonisolated static let bands = 10

    func tree(for surface: SurfaceLayer) -> Tree? {
        trees[ObjectIdentifier(surface)]
    }

    // MARK: CueRenderer

    public func mount(on surface: SurfaceLayer) {
        let tree = Tree(surface: surface)
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

    public func clear(_ surface: SurfaceLayer) {
        token += 1
        plan = nil
        state = nil
        lastPosition = nil
        guard let tree = tree(for: surface) else { return }
        tree.map.contents = nil
        tree.dot.isHidden = true
        tree.ring.isHidden = true
        tree.trail.forEach { $0.path = nil }
        for text in [tree.header, tree.coordinates, tree.status, tree.place] { text.runs = [] }
    }

    public func prepare(_ cue: Cue, show: ShowSettings) {
        guard case .map(let content) = cue.content else { return }
        token += 1
        let settings = content.settings
        plan = Plan(cue: MapCuePlan(content, settings: settings), content: content, settings: settings, number: cue.number,
                    timeline: GoTimeline(parts: MapCuePlan(content, settings: settings).parts), map: nil, aspect: 1, isReady: content.src.isEmpty)
        state = nil
        lastPosition = nil
        for tree in trees.values { tree.map.contents = nil }
        guard !content.src.isEmpty else { return }
        guard let url = media(content.src) else {
            plan?.isReady = true
            onProblem?("Cue \(cue.number)\u{2019}s map, \((content.src as NSString).lastPathComponent), is missing from the show, so its dot moves over black.")
            return
        }
        let token = self.token, needed = neededPixels(zoom: settings.zoom), maxPixels = Self.bucket(needed)
        map(url, path: content.src, maxPixels: maxPixels) { [weak self] image, original in
            guard let self, token == self.token else { return }
            guard let image else {
                plan?.isReady = true
                onProblem?("Cue \(cue.number)\u{2019}s map, \((content.src as NSString).lastPathComponent), couldn\u{2019}t be read, so its dot moves over black.")
                repaint()
                return
            }
            plan?.map = image
            plan?.aspect = Double(image.width) / Double(max(image.height, 1))
            if let plan { self.plan?.cue = MapCuePlan(plan.content, settings: plan.settings, aspect: plan.aspect) }
            // As large as it is drawn; held still round a short route, that
            // can be less than Zoom.
            let wanted = min(drawnPixels(), needed)
            if let original, original < Int(Double(min(wanted, Self.largest)) * 0.75) {
                let how = settings.camera == .follow ? "At Zoom \(settings.zoom)\u{00D7}" : "Held still round its route"
                onProblem?("Cue \(cue.number)\u{2019}s map is \(original) pixels across. \(how) it wants about \(wanted) to stay sharp on the projector.")
            }
            plan?.isReady = true
            for tree in trees.values { tree.map.contents = image }
            repaint()
            onReady?()
        }
    }

    public func preload(_ cue: Cue, show: ShowSettings) {
        guard case .map(let content) = cue.content, !content.src.isEmpty, let url = media(content.src) else { return }
        let settings = content.settings
        map(url, path: content.src, maxPixels: Self.bucket(neededPixels(zoom: settings.zoom))) { _, _ in }
    }

    /// The treated map: from the cache, or decoded and treated off the main
    /// thread. With it, how wide the picture is, when it was decoded smaller
    /// than asked, or nil when it is as wide as asked.
    private func map(_ url: URL, path: String, maxPixels: Int, then: @escaping (CGImage?, Int?) -> Void) {
        let key = "\(path)@\(maxPixels)"
        if let image = treated[key] {
            then(image, image.width < maxPixels && image.height < maxPixels ? image.width : nil)
            return
        }
        if treating[key] != nil {
            treating[key]?.append { then($0, $0.flatMap { $0.width < maxPixels && $0.height < maxPixels ? $0.width : nil }) }
            return
        }
        treating[key] = [{ then($0, $0.flatMap { $0.width < maxPixels && $0.height < maxPixels ? $0.width : nil }) }]
        loader.load(.file(url), maxPixels: maxPixels) { [weak self] result in
            guard let self else { return }
            guard case .success(let decoded) = result else {
                finish(key, nil)
                return
            }
            Task.detached(priority: .userInitiated) {
                let image = MapTreatment.treat(decoded)
                await MainActor.run { [weak self] in self?.finish(key, image) }
            }
        }
    }

    private func finish(_ key: String, _ image: CGImage?) {
        if let image {
            // The map on stage and the one coming are all that are kept.
            if treated.count >= 2, let oldest = treated.keys.first { treated.removeValue(forKey: oldest) }
            treated[key] = image
        }
        for then in treating.removeValue(forKey: key) ?? [] { then(image) }
    }

    /// The pixels across the map is drawn at, on the widest surface, as the
    /// prepared cue frames it.
    private func drawnPixels() -> Int {
        guard let plan else { return 0 }
        let start = plan.cue.state(at: plan.cue.startMs / Double(plan.cue.clockMs), timeline: plan.timeline)
        return trees.values.map { tree -> Int in
            let bounds = tree.surface.inset.bounds.size
            return Int(frame(start, in: bounds).size.width * max(tree.surface.contentsScale, 1))
        }.max() ?? 0
    }

    /// The pixels across the map is drawn at on the widest surface.
    private func neededPixels(zoom: Int) -> Int {
        let widest = trees.values.map { $0.surface.inset.bounds.width * max($0.surface.contentsScale, 1) }.max() ?? 1920
        return Int(widest) * zoom
    }

    /// The most the map is decoded at, across.
    static let largest = 8192

    /// Rounded up so nearby sizes share a decode, and no larger than the
    /// graphics can hold comfortably.
    static func bucket(_ pixels: Int) -> Int {
        min(max(Int((Double(pixels) / 512).rounded(.up)) * 512, 1024), largest)
    }

    public func frame(_ f: Int) -> Bool {
        paint(at: Double(f))
    }

    public func paint(at position: Double) -> Bool {
        guard let plan else { return true }
        lastPosition = position
        let state = plan.cue.state(at: position, timeline: plan.timeline)
        self.state = state
        for tree in trees.values { draw(tree, state: state, at: position) }
        // Not finished while the map is on its way, so nothing continues
        // from a black stage.
        return plan.isReady && plan.cue.isFinished(at: position, timeline: plan.timeline)
    }

    private func repaint() {
        if let lastPosition { _ = paint(at: lastPosition) }
    }

    public func fit(_ surface: SurfaceLayer) {
        guard let tree = tree(for: surface) else { return }
        let bounds = surface.inset.bounds
        tree.root.frame = bounds
        let scale = max(surface.contentsScale, 1)
        for layer in [tree.overlay, tree.header, tree.coordinates, tree.status, tree.place] as [CALayer] { layer.contentsScale = scale }
        tree.overlay.frame = bounds
        if tree.overlaySize != bounds.size {
            tree.overlaySize = bounds.size
            tree.overlay.contents = MapTreatment.overlay(width: Int(bounds.width * scale), height: Int(bounds.height * scale), scale: scale)
        }
        let h = bounds.height
        tree.fonts = (StageFont.text(size: (h * 0.032).rounded()), StageFont.title(size: (h * 0.05).rounded()))
        if let state, let lastPosition { draw(tree, state: state, at: lastPosition) }
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

    /// GO point k lets the dot go to stop k + 1, in part k + 1; part 0 is
    /// the dot at its start.
    public func goTo(_ point: Int, at f: Int) {
        plan?.timeline.jump(toPart: point + 1, at: f)
    }

    // MARK: Drawing

    /// Where a point on the map is on the stage, measured from the bottom
    /// left as Core Animation measures, with `view` at the middle.
    static func place(_ p: PicturePoint, view: PicturePoint, map: CGSize, in bounds: CGSize) -> CGPoint {
        CGPoint(x: bounds.width / 2 + (p.x - view.x) * map.width, y: bounds.height / 2 - (p.y - view.y) * map.height)
    }

    /// How large the map is drawn: zoom stage widths across, its own shape.
    static func mapSize(zoom: Int, aspect: Double, in bounds: CGSize) -> CGSize {
        let width = bounds.width * CGFloat(max(zoom, 1))
        return CGSize(width: width, height: width / CGFloat(max(aspect, 0.01)))
    }

    /// The point on the map at the middle of the stage, and how large the
    /// map is drawn: following the dot, the dot's place at Zoom; holding
    /// still, the frame round the route.
    func frame(_ state: MapCuePlan.State, in bounds: CGSize) -> (view: PicturePoint, size: CGSize) {
        guard let plan else { return (state.view, bounds) }
        switch plan.settings.camera {
        case .follow:
            return (state.view, Self.mapSize(zoom: plan.settings.zoom, aspect: plan.aspect, in: bounds))
        case .still:
            let still = plan.cue.stillView(stageAspect: bounds.width / max(bounds.height, 1))
            let width = bounds.width / CGFloat(max(still.width, 0.0001))
            return (still.centre, CGSize(width: width, height: width / CGFloat(plan.aspect)))
        }
    }

    private func draw(_ tree: Tree, state: MapCuePlan.State, at position: Double) {
        guard let plan, let fonts = tree.fonts else { return }
        let bounds = tree.root.bounds.size
        guard bounds.width > 0, bounds.height > 0 else { return }
        let (view, size) = frame(state, in: bounds)
        let corner = Self.place(PicturePoint(x: 0, y: 1), view: view, map: size, in: bounds)
        tree.map.frame = CGRect(origin: corner, size: size)
        if tree.map.contents == nil, let map = plan.map { tree.map.contents = map }

        let ms = plan.cue.ms(at: position), since = ms - plan.cue.startMs
        let radius = (bounds.height * 0.011).rounded(.up)

        // The trail, in bands by age, each joined to the next.
        let samples = plan.cue.trail(at: position, timeline: plan.timeline, seconds: plan.settings.trailSeconds)
        let points = samples.map { Self.place($0.point, view: view, map: size, in: bounds) }
        for (band, layer) in tree.trail.enumerated() {
            let low = 1 - Double(band + 1) / Double(Self.bands), high = 1 - Double(band) / Double(Self.bands)
            let indices = samples.indices.filter { samples[$0].age > low && samples[$0].age <= high || (band == Self.bands - 1 && samples[$0].age == 0) }
            guard let first = indices.first, let last = indices.last else {
                layer.path = nil
                continue
            }
            let path = CGMutablePath()
            path.move(to: points[first])
            for i in first...min(last + 1, points.count - 1) where i > first { path.addLine(to: points[i]) }
            layer.path = path
            layer.lineWidth = radius * 0.7
            layer.opacity = Float(0.85 * pow(1 - (low + high) / 2, 1.2))
        }

        // The dot, lighting hard once a second, and its ring: at the middle
        // when the view follows it.
        let centre = Self.place(state.dot, view: view, map: size, in: bounds)
        let brightness = MapPulse.brightness(at: since)
        tree.dot.isHidden = !state.dotVisible
        tree.dot.path = CGPath(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2), transform: nil)
        tree.dot.opacity = Float(brightness)
        tree.dot.shadowRadius = radius * 1.6
        tree.dot.shadowOpacity = Float(brightness)
        if state.dotVisible, let spread = MapPulse.ring(at: since) {
            let r = radius * (1 + 5 * spread)
            tree.ring.isHidden = false
            tree.ring.path = CGPath(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2), transform: nil)
            tree.ring.lineWidth = max(1, bounds.height * 0.003)
            tree.ring.opacity = Float(0.9 * pow(1 - spread, 1.5))
        } else {
            tree.ring.isHidden = true
        }

        // The text: the header and coordinates along the top, the status and
        // the place at the bottom left.
        let margin = (bounds.height * 0.05).rounded(), small = fonts.small, big = fonts.status
        let bright = MapLook.phosphor.cgColor, dim = MapLook.dimPhosphor.cgColor
        let smallHeight = StageFont.normalLineHeight(of: small).rounded(.up), bigHeight = StageFont.normalLineHeight(of: big).rounded(.up)
        func set(_ layer: TextLayer, _ runs: [TextRun], top: CGFloat, height: CGFloat, font: CTFont) {
            layer.frame = CGRect(x: 0, y: bounds.height - top - height, width: bounds.width, height: height)
            layer.baseline = CTFontGetDescent(font).rounded(.up)
            layer.runs = runs
        }
        // A block cursor after whatever is still typing, and after the
        // status once it has, blinking.
        let cursorOn = since.truncatingRemainder(dividingBy: 1000) < 500
        func typed(_ line: MapCuePlan.Line, cursor: Bool) -> String {
            line.typed(at: ms) + (cursor && (line.isTyping(at: ms) || cursorOn) ? "\u{2588}" : "")
        }
        set(tree.header, [TextRun(text: typed(state.header, cursor: state.header.isTyping(at: ms)), font: small, colour: bright, x: margin)],
            top: margin, height: smallHeight, font: small)
        let coordinates: String? = plan.content.reference.map { reference in
            guard state.signal != .lost, let c = reference.coordinates(of: state.dot) else { return MapReference.lost }
            return MapReference.format(latitude: c.latitude, longitude: c.longitude)
        }
        if let coordinates {
            let width = CGFloat(coordinates.count) * StageFont.advance(of: small)
            set(tree.coordinates, [TextRun(text: coordinates, font: small, colour: dim, x: bounds.width - margin - width)],
                top: margin, height: smallHeight, font: small)
        } else {
            tree.coordinates.runs = []
        }
        // SIGNAL LOST flashes.
        let flashing = state.signal == .lost && since.truncatingRemainder(dividingBy: 500) >= 250
        let statusText = flashing ? "" : typed(state.status, cursor: true)
        let placeTop = bounds.height - margin - smallHeight
        set(tree.status, [TextRun(text: statusText, font: big, colour: bright, x: margin)], top: placeTop - bigHeight - smallHeight * 0.2,
            height: bigHeight, font: big)
        set(tree.place, [TextRun(text: typed(state.place, cursor: false), font: small, colour: dim, x: margin)], top: placeTop,
            height: smallHeight, font: small)
    }

    #if DEBUG
    /// Whether a map is drawn, for tests.
    var hasMap: Bool { plan?.map != nil }
    #endif
}
