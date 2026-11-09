import AppKit
import BackdropCore

/// Anagram cues: phrases whose letters lift out of line and travel to spell
/// others. Letters heading right arc over the line and letters heading left
/// dip under it, so the two streams pass without touching. Each warms from
/// slate to bone as it lands in the answer, as a decrypting title does.
///
/// A cue can hold several anagrams, stacked, solved one after another, and
/// each can show working on the way: steps that may be partial or wrong.
/// Working stays slate, and the letters a step doesn't use dim on a line
/// beneath it until a later step takes them up.
///
/// The model says which letter goes where and when it sets off
/// (`AnagramCuePlan`). The clock triggers each letter; the journey itself is
/// a Core Animation path with its own duration, as a tile's flip is, so it
/// runs smoothly between the clock's frames.
@MainActor
public final class AnagramRenderer: CueRenderer, ReportsProblems, WaitsForGO {
    public let isInstant = false
    public var onProblem: ((String) -> Void)?

    private var random: AnyUnitRandom
    private(set) var plan: AnagramCuePlan?
    /// When each part of the cue starts, as GO lets them go.
    private(set) var timeline = GoTimeline(parts: [0])
    private var clockSeconds = 0.044
    private var textScale = 100
    private var family = ""
    private(set) var lastFrame: Int?
    /// The first paint of a cue put up finished lands without animating.
    private var fresh = true
    /// The next paint follows a jump to a GO point, so the stage is placed
    /// as it stands then, with nothing animating into place.
    private var jumped = false
    private var trees: [ObjectIdentifier: Tree] = [:]

    /// How bright a letter is on the line of those a step leaves unused.
    static let dimmed = 0.4

    /// - Parameter random: The small extra delays on each letter. Tests pass
    ///   a seeded generator.
    public init(random: some UnitRandom = SystemUnitRandom()) {
        self.random = AnyUnitRandom(random)
    }

    /// One surface's layers.
    final class Tree {
        let surface: SurfaceLayer
        let root = StillLayer()
        /// Each anagram's letters.
        var tracks: [TrackLayers] = []
        var layout: AnagramLayout?

        init(surface: SurfaceLayer) {
            self.surface = surface
            root.isHidden = true
        }
    }

    /// One anagram's letters on a surface, built for the move it is showing
    /// and built again when the next sets off. The two meet exactly: a move's
    /// letters land where the next one's stand waiting.
    final class TrackLayers {
        var shown: Shown?
        var pieces: [PieceLayer] = []
    }

    /// What one anagram shows: a move from one of its steps to the next, or
    /// where it stands when the cue doesn't solve it.
    struct Shown: Equatable {
        var track: Int
        /// Nil for an anagram standing still.
        var move: Int?
        var plan: AnagramPlan
        /// The steps it goes from and to.
        var from: Int
        var to: Int
        /// Into the answer, so the letters warm to bone.
        var warms: Bool
        /// The frame it set off, or nil while it waits for GO or stands still.
        var start: Int?
        /// Standing still, solved already: in bone from the start.
        var solvedAlready = false
    }

    func tree(for surface: SurfaceLayer) -> Tree? {
        trees[ObjectIdentifier(surface)]
    }

    /// What anagram `t` shows on frame `f`.
    func shown(_ t: Int, at f: Int) -> Shown? {
        guard let plan, plan.tracks.indices.contains(t) else { return nil }
        let track = plan.tracks[t]
        guard let (index, start) = plan.shown(track, at: f, timeline: timeline) else {
            return Shown(track: t, move: nil, plan: track.still, from: 0, to: 0, warms: false, start: nil, solvedAlready: track.solvedAlready)
        }
        let move = track.moves[index]
        return Shown(track: t, move: index, plan: move.plan, from: index, to: index + 1, warms: move.warms, start: start)
    }

    // MARK: CueRenderer

