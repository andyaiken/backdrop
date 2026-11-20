import BackdropCore
import CoreText
import QuartzCore

/// One card of a departures board, which a decryption cue's letters stand on
/// when that is how they find their way home: a dark card split across the middle on
/// two brass hinge pins, its glyph cut in two by the split, and while it
/// flips, the flap on its way down. A `TextLayer` draws its cards under its
/// runs.
struct FlapCard: Equatable {
    /// The glyph the card showed before the flap now falling.
    var from: String
    /// The glyph the falling flap brings: on the top half as soon as the flap
    /// lifts away from it, and on the lower half once the flap has landed.
    var to: String
    /// How far through the flip, from 0, at rest on `from`, towards 1.
    var phase: CGFloat
    var font: CTFont
    var colour: CGColor
    /// The left edge of the card's cell, and the cell's width. The card
    /// stands in the middle of it, a little narrower.
    var x: CGFloat
    var cell: CGFloat
    /// The brass hinge pins at either end of the split. Left off cards too
    /// small for them, where they would read as dots between the letters.
    var pins: Bool

    /// The share of its cell a card takes; the rest is the gap to the next.
    static let share: CGFloat = 0.9

    /// A card at rest on a glyph.
    init(_ glyph: String, font: CTFont, colour: CGColor, x: CGFloat, cell: CGFloat, pins: Bool = true) {
        self.init(from: glyph, to: glyph, phase: 0, font: font, colour: colour, x: x, cell: cell, pins: pins)
    }

    init(from: String, to: String, phase: CGFloat, font: CTFont, colour: CGColor, x: CGFloat, cell: CGFloat, pins: Bool = true) {
        self.from = from
        self.to = to
        self.phase = phase
        self.font = font
        self.colour = colour
        self.x = x
        self.cell = cell
        self.pins = pins
    }

    static func == (a: FlapCard, b: FlapCard) -> Bool {
        a.from == b.from && a.to == b.to && a.phase == b.phase && CFEqual(a.font, b.font) && a.colour == b.colour
            && a.x == b.x && a.cell == b.cell && a.pins == b.pins
    }

    /// Draws the card on a line whose baseline is `baseline` above its
    /// bottom edge, and which is `height` tall.
    func draw(in ctx: CGContext, baseline: CGFloat, height: CGFloat) {
        let em = CTFontGetSize(font)
        // The split runs through the middle of the capitals, as a board's
        // does, and the card reaches as far either side as the line lets it.
        let hinge = baseline + CTFontGetCapHeight(font) / 2
        let reach = max(0, min(hinge, height - hinge))
        let width = cell * Self.share
        let card = CGRect(x: x + (cell - width) / 2, y: hinge - reach, width: width, height: 2 * reach)
        let gap = max(1, 0.025 * em)
        let top = CGRect(x: card.minX, y: hinge + gap / 2, width: card.width, height: max(0, reach - gap / 2))
        let bottom = CGRect(x: card.minX, y: card.minY, width: card.width, height: max(0, reach - gap / 2))
        let corners = CGPath(roundedRect: card, cornerWidth: 0.07 * em, cornerHeight: 0.07 * em, transform: nil)

        /// One half of the card with its half of a glyph, squashed towards
        /// the hinge when it is the flap in flight, and darkened by `shade`.
        func face(_ rect: CGRect, _ glyph: String, squash: CGFloat = 1, shade: CGFloat = 0) {
            guard squash > 0.001, rect.height > 0 else { return }
            ctx.saveGState()
            ctx.translateBy(x: 0, y: hinge)
            ctx.scaleBy(x: 1, y: squash)
            ctx.translateBy(x: 0, y: -hinge)
            ctx.addPath(corners)
            ctx.clip()
            ctx.clip(to: rect)
            ctx.setFillColor(Palette.card.cgColor)
            ctx.fill(rect)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour,
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: glyph, attributes: attributes))
            let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            ctx.textPosition = CGPoint(x: x + (cell - advance) / 2, y: baseline)
            CTLineDraw(line, ctx)
            if shade > 0 {
                ctx.setFillColor(CGColor(gray: 0, alpha: min(shade, 1)))
                ctx.fill(rect)
            }
            ctx.restoreGState()
        }

        // The lower half sits a shade back, in the shadow of the flap above.
        let low: CGFloat = 0.14
        let turning = phase > 0 && phase < 1
        face(top, turning ? to : from)
        face(bottom, from, shade: low)
        if turning {
            // The flap: first the top half's face, tipping towards us and
            // foreshortened about the hinge; then, past upright, its back,
            // with the new glyph's lower half, coming down over the old. It
            // darkens the further it is from flat.
            let tilt = cos(phase * .pi)
            if tilt > 0 {
                face(top, from, squash: tilt, shade: 0.45 * (1 - tilt))
            } else {
                face(bottom, to, squash: -tilt, shade: low + 0.45 * (1 + tilt))
            }
        }

        // The hinge pins, brass, at either end of the split.
        guard pins else { return }
        let pin = CGSize(width: 0.05 * em, height: 0.1 * em)
        ctx.setFillColor(Palette.brass.cgColor)
        for left in [card.minX - pin.width / 2, card.maxX - pin.width / 2] {
            let rect = CGRect(x: left, y: hinge - pin.height / 2, width: pin.width, height: pin.height)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: pin.width * 0.3, cornerHeight: pin.width * 0.3, transform: nil))
        }
        ctx.fillPath()
    }
}
