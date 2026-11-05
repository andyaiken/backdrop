import AppKit

/// The keyboard reference along the bottom.
final class KeyBar: PanelView {
    private let keys: [(String, String)] = [
        ("Space", "Fire the standby cue"),
        ("\u{2190} \u{2192}", "Stand by previous, next"),
        ("0\u{2013}9 \u{21A9}", "Go to a cue number"),
        ("R", "Run again"),
        ("B", "Blackout"),
    ]

    init() {
        super.init(fill: Desk.raised)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        Desk.line.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()

        var x: CGFloat = 16
        let midY = bounds.height / 2
        for (key, meaning) in keys {
            let keyText = NSAttributedString(string: key, attributes: [.font: Desk.mono(12), .foregroundColor: Desk.brass])
            let keySize = keyText.size()
            let cap = NSRect(x: x, y: midY - 10, width: keySize.width + 14, height: 20)
            let path = NSBezierPath(roundedRect: cap.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            Desk.sunk.setFill()
            path.fill()
            Desk.line.setStroke()
            path.stroke()
            keyText.draw(at: NSPoint(x: cap.minX + 7, y: midY - keySize.height / 2))
            let meaningText = NSAttributedString(string: meaning, attributes: [.font: Desk.sans(12.5), .foregroundColor: Desk.dim])
            let meaningSize = meaningText.size()
            meaningText.draw(at: NSPoint(x: cap.maxX + 7, y: midY - meaningSize.height / 2))
            x = cap.maxX + 7 + meaningSize.width + 22
        }
        let trail = NSAttributedString(string: "These work in the projector window too.",
                                       attributes: [.font: Desk.sans(12.5), .foregroundColor: Desk.dim])
        let trailSize = trail.size()
        if bounds.width - 16 - trailSize.width > x {
            trail.draw(at: NSPoint(x: bounds.width - 16 - trailSize.width, y: midY - trailSize.height / 2))
        }
    }
}
