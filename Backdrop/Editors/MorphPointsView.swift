import AppKit
import BackdropCore

/// One picture with its points, numbered. A point is a ring, brass when it
/// is selected or its partner on the other picture is under the pointer.
final class MorphPointsView: NSView {
    var image: CGImage? { didSet { needsDisplay = true; window?.invalidateCursorRects(for: self) } }
    var points: [PicturePoint] = [] { didSet { needsDisplay = true } }
    var selected: Int? { didSet { needsDisplay = true } }
    /// The same point on the other picture, lit while this one is under the
    /// pointer.
    weak var partner: MorphPointsView?
    fileprivate var lit: Int? { didSet { if lit != oldValue { needsDisplay = true } } }

    var onAdd: (PicturePoint) -> Void = { _ in }
    var onSelect: (Int?) -> Void = { _ in }
    var onMove: (Int, PicturePoint, _ done: Bool) -> Void = { _, _, _ in }
    var onDelete: (Int) -> Void = { _ in }

    private var dragging: Int?
    private var moved = false
    private static let radius: CGFloat = 6

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The picture, as large as fits, keeping its shape.
    var imageRect: CGRect {
        guard let image, image.width > 0, image.height > 0 else { return .zero }
        let area = bounds.insetBy(dx: 2, dy: 2), aspect = CGFloat(image.width) / CGFloat(image.height)
        let w = min(area.width, area.height * aspect), h = w / aspect
        return CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
    }

    private func location(of p: PicturePoint) -> CGPoint {
        let r = imageRect
        return CGPoint(x: r.minX + CGFloat(p.x) * r.width, y: r.minY + CGFloat(p.y) * r.height)
    }

    private func picturePoint(at location: CGPoint) -> PicturePoint {
        let r = imageRect
        return PicturePoint(x: Double((location.x - r.minX) / r.width), y: Double((location.y - r.minY) / r.height)).clamped
    }

    private func point(at location: CGPoint) -> Int? {
        points.indices.reversed().first { i in
            let p = self.location(of: points[i])
            return hypot(p.x - location.x, p.y - location.y) <= Self.radius + 3
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        Desk.sunk.setFill()
        bounds.fill()
        guard let image, let ctx = NSGraphicsContext.current?.cgContext else {
            let text = NSAttributedString(string: "No picture", attributes: [.font: Desk.sans(12.5), .foregroundColor: Desk.dim])
            let size = text.size()
            text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
            return
        }
        let r = imageRect
        // The view is flipped; a picture is drawn the right way up.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: r.maxY + r.minY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: r)
        ctx.restoreGState()

        let font = Desk.mono(10.5, .semibold)
        for (i, p) in points.enumerated() {
            let c = location(of: p)
            let on = i == selected || i == lit || i == partner?.lit
            let ring = NSBezierPath(ovalIn: CGRect(x: c.x - Self.radius, y: c.y - Self.radius, width: Self.radius * 2, height: Self.radius * 2))
            ring.lineWidth = 3
            NSColor.black.withAlphaComponent(0.7).setStroke()
            ring.stroke()
            ring.lineWidth = 1.6
            (on ? Desk.brass : Desk.text).setStroke()
            ring.stroke()
            if on {
                Desk.brass.withAlphaComponent(0.35).setFill()
                ring.fill()
            }
            let label = NSAttributedString(string: "\(i + 1)", attributes: [
                .font: font, .foregroundColor: on ? Desk.brass : Desk.text,
                .strokeColor: NSColor.black, .strokeWidth: -3,
            ])
            label.draw(at: NSPoint(x: c.x + Self.radius + 2, y: c.y - Self.radius - 9))
        }
    }

    override func resetCursorRects() {
        addCursorRect(imageRect, cursor: .crosshair)
    }

    override func mouseMoved(with event: NSEvent) {
        lit = point(at: convert(event.locationInWindow, from: nil))
        partner?.needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        lit = nil
        partner?.needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let at = convert(event.locationInWindow, from: nil)
        moved = false
        if let i = point(at: at) {
            dragging = i
            onSelect(i)
        } else if imageRect.contains(at) {
            onAdd(picturePoint(at: at))
            dragging = selected
        } else {
            dragging = nil
            onSelect(nil)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragging else { return }
        moved = true
        onMove(dragging, picturePoint(at: convert(event.locationInWindow, from: nil)), false)
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragging = nil }
        guard let dragging, moved else { return }
        onMove(dragging, picturePoint(at: convert(event.locationInWindow, from: nil)), true)
    }

    override func keyDown(with event: NSEvent) {
        let delete = event.charactersIgnoringModifiers.map { $0 == "\u{7F}" || $0 == "\u{F728}" } ?? false
        if delete, let selected {
            onDelete(selected)
        } else {
            super.keyDown(with: event)
        }
    }
}
