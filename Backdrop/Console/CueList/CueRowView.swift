import AppKit
import BackdropCore

/// One row: number, a glyph for the kind, the name, and beneath it the
/// subtitle and the cue point. The live cue sits on a raised background; the
/// standby cue has a brass number and a brass bar. In edit mode every cue but
/// the first has a row above it for the transition in, `TransitionRowView`.
final class CueRowView: NSView {
    let cue: Cue
    var isStandby = false { didSet { if isStandby != oldValue { needsDisplay = true } } }
    var isLive = false { didSet { if isLive != oldValue { needsDisplay = true } } }
    var hasIssue = false
    /// How many GOs the cue waits for while they are folded away: shown as a
    /// count. Zero while its sub-cues are open, or when it has none.
    var foldedGoes = 0 { didSet { if foldedGoes != oldValue { needsDisplay = true } } }
    /// In edit mode, a picture or clip dropped on an image or video row goes
    /// to that cue.
    var acceptsMedia = false
    /// Edit mode: a delete button and a grip to drag the row by, at the right.
    var isEditing = false {
        didSet {
            guard isEditing != oldValue else { return }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    /// Dimmed while it's being dragged to a new place.
    var isLifted = false { didSet { alphaValue = isLifted ? 0.45 : 1 } }
    private var targeted = false { didSet { needsDisplay = true } }
    private var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    var onClick: (UUID) -> Void = { _ in }
    var onDrop: (URL, UUID) -> Void = { _, _ in }
    var onDelete: (UUID) -> Void = { _ in }
    /// The grip was pressed: the list takes the drag from here.
    var onGrip: (CueRowView, NSEvent) -> Void = { _, _ in }

    init(cue: Cue) {
        self.cue = cue
        super.init(frame: .zero)
        let continues = cue.continueMode.continues ? "Continues " + cue.continueMode.summary : nil
        toolTip = [cue.line.isEmpty ? nil : cue.line, continues].compactMap { $0 }.joined(separator: "\n").nilIfEmpty
        if [.image, .morph, .map, .video].contains(cue.kind) { registerForDraggedTypes([.fileURL]) }
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

    /// At the right of the row, for a cue that moves on by itself: a down
    /// arrow if it continues when finished, whatever the wait after, or the
    /// moment it fires; a clock if it continues a while after it fires.
    static func continueSymbol(_ mode: ContinueMode) -> String? {
        switch mode {
        case .whenCued: nil
        case .whenFinished, .after(0): "arrow.down"
        case .after: "clock"
        }
    }

    /// What the cue shows beneath its name, with a count of its GOs while
    /// they are folded away.
    var subtitle: String {
        let goes = foldedGoes > 0 ? "\u{25B8} \(foldedGoes) GO\(foldedGoes == 1 ? "" : "s")" : ""
        return [content, goes].filter { !$0.isEmpty }.joined(separator: "   ")
    }

    private var content: String {
        switch cue.content {
        case .title(let c): c.sub
        case .anagram(let c):
            [c.anagrams.first.map { $0.answer.isEmpty ? "" : "\u{2192} " + $0.answer } ?? "",
             c.anagrams.count > 1 ? "and \(c.anagrams.count - 1) more" : ""].filter { !$0.isEmpty }.joined(separator: "   ")
        case .image(let c): c.src.isEmpty ? "no picture" : ""
        case .morph(let c):
            c.pictures.count < 2 ? "needs two pictures"
                : c.pictures.count > 2 ? "\(c.pictures.count) pictures"
                : "\(c.pictures[1].pairs.count) point\(c.pictures[1].pairs.count == 1 ? "" : "s")"
        case .map(let c):
            c.src.isEmpty ? "no map"
                : c.stops.count < 2 ? "no stops" : "\(c.stops.count - 1) stop\(c.stops.count == 2 ? "" : "s")"
        case .video(let c): [c.sub, c.atEnd == .hold ? "" : c.atEnd.rawValue].filter { !$0.isEmpty }.joined(separator: "   ")
        case .feed(let c):
            [c.sub, c.settings.device.isEmpty ? "no camera" : c.settings.deviceName].filter { !$0.isEmpty }.joined(separator: "   ")
        case .blank(let c): c.colour.hex
        case .conversation(let c):
            c.messages.isEmpty ? "no messages" : "\(c.messages.count) message\(c.messages.count == 1 ? "" : "s")"
        case .sms(let c): [c.sub.isEmpty ? "no sender" : "from \(c.sub)", c.settings.shownStatus == .none ? (c.settings.sent ? "sent" : "") : "sent, \(c.settings.shownStatus.name.lowercased())" + (c.settings.goStatuses.isEmpty ? "" : " \u{2192} read")].filter { !$0.isEmpty }.joined(separator: "   ")
        case .keypad(let c): c.script.isEmpty ? "no keys" : "\(c.boxCount) boxes"
        case .text: ""
        case .layered(let c):
            c.layers.isEmpty ? "no layers" : "\(c.layers.count) layer\(c.layers.count == 1 ? "" : "s")"
        }
    }

    /// The middle of the cue's own lines. The number and kind on the left,
    /// and every mark and control on the right, centre on it, so they line up
    /// however many lines the row has.
    private var middleY: CGFloat { bounds.height / 2 }
    /// The whole height of the row's right edge, so it's easy to take hold of.
    var gripRect: NSRect { NSRect(x: bounds.width - 26, y: 0, width: 26, height: bounds.height) }
    var deleteRect: NSRect { NSRect(x: bounds.width - 48, y: middleY - 11, width: 22, height: 22) }
    /// A mark's place at the right, centred on the middle.
    private func markRect(x: CGFloat) -> NSRect { NSRect(x: x, y: middleY - 8, width: 14, height: 16) }
    /// The room the edit-mode controls take at the right.
    private var controlsWidth: CGFloat { isEditing ? 48 : 0 }

    /// A system symbol, drawn the right way up in this top-down view.
    private func drawSymbol(_ name: String, _ colour: NSColor, centredIn rect: NSRect, size: CGFloat = 11) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [colour]))) else { return }
        let s = image.size
        image.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func resetCursorRects() {
        if isEditing { addCursorRect(gripRect, cursor: .openHand) }
    }

