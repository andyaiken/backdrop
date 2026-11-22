import AppKit
import BackdropCore

/// One cue in the rail, as pencilled in the book: its number in a margin
/// box, its name, its cue point in typewriter italics, and at the right a
/// picture of it finished. The Studio adds the row's summary, and while the
/// pointer is over it, delete and a grip to drag it by.
///
/// The square tab down the left edge says what the row is: NEXT in brass,
/// ON STAGE in red, or, with no word, amber for a cue with an issue.
final class CueRowView: NSView {
    let cue: Cue
    var room = Room.studio { didSet { needsDisplay = true } }
    /// The Booth draws two lines of cue point and no summary; the Studio one
    /// of each.
    var isBooth = false { didSet { if isBooth != oldValue { needsDisplay = true } } }
    var isStandby = false { didSet { if isStandby != oldValue { needsDisplay = true; updateAccessibility() } } }
    var isLive = false { didSet { if isLive != oldValue { needsDisplay = true; updateAccessibility() } } }
    /// What is wrong with the cue, in the sheet's words, if anything.
    var issue: String? { didSet { if issue != oldValue { needsDisplay = true; updateAccessibility() } } }
    /// How many GOs the cue waits for while they are folded away. Zero while
    /// its steps are open, or when it has none.
    var foldedGoes = 0 { didSet { if foldedGoes != oldValue { needsDisplay = true } } }
    /// The Studio: delete and a grip, while the pointer is over the row.
    var isEditing = false {
        didSet {
            guard isEditing != oldValue else { return }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    /// The cue finished, at the right.
    var thumbnail: CGImage? { didSet { if thumbnail !== oldValue { needsDisplay = true } } }
    /// Dimmed while it's being dragged to a new place.
    var isLifted = false { didSet { alphaValue = isLifted ? 0.45 : 1 } }
    /// A picture or clip dragged over it would go to this cue. The list
    /// decides, since it takes every drop.
    var isTargeted = false { didSet { if isTargeted != oldValue { needsDisplay = true } } }
    private(set) var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var onClick: (UUID) -> Void = { _ in }
    var onDelete: (UUID) -> Void = { _ in }
    /// The grip was pressed: the list takes the drag from here.
    var onGrip: (CueRowView, NSEvent) -> Void = { _, _ in }
    /// The Studio's accessibility actions: move the cue up or down a place.
    var onMove: (UUID, Int) -> Void = { _, _ in }

    init(cue: Cue) {
        self.cue = cue
        super.init(frame: .zero)
        toolTip = cue.line.isEmpty ? nil : cue.line
        updateAccessibility()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Whether a picture or clip dropped on the row goes to the cue, as its
    /// file. A layered image has a base and layers, so a drop would be
    /// ambiguous; its strip in the Inspector takes them instead.
    var takesMedia: Bool { [.image, .morph, .map, .video].contains(cue.kind) }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    #if DEBUG
    /// For snapshots, which have no pointer.
    func pretendHovered(_ on: Bool) { isHovered = on }
    #endif

    // MARK: Geometry

    static let inset: CGFloat = 8
    static let boxX: CGFloat = 18
    static let box = NSSize(width: 32, height: 22)
    static let textX: CGFloat = 62
    static let thumb = NSSize(width: 56, height: 32)
    private static let lineHeight: CGFloat = 16

    /// The margin box, where the rail's links join one cue to the next.
    var boxRect: NSRect { NSRect(x: Self.boxX, y: Self.inset + 1, width: Self.box.width, height: Self.box.height) }
    private var thumbRect: NSRect {
        NSRect(x: bounds.width - 10 - Self.thumb.width, y: Self.inset + 1, width: Self.thumb.width, height: Self.thumb.height)
    }
    /// Delete and the grip, left of the picture, while the pointer is over a
    /// row in the Studio.
    private var showsControls: Bool { isEditing && isHovered }
    var gripRect: NSRect { NSRect(x: thumbRect.minX - 26, y: thumbRect.minY, width: 22, height: Self.thumb.height) }
    var deleteRect: NSRect { NSRect(x: gripRect.minX - 24, y: thumbRect.midY - 11, width: 22, height: 22) }
    private var textWidth: CGFloat { max(40, thumbRect.minX - 10 - Self.textX) }

    private var summary: String {
        let goes = foldedGoes > 0 ? "\u{25B8} \(foldedGoes) GO\(foldedGoes == 1 ? "" : "s")" : ""
        return [CueText.summary(cue), goes].filter { !$0.isEmpty }.joined(separator: "   ")
    }

    private static let scriptFont = Desk.script(12.5, italic: true)

    /// How many lines the cue point takes: two at most in the Booth, one in
    /// the Studio.
    private func cuePointLines(width: CGFloat) -> Int {
        guard !cue.line.isEmpty else { return 0 }
        guard isBooth else { return 1 }
        let size = (cue.line as NSString).boundingRect(with: NSSize(width: width, height: 1000),
                                                       options: [.usesLineFragmentOrigin],
                                                       attributes: [.font: Self.scriptFont])
        return size.height > Self.lineHeight * 1.5 ? 2 : 1
    }

    func preferredHeight(width: CGFloat) -> CGFloat {
        let textWidth = max(40, width - 10 - Self.thumb.width - 10 - Self.textX)
        var height = 2 * Self.inset + 18
        if !isBooth, !summary.isEmpty { height += 17 }
        height += CGFloat(cuePointLines(width: textWidth)) * Self.lineHeight
        if issue != nil { height += Self.lineHeight }
        return max(height, Self.thumb.height + 2 * Self.inset + 2)
    }

    // MARK: Drawing

    override func resetCursorRects() {
        if showsControls { addCursorRect(gripRect, cursor: .openHand) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shape = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
        if isTargeted {
            room.raised.setFill()
            shape.fill()
            room.brass.setStroke()
            shape.lineWidth = 1.5
            shape.stroke()
        } else if isStandby {
            room.raised.setFill()
            shape.fill()
            room.brass.withAlphaComponent(0.6).setStroke()
            shape.stroke()
        } else if isLive {
            room.tally.withAlphaComponent(0.12).setFill()
            shape.fill()
        } else if isHovered {
            room.ink.withAlphaComponent(0.06).setFill()
            shape.fill()
        }
        if let _ = issue, !isStandby, !isLive { drawHatch(in: box) }

        // The tab names the row. The live cue stood by again shows NEXT,
        // since that's what Space will do.
        if isStandby {
            Desk.drawTab("NEXT", fill: room.brass, ink: room.background, in: box, radius: 4)
        } else if isLive {
            Desk.drawTab("ON STAGE", fill: room.tally, ink: .white, in: box, radius: 4)
        } else if issue != nil {
            Desk.drawTab(nil, fill: room.amber, ink: room.background, in: box, radius: 4)
        }

        drawMarginBox()

        var y = Self.inset
        if case .blank(let blank) = cue.content {
            // A blank has no words, only a colour: a small bordered swatch of it.
            let swatch = NSBezierPath(roundedRect: NSRect(x: Self.textX + 0.5, y: y + 3.5, width: 34, height: 13), xRadius: 3, yRadius: 3)
            NSColor(srgbRed: CGFloat(blank.colour.r) / 255, green: CGFloat(blank.colour.g) / 255,
                    blue: CGFloat(blank.colour.b) / 255, alpha: 1).setFill()
            swatch.fill()
            room.line.setStroke()
            swatch.stroke()
            // The Studio's summary gives the colour; the Booth has none, so it goes here.
            if isBooth { draw(blank.colour.hex, Desk.mono(12), room.dim, x: Self.textX + 44, y: y + 1, width: textWidth - 44) }
        } else {
            draw(CueText.name(cue), Desk.mono(13), room.ink, x: Self.textX, y: y, width: textWidth, kern: 0.65)
        }
        y += 18
        if !isBooth, !summary.isEmpty {
            draw(summary, Desk.sans(11.5), room.dim, x: Self.textX, y: y, width: textWidth)
            y += 17
        } else if isBooth, foldedGoes > 0, cue.line.isEmpty {
            draw("\u{25B8} \(foldedGoes) GO\(foldedGoes == 1 ? "" : "s")", Desk.sans(11.5), room.dim, x: Self.textX, y: y, width: textWidth)
        }
        let lines = cuePointLines(width: textWidth)
        if lines > 0 {
            draw(cue.line, Self.scriptFont, room.dim, x: Self.textX, y: y, width: textWidth, lines: lines)
            y += CGFloat(lines) * Self.lineHeight
        }
        if let issue {
            draw(issue, Desk.sans(11.5, .medium), room.amber, x: Self.textX, y: y, width: textWidth)
        }
        drawThumbnail()
        if showsControls {
            drawSymbol("line.3.horizontal", room.dim, centredIn: gripRect)
            drawSymbol("trash", room.dim, centredIn: deleteRect, size: 10.5)
        }
        if isTargeted {
            let words = cue.kind == .video ? "Use this clip" : "Use this picture"
            draw(words, Desk.sans(11.5, .semibold), room.brass, x: Self.textX, y: bounds.height - Self.inset - 16,
                 width: textWidth)
        }
    }

    /// The number in its box, as pencilled in the margin: filled brass when
    /// next, red when on stage.
    private func drawMarginBox() {
        let rect = boxRect.insetBy(dx: 0.75, dy: 0.75)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        path.lineWidth = 1.5
        let ink: NSColor
        if isStandby {
            room.brass.setFill()
            path.fill()
            ink = room.background
        } else {
            // Filled with the rail's own colour, so a link's spine passes behind it.
            room.panel.setFill()
            path.fill()
            (isLive ? room.tally : room.line).setStroke()
            path.stroke()
            ink = isLive ? room.tally : room.dim
        }
        let font = Desk.mono(cue.number.count > 3 ? 10 : 12, .medium)
        let text = NSAttributedString(string: cue.number, attributes: [.font: font, .foregroundColor: ink])
        let size = text.size()
        text.draw(at: NSPoint(x: rect.midX - min(size.width, rect.width - 4) / 2, y: rect.midY - size.height / 2))
    }

    /// The cue finished. A feed shows a camera; a picture not yet drawn,
    /// black.
    private func drawThumbnail() {
        let rect = thumbRect
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor.black.setFill()
        rect.fill()
        if let thumbnail, let context = NSGraphicsContext.current?.cgContext {
            // Flipped view: draw the image the right way up, filling the box.
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.maxY)
            context.scaleBy(x: 1, y: -1)
            let aspect = CGFloat(thumbnail.width) / CGFloat(max(1, thumbnail.height))
            let w = max(rect.width, rect.height * aspect), h = w / aspect
            context.draw(thumbnail, in: CGRect(x: (rect.width - w) / 2, y: (rect.height - h) / 2, width: w, height: h))
            context.restoreGState()
        } else if cue.kind == .feed {
            drawSymbol("video", NSColor.white.withAlphaComponent(0.6), centredIn: rect, size: 12)
        }
        NSGraphicsContext.restoreGraphicsState()
        room.line.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// Faint amber stripes across a row with an issue.
    private func drawHatch(in box: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).addClip()
        room.amber.withAlphaComponent(0.08).setStroke()
        let stripes = NSBezierPath()
        stripes.lineWidth = 6
        var x = box.minX - box.height
        while x < box.maxX {
            stripes.move(to: NSPoint(x: x, y: box.maxY))
            stripes.line(to: NSPoint(x: x + box.height, y: box.minY))
            x += 14
        }
        stripes.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func draw(_ text: String, _ font: NSFont, _ colour: NSColor, x: CGFloat, y: CGFloat, width: CGFloat,
                      kern: CGFloat = 0, lines: Int = 1) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = lines > 1 ? .byWordWrapping : .byTruncatingTail
        style.maximumLineHeight = Self.lineHeight
        let string = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: colour, .paragraphStyle: style, .kern: kern,
        ])
        string.draw(with: NSRect(x: x, y: y, width: width, height: CGFloat(lines) * Self.lineHeight + 2),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    /// A system symbol, drawn the right way up in this top-down view.
    private func drawSymbol(_ name: String, _ colour: NSColor, centredIn rect: NSRect, size: CGFloat = 11) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [colour]))) else { return }
        let s = image.size
        image.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    // MARK: Mouse

