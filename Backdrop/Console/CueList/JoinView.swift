import AppKit
import BackdropCore

/// Between two cues in the rail: how the stage changes into the second,
/// as a small picture of the style and today's note, "fade 0.5 s"; and when
/// the first runs on by itself, how, as a link: "runs on after 3.0 s".
///
/// In the Studio a join is clickable and selects the transition, and a
/// right click puts a changed one back to the standard fade. With the
/// pointer over it a brass + appears at its left, to add a cue there. The
/// joins above the first cue and below the last are only that +.
final class JoinView: NSView {
    /// The cue the transition leads into. Nil above the first cue and below the last.
    let cue: UUID?
    let style: TransitionStyle
    let note: String
    /// How the cue above runs on into this one, if it does.
    let link: String?
    /// Whether the transition differs from the standard fade, and so can be cleared.
    let isChanged: Bool
    /// Where a cue added here goes: after this index in the sheet, or -1 for the start.
    let after: Int
    var room = Room.studio { didSet { needsDisplay = true } }
    /// The Studio's: clickable, with the + on hover.
    var isEditing = false { didSet { if isEditing != oldValue { needsDisplay = true } } }
    var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true } } }
    private var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    var onClick: (UUID) -> Void = { _ in }
    var onClear: (UUID) -> Void = { _ in }
    var onInsert: (Int) -> Void = { _ in }

    static let height: CGFloat = 20
    static let linkedHeight: CGFloat = 24
    /// Above the first cue and below the last: room for the + alone.
    static let leadHeight: CGFloat = 20
    static let glyph = NSSize(width: 26, height: 8)

    init(cue: UUID?, transition: Transition?, link: String?, after: Int) {
        self.cue = cue
        self.style = transition?.style ?? .fade
        self.note = cue == nil ? "" : (transition.map(CueText.transitionNote) ?? "")
        self.link = link
        self.isChanged = transition.map { $0 != .standard } ?? false
        self.after = after
        super.init(frame: .zero)
        setAccessibilityElement(cue != nil)
        setAccessibilityRole(.button)
        setAccessibilityLabel(cue == nil ? nil : "Transition: \(note)" + (link.map { ". The cue above \($0)" } ?? ""))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    /// Where the + is: at the left, over the margin.
    private var plusRect: NSRect { NSRect(x: 0, y: bounds.midY - 9, width: 18, height: 18) }

    override func draw(_ dirtyRect: NSRect) {
        if isEditing, isSelected, cue != nil {
            room.brass.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).fill()
        }
        if isEditing, isHovered {
            // Over a transition, a box round it, to pick it; above the first
            // cue, a line where the cue would go. Either way, the + to add one.
            room.brass.setStroke()
            room.brass.setFill()
            if cue != nil {
                let box = NSBezierPath(roundedRect: NSRect(x: CueRowView.boxX, y: 0, width: bounds.width - CueRowView.boxX - 8, height: bounds.height)
                    .insetBy(dx: 0.75, dy: 0.75), xRadius: 4, yRadius: 4)
                box.lineWidth = 1.5
                box.stroke()
            } else {
                NSRect(x: 22, y: bounds.midY - 0.75, width: bounds.width - 30, height: 1.5).fill()
            }
            let circle = NSBezierPath(ovalIn: plusRect.insetBy(dx: 1, dy: 1))
            circle.fill()
            let plus = NSBezierPath()
            plus.move(to: NSPoint(x: plusRect.midX - 4, y: plusRect.midY))
            plus.line(to: NSPoint(x: plusRect.midX + 4, y: plusRect.midY))
            plus.move(to: NSPoint(x: plusRect.midX, y: plusRect.midY - 4))
            plus.line(to: NSPoint(x: plusRect.midX, y: plusRect.midY + 4))
            plus.lineWidth = 1.6
            room.background.setStroke()
            plus.stroke()
            if cue == nil { return }
        }
        guard cue != nil else { return }
        let glyphRect = NSRect(x: CueRowView.boxX + 3, y: bounds.midY - Self.glyph.height / 2,
                               width: Self.glyph.width, height: Self.glyph.height)
        drawGlyph(in: glyphRect)
        let colour = isChanged || (isEditing && isSelected) ? room.brass : room.dim
        let text = NSAttributedString(string: note, attributes: [.font: Desk.mono(10.5), .foregroundColor: colour])
        let size = text.size()
        text.draw(at: NSPoint(x: CueRowView.textX, y: bounds.midY - size.height / 2))
        if let link {
            let words = NSAttributedString(string: link, attributes: [.font: Desk.sans(10.5, .medium), .foregroundColor: room.brass])
            let s = words.size()
            words.draw(at: NSPoint(x: max(CueRowView.textX + size.width + 12, bounds.width - 10 - s.width), y: bounds.midY - s.height / 2))
        }
    }

    /// The transition's style, small: a hard split for a snap, grey to black
    /// to grey for a fade, a blend for a crossfade, a slanted split for a wipe.
    private func drawGlyph(in rect: NSRect) {
        let light = NSColor(white: 0.62, alpha: 1), dark = NSColor(white: 0.12, alpha: 1)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        switch style {
        case .snap:
            light.setFill()
            NSRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height).fill()
            dark.setFill()
            NSRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height).fill()
        case .fade:
            NSGradient(colors: [light, .black, light])?.draw(in: rect, angle: 0)
        case .crossfade:
            NSGradient(starting: light, ending: dark)?.draw(in: rect, angle: 0)
        case .wipe:
            dark.setFill()
            rect.fill()
            let slant = NSBezierPath()
            slant.move(to: NSPoint(x: rect.minX, y: rect.minY))
            slant.line(to: NSPoint(x: rect.midX + 3, y: rect.minY))
            slant.line(to: NSPoint(x: rect.midX - 3, y: rect.maxY))
            slant.line(to: NSPoint(x: rect.minX, y: rect.maxY))
            slant.close()
            light.setFill()
            slant.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        room.line.setStroke()
        shape.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEditing else { return }
        let point = convert(event.locationInWindow, from: nil)
        if plusRect.insetBy(dx: -4, dy: -4).contains(point) || cue == nil {
            onInsert(after)
        } else if let cue {
            onClick(cue)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEditing, let cue else { return false }
        onClick(cue)
        return true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard isEditing, isChanged else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(title: "Clear Transition", action: #selector(clearPicked(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func clearPicked(_ item: NSMenuItem) {
        if let cue { onClear(cue) }
    }

    /// How a cue runs on into the next, as its link says it.
    static func link(for mode: ContinueMode) -> String? {
        switch mode {
        case .whenCued: nil
        case .after(0): "runs on at once"
        case .after(let ms): "runs on after \(CueText.seconds(ms))"
        case .whenFinished(0): "runs on when finished"
        case .whenFinished(let ms): "runs on \(CueText.seconds(ms)) after finishing"
        }
    }
}