    public func mount(on surface: SurfaceLayer) {
        let tree = Tree(surface: surface)
        trees[ObjectIdentifier(surface)] = tree
        surface.inset.addSublayer(tree.root)
        build(tree)
        fit(surface)
    }

    public func unmount(from surface: SurfaceLayer) {
        trees.removeValue(forKey: ObjectIdentifier(surface))?.root.removeFromSuperlayer()
    }

    public func setVisible(_ visible: Bool, on surface: SurfaceLayer) {
        tree(for: surface)?.root.isHidden = !visible
    }

    public func clear(_ surface: SurfaceLayer) {
        plan = nil
        timeline = .init(parts: [0])
        lastFrame = nil
        guard let tree = tree(for: surface) else { return }
        for track in tree.tracks { track.pieces.forEach { $0.removeFromSuperlayer() } }
        tree.tracks = []
    }

    public func prepare(_ cue: Cue, show: ShowSettings) {
        guard case .anagram(let content) = cue.content else { return }
        let settings = content.settings
        let plan = AnagramCuePlan(content.anagrams, wave: settings.waveTicks, pause: settings.pauseTicks, advance: settings.advance,
                                  random: &random)
        self.plan = plan
        timeline = .init(parts: plan.parts)
        clockSeconds = Double(settings.clockMs) / 1000
        textScale = show.textScale
        family = settings.font
        if !family.isEmpty, !StageFont.has(family: family) {
            let name = cue.number.isEmpty ? "This anagram" : "Cue \(cue.number)"
            onProblem?("\(name)\u{2019}s font, \(family), isn\u{2019}t on this Mac, so it shows in \(SettingKey.stageFont) instead.")
        }
        lastFrame = nil
        fresh = true
        for tree in trees.values {
            build(tree)
            fit(tree.surface)
        }
    }

    /// Text size is show-wide and only layout, so an anagram on stage refits
    /// straight away.
    public func settingsChanged(_ show: ShowSettings) {
        guard show.textScale != textScale else { return }
        textScale = show.textScale
        for tree in trees.values { fit(tree.surface) }
    }

    public func frame(_ f: Int) -> Bool {
        lastFrame = f
        guard plan != nil else { return true }
        let finished = timeline.isFinished(at: f)
        apply(f, animated: !(fresh && finished) && !jumped)
        fresh = false
        jumped = false
        return finished
    }

    public func fit(_ surface: SurfaceLayer) {
        guard let tree = tree(for: surface) else { return }
        let size = surface.inset.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        tree.root.frame = CGRect(origin: .zero, size: size)
        guard let plan else { return }
        let layout = AnagramLayout(size: size, plan: plan, textScale: textScale, family: family)
        tree.layout = layout
        for track in tree.tracks {
            guard let shown = track.shown else { continue }
            for (piece, layer) in zip(shown.plan.pieces, track.pieces) { dress(layer, as: piece, in: shown, layout: layout, scale: surface.contentsScale) }
        }
        // Anything mid-journey picks up from where the new layout puts it.
        apply(lastFrame ?? -1_000_000, animated: false)
    }

    // MARK: WaitsForGO

    public func isWaiting(at f: Int) -> Bool {
        plan != nil && timeline.isWaiting(at: f)
    }

    public func carryOn(at f: Int) {
        timeline.carryOn(at: f)
    }

    public func carryOnToEnd() {
        timeline.carryOnToEnd()
    }

    /// GO point k lets go part k + 1; part 0 runs from the cue's start.
    public func goTo(_ point: Int, at f: Int) {
        timeline.jump(toPart: point + 1, at: f)
        jumped = true
    }

    // MARK: Pieces

    private func build(_ tree: Tree) {
        for track in tree.tracks { track.pieces.forEach { $0.removeFromSuperlayer() } }
        tree.tracks = (plan?.tracks ?? []).map { _ in TrackLayers() }
    }