    /// In the Studio, a right click offers what the list puts together for
    /// this cue.
    var onMenu: (UUID) -> NSMenu? = { _ in nil }

    override func menu(for event: NSEvent) -> NSMenu? {
        isEditing ? onMenu(cue.id) : nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if showsControls, deleteRect.contains(point) {
            onDelete(cue.id)
            return
        }
        if showsControls, gripRect.contains(point) {
            onGrip(self, event)
            return
        }
        onClick(cue.id)
    }

    // MARK: Accessibility

    /// "Cue 5, Safe, next. Keypad, 4 boxes. Cue point: TOM: The combination,
    /// Mara. Quickly. Runs on after 3 seconds."
    private func updateAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
        var parts = ["Cue \(cue.number), \(cue.text.isEmpty ? cue.kind.heading : CueText.name(cue))"
            + (isStandby ? ", next" : "") + (isLive ? ", on stage" : "") + "."]
        parts.append([cue.kind.heading, CueText.summary(cue)].filter { !$0.isEmpty }.joined(separator: ", ") + ".")
        if !cue.line.isEmpty { parts.append("Cue point: \(cue.line)") }
        switch cue.continueMode {
        case .whenCued: break
        case .after(0): parts.append("Runs on at once.")
        case .after(let ms): parts.append("Runs on after \(ContinueMode.seconds(ms)) seconds.")
        case .whenFinished(0): parts.append("Runs on when finished.")
        case .whenFinished(let ms): parts.append("Runs on \(ContinueMode.seconds(ms)) seconds after finishing.")
        }
        if let issue { parts.append("Issue: \(issue)") }
        setAccessibilityLabel(parts.joined(separator: " "))
    }

    override func accessibilityPerformPress() -> Bool {
        onClick(cue.id)
        return true
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard isEditing else { return nil }
        return [
            NSAccessibilityCustomAction(name: "Stand by") { [weak self] in
                guard let self else { return false }
                self.onClick(self.cue.id)
                return true
            },
            NSAccessibilityCustomAction(name: "Delete") { [weak self] in
                guard let self else { return false }
                self.onDelete(self.cue.id)
                return true
            },
            NSAccessibilityCustomAction(name: "Move up") { [weak self] in
                guard let self else { return false }
                self.onMove(self.cue.id, -1)
                return true
            },
            NSAccessibilityCustomAction(name: "Move down") { [weak self] in
                guard let self else { return false }
                self.onMove(self.cue.id, 1)
                return true
            },
        ]
    }
}
