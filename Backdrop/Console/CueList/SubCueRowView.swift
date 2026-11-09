import AppKit
import BackdropCore

/// One GO a cue waits for, under its cue: "GO 2 · Dracula? No." It has no
/// number of its own. GOs already reached are dimmed and ticked; the one
/// standing by has the brass bar. A click stands it by. It is drawn from
/// its cue's content, so it can't be dragged or deleted.
final class SubCueRowView: NSView {
    let cue: UUID
    let index: Int
    let count: Int
    let point: GoPoint
    var isStandby = false { didSet { if isStandby != oldValue { needsDisplay = true } } }
    var isTaken = false { didSet { if isTaken != oldValue { needsDisplay = true } } }
    var onClick: (UUID, Int) -> Void = { _, _ in }

    static let height: CGFloat = 22

    init(cue: UUID, index: Int, count: Int, point: GoPoint) {
        self.cue = cue
        self.index = index
        self.count = count
        self.point = point
        super.init(frame: .zero)
        toolTip = "GO \(index + 1) of \(count): \(point.unit.rawValue) \u{2014} \(point.text)"
            + (point.cuePoint.isEmpty ? "" : "\nWaits for: \(point.cuePoint)")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if isStandby {
            Desk.brass.setFill()
            NSRect(x: 0, y: 3, width: 2, height: bounds.height - 6).fill()
        }
        func draw(_ text: String, _ font: NSFont, _ colour: NSColor, x: CGFloat, width: CGFloat, align: NSTextAlignment = .left) {
            let style = NSMutableParagraphStyle()
            style.alignment = align
            style.lineBreakMode = .byTruncatingTail
            NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: colour, .paragraphStyle: style])
                .draw(in: NSRect(x: x, y: 2, width: width, height: 18))
        }
        let colour = isTaken ? Desk.dim.withAlphaComponent(0.6) : (isStandby ? Desk.brass : Desk.dim)
        if isTaken { draw("\u{2713}", Desk.sans(11.5, .semibold), colour, x: 56, width: 14) }
        let go = "GO \(index + 1)"
        draw(go, Desk.mono(11.5, .semibold), colour, x: 78, width: 44)
        // What it brings on, then what it waits for, in italics.
        let line = NSMutableAttributedString(string: "\u{00B7} " + point.text, attributes: [
            .font: Desk.sans(11.5), .foregroundColor: isTaken ? colour : Desk.text,
        ])
        if !point.cuePoint.isEmpty {
            line.append(NSAttributedString(string: "   " + point.cuePoint, attributes: [
                .font: NSFontManager.shared.convert(Desk.sans(11.5), toHaveTrait: .italicFontMask), .foregroundColor: Desk.dim,
            ]))
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
        line.draw(in: NSRect(x: 122, y: 2, width: bounds.width - 132, height: 18))
    }

    override func mouseDown(with event: NSEvent) {
        onClick(cue, index)
    }
}
