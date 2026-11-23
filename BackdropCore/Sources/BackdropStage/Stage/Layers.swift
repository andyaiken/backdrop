import CoreText
import Foundation
import QuartzCore

/// A layer with no implicit animations. Everything on stage changes when the
/// clock says so, and not over a quarter of a second afterwards. The few
/// things that do animate, such as histogram bars, add their animations
/// explicitly.
public class StillLayer: CALayer {
    override public func action(forKey event: String) -> (any CAAction)? {
        nil
    }
}

/// A run of text drawn at a position on its layer's baseline.
struct TextRun: Equatable {
    var text: String
    var font: CTFont
    var colour: CGColor
    /// The run's left edge, or the left edge of the cell it is centred in.
    var x: CGFloat
    /// Centre the run in a cell this wide, rather than starting it at `x`.
    var cell: CGFloat?
    /// Raised this far above the baseline, or below it when negative, as a
    /// letter on a dial is while it turns.
    var dy: CGFloat = 0
    /// Drawn instead of the text: a shape in em units, `GlyphMorph.unitsPerEm`
    /// to the em, from where the glyph's origin would be, as a letter
    /// partway through a morph is. The text stays, for what it stands for.
    var shape: CGPath?

    static func == (a: TextRun, b: TextRun) -> Bool {
        a.text == b.text && CFEqual(a.font, b.font) && a.colour == b.colour && a.x == b.x && a.cell == b.cell && a.dy == b.dy
            && sameShape(a.shape, b.shape)
    }

    /// Both none, or the same elements, point for point.
    private static func sameShape(_ a: CGPath?, _ b: CGPath?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): CFEqual(a, b)
        default: false
        }
    }
}

/// Draws positioned runs of text with Core Text. Every line on stage is one
/// of these, so each glyph lands exactly where layout put it, one character
/// to a run where the reveal needs that.
final class TextLayer: StillLayer {
    var runs: [TextRun] = [] {
        didSet { if runs != oldValue { setNeedsDisplay() } }
    }

    /// The cards of a departures board, drawn under the runs, for a
    /// decryption whose letters are on one.
    var cards: [FlapCard] = [] {
        didSet { if cards != oldValue { setNeedsDisplay() } }
    }

    /// Distance of the baseline above the layer's bottom edge.
    var baseline: CGFloat = 0 {
        didSet { if baseline != oldValue { setNeedsDisplay() } }
    }

    override init() {
        super.init()
        needsDisplayOnBoundsChange = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? TextLayer {
            runs = other.runs
            cards = other.cards
            baseline = other.baseline
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(in ctx: CGContext) {
        ctx.textMatrix = .identity
        for card in cards {
            card.draw(in: ctx, baseline: baseline, height: bounds.height)
        }
        for run in runs {
            if let shape = run.shape {
                // Placed as the glyph would be: in a cell, centred by the
                // type's one advance.
                var x = run.x
                if let cell = run.cell { x += (cell - StageFont.advance(of: run.font)) / 2 }
                let scale = CTFontGetSize(run.font) / GlyphMorph.unitsPerEm
                ctx.saveGState()
                ctx.translateBy(x: x, y: baseline + run.dy)
                ctx.scaleBy(x: scale, y: scale)
                ctx.addPath(shape)
                ctx.setFillColor(run.colour)
                ctx.fillPath(using: .winding)
                ctx.restoreGState()
                continue
            }
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): run.font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): run.colour,
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: run.text, attributes: attributes))
            var x = run.x
            if let cell = run.cell {
                x += (cell - CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))) / 2
            }
            ctx.textPosition = CGPoint(x: x, y: baseline + run.dy)
            CTLineDraw(line, ctx)
        }
    }
}

extension CGRect {
    /// Converts a rectangle laid out from the top, as the title layout
    /// measures, into Core Animation's coordinates, which run from the bottom.
    func flipped(within height: CGFloat) -> CGRect {
        CGRect(x: minX, y: height - maxY, width: width, height: self.height)
    }

    /// Inset that never goes past empty. insetBy gives CGRect.null, at
    /// infinity, when the rectangle is smaller than the inset, as a view is
    /// before its first layout; this keeps the middle, at zero size.
    public func insetClamped(dx: CGFloat, dy: CGFloat) -> CGRect {
        let r = standardized
        let w = max(0, r.width - 2 * dx), h = max(0, r.height - 2 * dy)
        return CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
    }
}
