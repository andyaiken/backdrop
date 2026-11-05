import AppKit
import CoreText
import ProspectCore

/// Where an anagram cue's letters go on a surface: every step of every
/// anagram in one size of type, so the letters keep their size as they
/// travel. The anagrams stack down the stage, each in a block with room for
/// its longest step, and each step's lines are centred in its block, so a
/// lone anagram's phrase and answer are each centred on the stage. Every
/// line is measured in its own font, so each letter starts and lands where
/// the font sets it, its own width and the kerning between letters included;
/// a monospaced font is one case. Measured in Core Animation's coordinates,
/// from the bottom.
@MainActor
struct AnagramLayout {
    let size: CGSize
    let font: CTFont
    let lineHeight: CGFloat
    /// One letter's layer, with room for any glyph's flourishes.
    let box: CGRect
    /// The baseline, above the bottom of a letter's box.
    let boxBaseline: CGFloat
    /// Every line of every step of every anagram: its width, and the middle
    /// of each of its characters from the line's left edge.
    private let steps: [[[Measured]]]
    /// Where each anagram's block begins, from the top, and how many lines
    /// it has room for.
    private let blocks: [(top: CGFloat, rows: Int)]

    /// Room between one anagram and the next, in lines.
    static let gap: CGFloat = 0.75

    struct Measured {
        var width: CGFloat
        var centres: [CGFloat]
    }

    init(size: CGSize, plan: AnagramCuePlan, textScale: Int, family: String = "") {
        self.size = size
        let W = size.width, H = size.height
        let padding = 4 * min(W, H) / 100
        let blockRows = plan.tracks.map { $0.steps.map(\.lines.count).max() ?? 0 }
        let rows = CGFloat(max(blockRows.reduce(0, +), 1)) + Self.gap * CGFloat(max(0, plan.tracks.count - 1))
        // SF Mono is opened out to a decryption's 0.72 em cells; a chosen
        // font gets a little air between its letters.
        let monospaced = family.isEmpty || !StageFont.has(family: family)
        func tracking(_ font: CTFont) -> CGFloat {
            let size = CTFontGetSize(font)
            return monospaced ? TitleLayout.cellEms * size - StageFont.advance(of: font) : 0.04 * size
        }
        let lines = plan.tracks.flatMap { $0.steps.flatMap(\.lines) }
        let reference = StageFont.anagram(family: family, size: 100)
        let widest = lines.map { Self.measure($0, font: reference, tracking: tracking(reference)).width }.max() ?? 0
        // As large as fits the width, with every line of every block in 70%
        // of the height and no line taller than a decryption's.
        let across = min(W * 0.88, (W - 2 * padding) * 0.9)
        let fit = min(widest > 0 ? across * 100 / widest : H, H * 0.28, H * 0.7 / (rows * 1.3))
        let fontSize = max(9, fit * CGFloat(textScale) / 100)
        let font = StageFont.anagram(family: family, size: fontSize)
        self.font = font
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        let lineHeight = max(fontSize * 1.3, (ascent + descent + CTFontGetLeading(font)) * 1.1)
        self.lineHeight = lineHeight
        box = CGRect(x: 0, y: 0, width: fontSize * 2, height: lineHeight * 1.6)
        boxBaseline = (box.height - lineHeight) / 2 + (lineHeight - ((lineHeight - (ascent + descent)) / 2 + ascent))
        let spacing = tracking(font)
        steps = plan.tracks.map { $0.steps.map { $0.lines.map { Self.measure($0, font: font, tracking: spacing) } } }
        var top = (H - rows * lineHeight) / 2
        blocks = blockRows.map { n in
            defer { top += (CGFloat(n) + Self.gap) * lineHeight }
            return (top, n)
        }
    }

    /// A line set in a font, `tracking` points apart: its width, and where
    /// the middle of each character's glyph falls, as Core Text sets them,
    /// kerning and any fallback font included.
    static func measure(_ text: String, font: CTFont, tracking: CGFloat) -> Measured {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): tracking,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var middles: [Int: CGFloat] = [:]
        var right: CGFloat = 0
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let n = CTRunGetGlyphCount(run)
            guard n > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: n), positions = [CGPoint](repeating: .zero, count: n)
            var indices = [CFIndex](repeating: 0, count: n), advances = [CGSize](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetPositions(run, CFRange(), &positions)
            CTRunGetStringIndices(run, CFRange(), &indices)
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String].map { $0 as! CTFont } ?? font
            CTFontGetAdvancesForGlyphs(runFont, .horizontal, glyphs, &advances, n)
            for k in 0..<n {
                // A glyph's own width, without the tracking set after it.
                if middles[indices[k]] == nil { middles[indices[k]] = positions[k].x + advances[k].width / 2 }
                right = max(right, positions[k].x + advances[k].width)
            }
        }
        var offset = 0, last: CGFloat = 0
        let centres = text.map { c -> CGFloat in
            // A character drawn as part of another's glyph, as in a
            // ligature, shares its middle.
            last = middles[offset] ?? last
            offset += String(c).utf16.count
            return last
        }
        return Measured(width: right, centres: centres)
    }

    /// Where a piece begins: its place in the step it leaves, or, for one
    /// that fades in, its place in the step it lands in.
    func start(of piece: AnagramPlan.Piece, in shown: AnagramRenderer.Shown) -> CGPoint {
        if let from = piece.from { return centre(of: from, track: shown.track, step: shown.from) }
        if let to = piece.to { return centre(of: to, track: shown.track, step: shown.to) }
        return CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// Where a piece ends: its place in the step it lands in, or, for one
    /// that fades out, where it stood.
    func end(of piece: AnagramPlan.Piece, in shown: AnagramRenderer.Shown) -> CGPoint {
        if let to = piece.to { return centre(of: to, track: shown.track, step: shown.to) }
        if let from = piece.from { return centre(of: from, track: shown.track, step: shown.from) }
        return CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// The middle of a character in one step of one anagram.
    func centre(of slot: AnagramPlan.Slot, track: Int, step: Int) -> CGPoint {
        guard steps.indices.contains(track), steps[track].indices.contains(step), steps[track][step].indices.contains(slot.line) else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        let lines = steps[track][step], line = lines[slot.line], block = blocks[track]
        let x = (size.width - line.width) / 2 + (line.centres.indices.contains(slot.column) ? line.centres[slot.column] : 0)
        let top = block.top + CGFloat(block.rows - lines.count) * lineHeight / 2
        let y = top + (CGFloat(slot.line) + 0.5) * lineHeight
        return CGPoint(x: x, y: size.height - y)
    }

    /// The way from a place in one step to a place in the next. The bow is a
    /// third of the distance across, kept between half a line and a line and
    /// a half.
    func arc(from: AnagramPlan.Slot, to: AnagramPlan.Slot, in shown: AnagramRenderer.Shown) -> Arc {
        let a = centre(of: from, track: shown.track, step: shown.from), b = centre(of: to, track: shown.track, step: shown.to)
        let dx = b.x - a.x
        let bow = dx == 0 ? 0 : min(max(abs(dx) / 3, lineHeight / 2), lineHeight * 1.5) * (dx > 0 ? 1 : -1)
        // A quadratic's control point sits twice as far out as its peak.
        let control = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 + 2 * bow)
        return Arc(start: a, control: control, end: b)
    }
}