    var preferredHeight: CGFloat {
        16 + 18 + (subtitle.isEmpty ? 0 : 17) + (cue.line.isEmpty ? 0 : 17)
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 0.5, dy: 0.5)
        if targeted {
            let path = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
            Desk.raised.setFill()
            path.fill()
            Desk.brass.setStroke()
            path.stroke()
        } else if isLive {
            let path = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
            Desk.raised.setFill()
            path.fill()
            Desk.lineBright.setStroke()
            path.stroke()
        }
        // Standing by is a tint and a bar; the pointer over a row is a lighter tint.
        if isStandby || (isHovered && !targeted) {
            (isStandby ? Desk.selected : Desk.hover).setFill()
            NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        }
        if isStandby {
            Desk.brass.setFill()
            NSRect(x: 0, y: 6, width: 2, height: bounds.height - 12).fill()
        }

        func draw(_ text: String, _ font: NSFont, _ colour: NSColor, x: CGFloat, y: CGFloat, width: CGFloat, align: NSTextAlignment = .left, kern: CGFloat = 0) {
            let style = NSMutableParagraphStyle()
            style.alignment = align
            style.lineBreakMode = .byTruncatingTail
            NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: colour, .paragraphStyle: style, .kern: kern,
            ]).draw(in: NSRect(x: x, y: y, width: width, height: 18))
        }

        var y: CGFloat = 8
        // A figure or a mark is centred by its own height, not its line's: a
        // line has room below the baseline for descenders that digits never
        // use, which would leave them sitting high beside the icons.
        func centredY(_ font: NSFont) -> CGFloat { middleY + font.capHeight / 2 - font.ascender }
        let numberFont = Desk.mono(12)
        draw(cue.number, numberFont, isStandby ? Desk.brass : Desk.dim, x: 8, y: centredY(numberFont), width: 40, align: .right)
        drawSymbol(cue.kind.symbol, Desk.dim, centredIn: NSRect(x: 56, y: middleY - 8, width: 14, height: 14))
        // At the right: in edit mode the grip and delete; then how the cue
        // continues, then any problem.
        if isEditing {
            drawSymbol("line.3.horizontal", Desk.dim, centredIn: NSRect(x: gripRect.minX, y: middleY - 11, width: gripRect.width, height: 22))
            drawSymbol("trash", Desk.dim, centredIn: deleteRect, size: 10.5)
        }
        let symbol = Self.continueSymbol(cue.continueMode)
        let marks = CGFloat((symbol == nil ? 0 : 1) + (hasIssue ? 1 : 0))
        let textX: CGFloat = 78, textWidth = bounds.width - textX - 10 - marks * 18 - controlsWidth
        if case .blank(let blank) = cue.content {
            // A blank has no words, only a colour: a small bordered swatch of it.
            let swatch = NSBezierPath(roundedRect: NSRect(x: textX + 0.5, y: y + 2.5, width: 34, height: 13), xRadius: 3, yRadius: 3)
            NSColor(srgbRed: CGFloat(blank.colour.r) / 255, green: CGFloat(blank.colour.g) / 255,
                    blue: CGFloat(blank.colour.b) / 255, alpha: 1).setFill()
            swatch.fill()
            Desk.lineBright.setStroke()
            swatch.stroke()
        } else {
            draw(cue.text.isEmpty ? "\u{2014}" : cue.text.replacingOccurrences(of: "\n", with: " \u{23CE} "), Desk.mono(13), Desk.text, x: textX, y: y, width: textWidth, kern: 0.65)
        }
        var markX = bounds.width - 22 - controlsWidth
        if let symbol {
            drawSymbol(symbol, isStandby ? Desk.brass : Desk.dim, centredIn: markRect(x: markX))
            markX -= 18
        }
        if hasIssue {
            let bang = Desk.mono(13, .bold)
            draw("!", bang, Desk.brass, x: markX + 2, y: centredY(bang), width: 12)
        }
        y += 18
        if !subtitle.isEmpty {
            draw(subtitle, Desk.sans(11.5), Desk.dim, x: textX, y: y, width: textWidth)
            y += 17
        }
        if !cue.line.isEmpty {
            let italic = NSFontManager.shared.convert(Desk.sans(11.5), toHaveTrait: .italicFontMask)
            draw(cue.line, italic, Desk.dim, x: textX, y: y, width: textWidth)
        }
    }

    /// In edit mode, a right click offers what the list puts together for
    /// this cue.
    var onMenu: (UUID) -> NSMenu? = { _ in nil }

    override func menu(for event: NSEvent) -> NSMenu? {
        isEditing ? onMenu(cue.id) : nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isEditing, deleteRect.contains(point) {
            onDelete(cue.id)
            return
        }
        if isEditing, gripRect.contains(point) {
            onGrip(self, event)
            return
        }
        onClick(cue.id)
    }

    private func droppedURL(_ info: any NSDraggingInfo) -> URL? {
        guard acceptsMedia else { return nil }
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        guard let url = urls?.first, ShowDocument.accepts(url, for: cue.kind) else { return nil }
        return url
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        targeted = droppedURL(sender) != nil
        return targeted ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        targeted = false
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        targeted = false
        guard let url = droppedURL(sender) else { return false }
        onDrop(url, cue.id)
        return true
    }
}
