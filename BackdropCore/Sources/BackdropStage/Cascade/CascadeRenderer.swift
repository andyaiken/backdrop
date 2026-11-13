import AppKit
import BackdropCore
import CoreText
import QuartzCore

/// Cascade cues: glyphs raining down the picture in streaks, and a message
/// left behind as the rain clears.
///
/// The model works out each frame once (`CascadeCuePlan`); this draws it on
/// every surface. Thousands of glyphs change on every frame, far too many
/// for a layer each, so each surface's picture is drawn whole into a bitmap,
/// with the glyphs sorted by colour and drawn a colour at a time.
///
/// Rain with no message never settles: it keeps falling until the next cue,
/// and keeps falling when it is put up finished, too.
@MainActor
public final class CascadeRenderer: CueRenderer, WaitsForGO, KeepsMoving {
    public let isInstant = false

    /// The face the rain falls in. SF Mono has no katakana, and every Mac
    /// has Hiragino Sans.
    static let rainFontName = "HiraginoSans-W3"
    /// The levels a glyph's brightness is rounded to, so each level's glyphs
    /// can be drawn together.
    static let levels = 24
    /// The widest a picture is drawn, in pixels. A wider surface is drawn at
    /// this and scaled up.
    static let widest = 3840

    private var random: AnyUnitRandom
    private var plan: CascadeCuePlan?
    private var timeline = GoTimeline(parts: [0])
    /// Put up finished, so the rain is already falling rather than starting
    /// from the top.
    private var steady = false
    /// The frame on screen, kept so a resize or a newly mounted surface can
    /// draw it.
    private(set) var current: CascadeFrame?
    private var trees: [ObjectIdentifier: Tree] = [:]
    /// The glyphs of a frame, sorted into colours; kept between frames so
    /// they needn't be allocated afresh.
    private var batches: [Batch] = []

    /// - Parameter random: Where the plan's dice come from. Tests pass a
    ///   seeded generator.
    public init(random: some UnitRandom = SystemUnitRandom()) {
        self.random = AnyUnitRandom(random)
    }

    /// One surface's layers, and the bitmap its picture is drawn into.
    final class Tree {
        let surface: SurfaceLayer
        let root = StillLayer()
        let picture = StillLayer()
        var context: CGContext?
        var layout: Layout?
        /// Each letter of the message set once, in the size the letters take.
        var lines: [Character: (line: CTLine, centre: CGPoint)] = [:]

        init(surface: SurfaceLayer) {
            self.surface = surface
            root.isHidden = true
            picture.contentsGravity = .resize
            root.addSublayer(picture)
        }
    }

    /// Where the grid falls on one surface's bitmap, in its pixels, and the
    /// type that fills it.
    struct Layout {
        var width: Int
        var height: Int
        var cell: CGSize
        var rain: CTFont
        /// Each of `CascadeContent.glyphs`, in the rain's face.
        var glyphs: [CGGlyph]
        /// From a cell's centre to where each glyph is drawn from, so it
        /// sits in the middle of the cell.
        var offsets: [CGPoint]
        var letters: CTFont

        /// The middle of a cell. Rows count down from the top.
        func centre(column: Int, row: Int) -> CGPoint {
            CGPoint(x: (CGFloat(column) + 0.5) * cell.width, y: CGFloat(height) - (CGFloat(row) + 0.5) * cell.height)
        }
    }