    /// Lays out a letter's two faces: as it stands before the move, in slate,
    /// and as it lands, in bone if it lands in the answer. One solved already
    /// stands in bone.
    private func dress(_ layer: PieceLayer, as piece: AnagramPlan.Piece, in shown: Shown, layout: AnagramLayout, scale: CGFloat) {
        layer.bounds = layout.box
        layer.morphs = piece.character != piece.landing
        let leaving = shown.solvedAlready ? Palette.bone : Palette.slate
        let landing = shown.warms || shown.solvedAlready ? Palette.bone : Palette.slate
        for (face, character, colour) in [(layer.before, piece.character, leaving), (layer.after, piece.landing, landing)] {
            face.contentsScale = scale
            face.frame = layer.bounds
            face.baseline = layout.boxBaseline
            face.runs = [TextRun(text: String(character), font: layout.font, colour: colour.cgColor, x: 0, cell: layout.box.width)]
        }
    }

    private func apply(_ f: Int, animated: Bool) {
        guard let plan else { return }
        for tree in trees.values {
            guard let layout = tree.layout else { continue }
            for (t, layers) in tree.tracks.enumerated() {
                guard let shown = shown(t, at: f) else { continue }
                // A new move sets off: its letters take over from the last's,
                // standing exactly where those landed.
                if layers.shown == nil || layers.shown?.move != shown.move {
                    layers.pieces.forEach { $0.removeFromSuperlayer() }
                    layers.pieces = shown.plan.pieces.map { piece in
                        let layer = PieceLayer()
                        dress(layer, as: piece, in: shown, layout: layout, scale: tree.surface.contentsScale)
                        tree.root.addSublayer(layer)
                        return layer
                    }
                }
                layers.shown = shown
                let steps = plan.tracks[t].steps
                // Frames since the move set off; long before, while it waits.
                let local = shown.start.map { f - $0 } ?? -1_000_000
                for (piece, layer) in zip(shown.plan.pieces, layers.pieces) {
                    place(layer, piece, at: local, in: shown, steps: steps, layout: layout, animated: animated)
                }
            }
        }
    }

    private func place(_ layer: PieceLayer, _ piece: AnagramPlan.Piece, at f: Int, in shown: Shown, steps: [AnagramCuePlan.Step],
                       layout: AnagramLayout, animated: Bool) {
        let p = shown.plan.progress(of: piece, at: f)
        let length = Double(piece.travels ? AnagramPlan.travelFrames : AnagramPlan.fadeFrames) * clockSeconds
        let elapsed = Double(f - piece.start) * clockSeconds
        // Full brightness, or dimmed among the letters a step leaves unused.
        let leaving = piece.from.map { steps[shown.from].isDim($0) ? Self.dimmed : 1 } ?? 0
        let arriving = piece.to.map { steps[shown.to].isDim($0) ? Self.dimmed : 1 } ?? 0
        if p >= 1 {
            layer.land(at: layout.end(of: piece, in: shown), opacity: arriving)
        } else if f < piece.start {
            layer.wait(at: layout.start(of: piece, in: shown), opacity: leaving, faded: piece.from == nil)
        } else if piece.travels, let from = piece.from, let to = piece.to {
            let path = layout.arc(from: from, to: to, in: shown)
            if animated {
                layer.travel(along: path, from: leaving, to: arriving, elapsed: elapsed, duration: length)
            } else {
                layer.step(to: path.point(at: p), progress: p, opacity: leaving + (arriving - leaving) * p)
            }
        } else {
            // Fading out where it began, or in where it lands.
            let point = layout.start(of: piece, in: shown)
            let fadingIn = piece.from == nil
            if animated {
                layer.fade(in: fadingIn, at: point, to: fadingIn ? arriving : leaving, elapsed: elapsed, duration: length)
            } else {
                layer.step(to: point, progress: fadingIn ? 1 : 0, opacity: fadingIn ? arriving * p : leaving * (1 - p))
            }
        }
    }
}
