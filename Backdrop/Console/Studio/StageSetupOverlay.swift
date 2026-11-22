import AppKit
import BackdropCore

/// Stage setup, on the stage itself: the projector's whole output with the
/// projection area outlined in brass, eight handles round it, and a readout.
/// Dragging an edge or a corner resizes the area, and dragging inside it
/// moves it, snapping to the centre lines within 1%. A drag is one undo step.
@MainActor
final class StageSetupOverlay: NSView {
    var geometry = Geometry() { didSet { if geometry != oldValue { needsDisplay = true } } }
    /// The area changed: coalescing, as a slider's drag is.
    var onChange: (Geometry) -> Void = { _ in }
    var onFinished: () -> Void = {}

    private static let handle: CGFloat = 9

    override var isFlipped: Bool { true }

    private var area: NSRect { geometry.insetRect(in: bounds.size) }

    private enum Grip: Equatable {
        case move
        case edge(left: Bool, right: Bool, top: Bool, bottom: Bool)
    }

    private var handles: [(Grip, NSPoint)] {
        let a = area
        let xs: [(CGFloat, Bool, Bool)] = [(a.minX, true, false), (a.midX, false, false), (a.maxX, false, true)]
        let ys: [(CGFloat, Bool, Bool)] = [(a.minY, true, false), (a.midY, false, false), (a.maxY, false, true)]
        var result: [(Grip, NSPoint)] = []
        for (x, left, right) in xs {
            for (y, top, bottom) in ys where left || right || top || bottom {
                result.append((.edge(left: left, right: right, top: top, bottom: bottom), NSPoint(x: x, y: y)))
            }
        }
        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        let brass = Room.studio.brass
        // Outside the area: the output, dimmed.
        NSColor.black.withAlphaComponent(0.45).setFill()
        let outside = NSBezierPath(rect: bounds)
        outside.append(NSBezierPath(rect: area).reversed)
        outside.fill()
        // The centre lines it snaps to.
        brass.withAlphaComponent(0.25).setFill()
        NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height).fill()
        NSRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1).fill()
        brass.setStroke()
        let outline = NSBezierPath(rect: area.insetBy(dx: 0.75, dy: 0.75))
        outline.lineWidth = 1.5
        outline.stroke()
        for (_, point) in handles {
            let r = NSRect(x: point.x - Self.handle / 2, y: point.y - Self.handle / 2, width: Self.handle, height: Self.handle)
            NSColor.white.setFill()
            NSBezierPath(rect: r).fill()
            brass.setStroke()
            NSBezierPath(rect: r).stroke()
        }
        let readout = "W \(geometry.width)% \u{00B7} H \(geometry.height)% \u{00B7} across \(Self.signed(geometry.across))% \u{00B7} down \(Self.signed(geometry.down))%"
        let text = NSAttributedString(string: readout, attributes: [.font: Desk.mono(11.5), .foregroundColor: NSColor.white])
        let size = text.size()
        let box = NSRect(x: area.midX - size.width / 2 - 8, y: max(6, area.minY - size.height - 14), width: size.width + 16, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        text.draw(at: NSPoint(x: box.minX + 8, y: box.minY + 3))
    }

    private static func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : n < 0 ? "\u{2212}\(-n)" : "0" }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = convert(event.locationInWindow, from: nil)
        let grip: Grip
        if let near = handles.first(where: { hypot($0.1.x - start.x, $0.1.y - start.y) < Self.handle + 3 }) {
            grip = near.0
        } else if area.contains(start) {
            grip = .move
        } else {
            return
        }
        let original = geometry
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking) { event, stop in
            guard let event, event.type == .leftMouseDragged else {
                stop.pointee = true
                return
            }
            let point = convert(event.locationInWindow, from: nil)
            // In percentages of the output.
            let dx = Double((point.x - start.x) / max(1, bounds.width) * 100)
            let dy = Double((point.y - start.y) / max(1, bounds.height) * 100)
            let next = Self.dragged(original, grip: grip, dx: dx, dy: dy)
            if next != geometry {
                geometry = next
                onChange(next)
            }
        }
        onFinished()
    }

    /// Where the area goes for a drag: moved, or one or two of its edges
    /// moved with the opposite ones staying put. Within the ranges, and
    /// snapped to the centre within 1%.
    private static func dragged(_ g: Geometry, grip: Grip, dx: Double, dy: Double) -> Geometry {
        var g = g
        let size = SettingRange.geometrySize, offset = SettingRange.geometryOffset
        switch grip {
        case .move:
            g.across = offset.limit(snap(Int((Double(g.across) + dx).rounded())))
            g.down = offset.limit(snap(Int((Double(g.down) + dy).rounded())))
        case .edge(let left, let right, let top, let bottom):
            // Each edge's own position, in percent from the left or top.
            var l = (100 - Double(g.width)) / 2 + Double(g.across), r = l + Double(g.width)
            var t = (100 - Double(g.height)) / 2 + Double(g.down), b = t + Double(g.height)
            if left { l += dx }
            if right { r += dx }
            if top { t += dy }
            if bottom { b += dy }
            let width = size.limit(Int((r - l).rounded())), height = size.limit(Int((b - t).rounded()))
            g.width = width
            g.height = height
            g.across = offset.limit(snap(Int((l + Double(width) / 2 - 50).rounded())))
            g.down = offset.limit(snap(Int((t + Double(height) / 2 - 50).rounded())))
            // The edge not dragged stays where it was.
            if left && !right { g.across = offset.limit(Int((r - Double(width) / 2 - 50).rounded())) }
            if top && !bottom { g.down = offset.limit(Int((b - Double(height) / 2 - 50).rounded())) }
        }
        return g
    }

    /// The centre lines pull within 1%.
    private static func snap(_ offset: Int) -> Int { abs(offset) <= 1 ? 0 : offset }

    override func resetCursorRects() {
        addCursorRect(area, cursor: .openHand)
        for (_, point) in handles {
            addCursorRect(NSRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14), cursor: .crosshair)
        }
    }
}

extension ClosedRange<Int> {
    fileprivate func limit(_ v: Int) -> Int { Swift.min(Swift.max(v, lowerBound), upperBound) }
}
