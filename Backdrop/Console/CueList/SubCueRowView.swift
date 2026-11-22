import AppKit
import BackdropCore

/// One GO a cue waits for, under its cue: "◆ GO 2 · THE EYES". It has no
/// number of its own. GOs already reached are ticked and dim; the one
/// standing by is brass. A click stands it by. It is drawn from its cue's
/// content, so it can't be dragged or deleted.
final class SubCueRowView: NSView {
    let cue: UUID
    let index: Int
    let count: Int
    let point: GoPoint
    var room = Room.studio { didSet { needsDisplay = true } }
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
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
        setAccessibilityLabel("GO \(index + 1) of \(count): \(point.text)."
            + (point.cuePoint.isEmpty ? "" : " Cue point: \(point.cuePoint)"))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let colour = isTaken ? room.dim.withAlphaComponent(0.6) : (isStandby ? room.brass : room.dim)
        // The diamond: solid when standing by, ticked when taken, else an outline.
        let centre = NSPoint(x: CueRowView.boxX + CueRowView.box.width / 2 + 12, y: bounds.midY)
        let diamond = NSBezierPath()
        diamond.move(to: NSPoint(x: centre.x, y: centre.y - 5))
        diamond.line(to: NSPoint(x: centre.x + 5, y: centre.y))
        diamond.line(to: NSPoint(x: centre.x, y: centre.y + 5))
        diamond.line(to: NSPoint(x: centre.x - 5, y: centre.y))
        diamond.close()
        if isStandby || isTaken {
            colour.setFill()
            diamond.fill()
        } else {
            colour.setStroke()
            diamond.lineWidth = 1.2
            diamond.stroke()
        }
        func draw(_ text: NSAttributedString, x: CGFloat, width: CGFloat) {
            text.draw(with: NSRect(x: x, y: 3, width: width, height: 16), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        let go = "GO \(index + 1)" + (isTaken ? " \u{2713}" : "")
        draw(NSAttributedString(string: go, attributes: [.font: Desk.mono(11.5, .semibold), .foregroundColor: colour]),
             x: CueRowView.textX, width: 56)
        // What it brings on, then what it waits for, in the typewriter.
        let line = NSMutableAttributedString(string: "\u{00B7} " + point.text, attributes: [
            .font: Desk.sans(11.5), .foregroundColor: isTaken ? colour : (isStandby ? room.brass : room.ink),
        ])
        if !point.cuePoint.isEmpty {
            line.append(NSAttributedString(string: "   " + point.cuePoint, attributes: [
                .font: Desk.script(11.5, italic: true), .foregroundColor: room.dim,
            ]))
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
        draw(line, x: CueRowView.textX + 56, width: max(0, bounds.width - CueRowView.textX - 66))
    }

    override func mouseDown(with event: NSEvent) {
        onClick(cue, index)
    }

    override func accessibilityPerformPress() -> Bool {
        onClick(cue, index)
        return true
    }
}