    /// The glyphs of one colour, mirrored or not.
    struct Batch {
        var glyphs: [CGGlyph] = []
        var points: [CGPoint] = []
    }

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
        trees[ObjectIdentifier(surface)]?.root.isHidden = !visible
    }

    public func clear(_ surface: SurfaceLayer) {
        plan = nil
        timeline = GoTimeline(parts: [0])
        steady = false
        current = nil
        trees[ObjectIdentifier(surface)]?.picture.contents = nil
    }

    public func prepare(_ cue: Cue, show: ShowSettings) {
        guard case .cascade(let content) = cue.content else { return }
        // One shape for every surface, so they agree on the grid: the
        // biggest's, which is the projector's when it is open.
        var aspect = 16.0 / 9, biggest: CGFloat = 0
        for tree in trees.values {
            let size = tree.surface.inset.bounds.size
            guard size.height > 0, size.width * size.height > biggest else { continue }
            biggest = size.width * size.height
            aspect = Double(size.width / size.height)
        }
        let plan = CascadeCuePlan(content, aspect: aspect, random: &random)
        self.plan = plan
        timeline = GoTimeline(parts: plan.parts)
        steady = false
        current = nil
        for tree in trees.values { fit(tree.surface) }
    }

    public func frame(_ f: Int) -> Bool {
        guard let plan else { return true }
        let frame = plan.frame(f, timeline: timeline, steady: steady)
        current = frame
        for tree in trees.values { draw(frame, on: tree) }
        return frame.isSettled
    }

    public func fit(_ surface: SurfaceLayer) {
        guard let tree = trees[ObjectIdentifier(surface)] else { return }
        let size = surface.inset.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        tree.root.frame = CGRect(origin: .zero, size: size)
        tree.picture.frame = tree.root.bounds

        let scale = min(max(surface.contentsScale, 1), CGFloat(Self.widest) / size.width)
        let width = max(1, Int((size.width * scale).rounded())), height = max(1, Int((size.height * scale).rounded()))
        if tree.context?.width != width || tree.context?.height != height {
            tree.context = Self.bitmap(width: width, height: height)
        }
        guard let plan else {
            tree.layout = nil
            return
        }
        tree.layout = Self.layout(width: width, height: height, columns: plan.columns, rows: plan.rows)
        tree.lines = [:]
        if let current { draw(current, on: tree) }
    }

    // MARK: WaitsForGO

    /// Never: the rain keeps falling while the message waits for GO, so the
    /// clock must keep running.
    public func isWaiting(at f: Int) -> Bool { false }
    public func carryOn(at f: Int) { timeline.carryOn(at: f) }

    public func carryOnToEnd() {
        timeline.carryOnToEnd()
        steady = true
    }

    /// GO point 0 is the message, the cue's part 1.
    public func goTo(_ point: Int, at f: Int) { timeline.jump(toPart: point + 1, at: f) }

    // MARK: KeepsMoving

    public var keepsMoving: Bool { plan.map { !$0.hasMessage } ?? false }

    // MARK: Drawing

    private static func bitmap(width: Int, height: Int) -> CGContext? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        // Smoothing is for type on an opaque background; this is drawn on clear.
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSmoothing(false)
        return context
    }

    static func layout(width: Int, height: Int, columns: Int, rows: Int) -> Layout {
        let cell = CGSize(width: CGFloat(width) / CGFloat(columns), height: CGFloat(height) / CGFloat(rows))
        // Half-width katakana are about half an em wide and four fifths of
        // one tall.
        let size = min(cell.width * 1.45, cell.height * 1.1)
        let rain = (NSFont(name: rainFontName, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)) as CTFont
        var units = CascadeContent.glyphs.map { UniChar(String($0).utf16.first ?? 0) }
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        CTFontGetGlyphsForCharacters(rain, &units, &glyphs, units.count)
        var boxes = [CGRect](repeating: .zero, count: glyphs.count)
        CTFontGetBoundingRectsForGlyphs(rain, .horizontal, glyphs, &boxes, glyphs.count)
        let offsets = boxes.map { CGPoint(x: -$0.midX, y: -$0.midY) }
        // The message's letters a little larger: SF Mono is three fifths of
        // an em wide.
        let letters = StageFont.title(size: min(cell.width / 0.62, cell.height * 0.95))
        return Layout(width: width, height: height, cell: cell, rain: rain, glyphs: glyphs, offsets: offsets, letters: letters)
    }

    /// Where a glyph's batch is: its level, whether it is a head, and
    /// whether it is mirrored.
    private static func batch(level: Double, head: Bool, mirrored: Bool) -> Int {
        let k = min(levels, max(1, Int((level * Double(levels)).rounded(.up))))
        return ((head ? 1 : 0) * (levels + 1) + k) * 2 + (mirrored ? 1 : 0)
    }

    /// The colour of a batch: the cue's colour, faded towards its tail and
    /// whitening towards its head; a head near white.
    private static func colour(ofBatch b: Int, in colour: RGB) -> CGColor {
        let k = (b / 2) % (levels + 1), head = b / 2 > levels
        let level = Double(k) / Double(levels)
        let white = head ? 0.85 : max(0, level - 0.75) * 1.2
        return mix(colour, white: white, alpha: head ? level : pow(level, 1.4))
    }

    static func mix(_ c: RGB, white: Double, alpha: Double) -> CGColor {
        func channel(_ v: UInt8) -> CGFloat { CGFloat(Double(v) / 255 * (1 - white) + white) }
        return CGColor(srgbRed: channel(c.r), green: channel(c.g), blue: channel(c.b), alpha: CGFloat(alpha))
    }

    private func draw(_ frame: CascadeFrame, on tree: Tree) {
        guard let plan, let layout = tree.layout, let context = tree.context else { return }
        let bounds = CGRect(x: 0, y: 0, width: layout.width, height: layout.height)
        context.clear(bounds)
        // The text matrix isn't part of the graphics state, so restoring it
        // doesn't undo where the last letter left the text position, which
        // would move every glyph drawn after it.
        context.textMatrix = .identity

        let count = 2 * (Self.levels + 1) * 2
        if batches.count != count { batches = Array(repeating: Batch(), count: count) }
        for i in batches.indices {
            batches[i].glyphs.removeAll(keepingCapacity: true)
            batches[i].points.removeAll(keepingCapacity: true)
        }
        let width = CGFloat(layout.width)
        for g in frame.glyphs {
            let c = layout.centre(column: g.column, row: g.row)
            let offset = layout.offsets[g.glyph]
            // A mirrored glyph is drawn with the picture turned over, so
            // where it goes is measured from the other side.
            let x = (g.mirrored ? width - c.x : c.x) + offset.x
            let b = Self.batch(level: g.level, head: g.head, mirrored: g.mirrored)
            batches[b].glyphs.append(layout.glyphs[g.glyph])
            batches[b].points.append(CGPoint(x: x, y: c.y + offset.y))
        }
        for mirrored in [false, true] {
            context.saveGState()
            if mirrored {
                context.translateBy(x: width, y: 0)
                context.scaleBy(x: -1, y: 1)
            }
            for b in stride(from: mirrored ? 1 : 0, to: count, by: 2) where !batches[b].glyphs.isEmpty {
                context.setFillColor(Self.colour(ofBatch: b, in: plan.content.colour))
                CTFontDrawGlyphs(layout.rain, batches[b].glyphs, batches[b].points, batches[b].glyphs.count, context)
            }
            context.restoreGState()
        }

        // The letters glow a little, in the cue's colour, and cool from
        // white into a lighter shade of it.
        if !frame.letters.isEmpty {
            context.saveGState()
            context.setShadow(offset: .zero, blur: layout.cell.width * 0.6, color: Self.mix(plan.content.colour, white: 0, alpha: 0.8))
            for letter in frame.letters {
                let (line, centre) = typeset(letter.character, on: tree, layout: layout)
                let c = layout.centre(column: letter.column, row: letter.row)
                context.setFillColor(Self.mix(plan.content.colour, white: 1 - 0.7 * letter.cooled, alpha: 1))
                context.textPosition = CGPoint(x: c.x - centre.x, y: c.y - centre.y)
                CTLineDraw(line, context)
            }
            context.restoreGState()
        }
        tree.picture.contents = context.makeImage()
    }

    /// A letter of the message, set once for this surface, coloured by
    /// whatever the context fills with, and how far its middle is from where
    /// it is drawn from.
    private func typeset(_ character: Character, on tree: Tree, layout: Layout) -> (line: CTLine, centre: CGPoint) {
        if let done = tree.lines[character] { return done }
        let text = NSAttributedString(string: String(character), attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): layout.letters,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ])
        let line = CTLineCreateWithAttributedString(text)
        let box = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let set = (line, CGPoint(x: box.midX, y: box.midY))
        tree.lines[character] = set
        return set
    }
}
