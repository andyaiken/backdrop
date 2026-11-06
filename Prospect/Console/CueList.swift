import AppKit
import ProspectCore

/// One row: number, a glyph for the kind, the name, and beneath it the
/// subtitle and the cue point. The live cue sits on a raised background; the
/// standby cue has a brass number and a brass bar. A transition in that isn't
/// the show's default is noted in brass along the top, between this cue and
/// the one before.
final class CueRowView: NSView {
    let cue: Cue
    let transitionNote: String?
    var isStandby = false { didSet { if isStandby != oldValue { needsDisplay = true } } }
    var isLive = false { didSet { if isLive != oldValue { needsDisplay = true } } }
    var hasIssue = false
    /// How many GOs the cue waits for while they are folded away: shown as a
    /// count. Zero while its sub-cues are open, or when it has none.
    var foldedGoes = 0 { didSet { if foldedGoes != oldValue { needsDisplay = true } } }
    /// How many groups the cue is inside: its name sits in a step for each.
    var depth = 0 { didSet { if depth != oldValue { needsDisplay = true } } }

    /// How far each group a row is inside sets it in.
    static let indentStep: CGFloat = 14
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
    var onClick: (UUID) -> Void = { _ in }
    var onDrop: (URL, UUID) -> Void = { _, _ in }
    var onDelete: (UUID) -> Void = { _ in }
    /// The grip was pressed: the list takes the drag from here.
    var onGrip: (CueRowView, NSEvent) -> Void = { _, _ in }

    init(cue: Cue, transitionNote: String? = nil) {
        self.cue = cue
        self.transitionNote = transitionNote
        super.init(frame: .zero)
        let continues = cue.continueMode.continues ? "Continues " + cue.continueMode.summary : nil
        toolTip = [cue.line.isEmpty ? nil : cue.line, continues].compactMap { $0 }.joined(separator: "\n").nilIfEmpty
        if [.image, .morph, .map, .video].contains(cue.kind) { registerForDraggedTypes([.fileURL]) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

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

    static func kindGlyph(_ kind: Cue.Kind) -> String {
        switch kind {
        case .title: "\u{2261}"
        case .anagram: "\u{21C4}"
        case .image: "\u{25A6}"
        case .morph: "\u{25D0}"
        case .map: "\u{2316}"
        case .video: "\u{25B6}"
        case .blank: "\u{25A1}"
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
        case .blank(let c): c.colour.hex
        }
    }

    /// What the cue list says about a cue's own transition in, if it has one.
    static func transitionNote(for cue: Cue, defaults: ShowSettings) -> String? {
        guard !cue.transition.isEmpty else { return nil }
        let transition = cue.transitionIn(defaults: defaults)
        return transition.style == .snap ? "snap" : "fade " + SettingKey.fade.format(.number(transition.fadeMs))
    }

    private static let noteHeight: CGFloat = 14

    /// The middle of the cue's own lines, below any transition note. The
    /// number and kind on the left, and every mark and control on the right,
    /// centre on it, so they line up however many lines the row has.
    private var middleY: CGFloat { ((transitionNote == nil ? 0 : Self.noteHeight) + bounds.height) / 2 }
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
        16 + 18 + (subtitle.isEmpty ? 0 : 17) + (cue.line.isEmpty ? 0 : 17) + (transitionNote == nil ? 0 : Self.noteHeight)
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
        if let transitionNote {
            draw("\u{2193} " + transitionNote, Desk.sans(10.5), Desk.brass, x: 78 + CGFloat(depth) * Self.indentStep, y: 3,
                 width: bounds.width - 88 - CGFloat(depth) * Self.indentStep)
            y += Self.noteHeight
        }
        // Text boxes are 18 high, with the glyphs sitting a point low in them.
        let leftY = middleY - 9 - 1
        draw(cue.number, Desk.mono(12), isStandby ? Desk.brass : Desk.dim, x: 8, y: leftY, width: 40, align: .right)
        draw(Self.kindGlyph(cue.kind), Desk.mono(11), Desk.dim, x: 56, y: leftY, width: 14)
        // At the right: in edit mode the grip and delete; then how the cue
        // continues, then any problem.
        if isEditing {
            drawSymbol("line.3.horizontal", Desk.dim, centredIn: NSRect(x: gripRect.minX, y: middleY - 11, width: gripRect.width, height: 22))
            drawSymbol("trash", Desk.dim, centredIn: deleteRect, size: 10.5)
        }
        let symbol = Self.continueSymbol(cue.continueMode)
        let marks = CGFloat((symbol == nil ? 0 : 1) + (hasIssue ? 1 : 0))
        let textX = 78 + CGFloat(depth) * Self.indentStep, textWidth = bounds.width - textX - 10 - marks * 18 - controlsWidth
        draw(cue.text.isEmpty ? "\u{2014}" : cue.text, Desk.mono(13), Desk.text, x: textX, y: y, width: textWidth, kern: 0.65)
        var markX = bounds.width - 22 - controlsWidth
        if let symbol {
            drawSymbol(symbol, isStandby ? Desk.brass : Desk.dim, centredIn: markRect(x: markX))
            markX -= 18
        }
        if hasIssue {
            draw("!", Desk.mono(13, .bold), Desk.brass, x: markX + 2, y: middleY - 9 - 1, width: 12)
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

/// The cue sheet as it reads: group headings, each cue under the groups it
/// is in, and under the live or standby cue the GOs it waits for. A group
/// folds away, all but its heading; the groups around the live and standby
/// cues open themselves, and any can be opened or folded by hand. In edit
/// mode cues and groups are dragged by their grips: a cue dropped just under
/// a heading joins that group, and a group takes everything in it along.
final class CueListView: NSScrollView {
    private let document = PanelView()
    private var cueRows: [UUID: CueRowView] = [:]
    private var groupRows: [UUID: GroupRowView] = [:]
    /// The GOs of the cues whose sub-cues are open: live or standing by.
    private var steps: [UUID: [SubCueRowView]] = [:]
    private var shown: [Cue] = []
    private var shownNotes: [String?] = []
    /// The sheet as last shown, and which of its rows are on screen, in order.
    private var outline: [OutlineRow] = []
    private var visible: [(view: NSView, row: Int)] = []
    /// Groups opened or folded by hand, until the live or standby cue moves
    /// into other groups.
    private var byHand: [UUID: Bool] = [:]
    private var around: Set<UUID> = []

    var onClick: (UUID) -> Void = { _ in }
    /// A sub-cue clicked: its cue, and which GO.
    var onStepClick: (UUID, Int) -> Void = { _, _ in }
    var onDrop: (URL, UUID) -> Void = { _, _ in }
    var onDelete: (UUID) -> Void = { _ in }
    /// A cue or a group dragged to stand before an outline row.
    var onMoveCue: (UUID, Int) -> Void = { _, _ in }
    var onMoveGroup: (UUID, Int) -> Void = { _, _ in }
    var onRenameGroup: (UUID, String) -> Void = { _, _ in }
    var onGroupLevel: (UUID, Int) -> Void = { _, _ in }
    var onDeleteGroup: (UUID) -> Void = { _ in }
    /// Renumber a group's cues, or with nil every cue: the console asks
    /// first.
    var onRenumber: (UUID?) -> Void = { _ in }
    /// The show as last shown, for the right-click menus.
    private var current: Show?
    /// Where a dragged row will land.
    private let insertion = PanelView(fill: Desk.brass)

    init() {
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = true
        autohidesScrollers = true
        documentView = document
        insertion.isHidden = true
        document.addSubview(insertion)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// - Parameters:
    ///   - standbyStep: The GO of the standby cue that stands by, if one does.
    ///   - taken: How many of the live cue's GOs it has reached.
    func update(show: Show, standby: UUID?, standbyStep: Int?, live: UUID?, taken: Int, issues: Set<UUID>, editing: Bool) {
        current = show
        let cues = show.cues, defaults = show.settings
        let notes = cues.map { CueRowView.transitionNote(for: $0, defaults: defaults) }
        if cues != shown || notes != shownNotes {
            cueRows.values.forEach { $0.removeFromSuperview() }
            cueRows = [:]
            for (cue, note) in zip(cues, notes) {
                let row = CueRowView(cue: cue, transitionNote: note)
                row.onClick = { [weak self] in self?.onClick($0) }
                row.onDrop = { [weak self] url, id in self?.onDrop(url, id) }
                row.onDelete = { [weak self] in self?.onDelete($0) }
                row.onGrip = { [weak self] row, event in self?.drag(row, from: event) }
                row.onMenu = { [weak self] id in self?.menu(forCue: id) }
                document.addSubview(row, positioned: .below, relativeTo: insertion)
                cueRows[cue.id] = row
            }
            shown = cues
            shownNotes = notes
        }
        for group in show.groups where groupRows[group.id] == nil {
            let row = GroupRowView(id: group.id)
            row.onToggle = { [weak self] id in self?.toggle(id) }
            row.onRename = { [weak self] id, name in self?.onRenameGroup(id, name) }
            row.onLevel = { [weak self] id, delta in self?.onGroupLevel(id, delta) }
            row.onDelete = { [weak self] id in self?.onDeleteGroup(id) }
            row.onGrip = { [weak self] row, event in self?.drag(row, from: event) }
            row.onMenu = { [weak self] id in self?.menu(forGroup: id) }
            document.addSubview(row, positioned: .below, relativeTo: insertion)
            groupRows[group.id] = row
        }
        for (id, row) in groupRows where !show.groups.contains(where: { $0.id == id }) {
            row.removeFromSuperview()
            groupRows[id] = nil
        }

        // The groups around the live and standby cues open themselves; a
        // move into other groups puts back any opened or folded by hand.
        let now = Set([live, standby].compactMap { $0 }.flatMap { show.groups(around: $0) }.map(\.id))
        if now != around {
            around = now
            byHand = [:]
        }
        outline = show.outline

        var open: [UUID: [SubCueRowView]] = [:]
        for row in cueRows.values {
            let id = row.cue.id
            row.isStandby = id == standby && standbyStep == nil
            row.isLive = id == live
            row.hasIssue = issues.contains(id)
            row.acceptsMedia = editing
            row.isEditing = editing
            // A cue's GOs open out while it is live or standing by, and fold
            // to a count otherwise.
            let points = row.cue.goPoints(defaults: defaults)
            let opens = !points.isEmpty && (id == live || id == standby)
            row.foldedGoes = opens ? 0 : points.count
            guard opens else { continue }
            var subRows = steps[id] ?? []
            if subRows.map(\.point) != points {
                subRows.forEach { $0.removeFromSuperview() }
                subRows = points.enumerated().map { i, point in
                    let sub = SubCueRowView(cue: id, index: i, count: points.count, point: point)
                    sub.onClick = { [weak self] in self?.onStepClick($0, $1) }
                    document.addSubview(sub, positioned: .below, relativeTo: insertion)
                    return sub
                }
            }
            for sub in subRows {
                sub.isStandby = id == standby && standbyStep == sub.index
                sub.isTaken = id == live && sub.index < taken
            }
            open[id] = subRows
        }
        for (id, subRows) in steps where open[id] == nil { subRows.forEach { $0.removeFromSuperview() } }
        steps = open
        for row in groupRows.values { row.isEditing = editing }
        layoutRows()
        // Keep the standby row in view, and the live row with it if both fit.
        let standbyRow: NSView? = cueRows.values.first(where: \.isStandby) ?? steps.values.joined().first(where: \.isStandby)
        if let standbyRow {
            var target = standbyRow.frame
            if let liveRow = cueRows.values.first(where: \.isLive), !liveRow.isHidden,
               target.union(liveRow.frame).height + 48 <= contentSize.height {
                target = target.union(liveRow.frame)
            }
            document.scrollToVisible(target.insetBy(dx: 0, dy: -24))
        }
    }

    private func isOpen(_ id: UUID) -> Bool {
        byHand[id] ?? around.contains(id)
    }

    private func toggle(_ id: UUID) {
        byHand[id] = !isOpen(id)
        layoutRows()
    }

    /// Starts renaming a group in place, as straight after Add Group.
    // MARK: Right-click menus

    /// A cue's: renumber each group it is in, innermost first, or every cue.
    private func menu(forCue id: UUID) -> NSMenu? {
        guard let show = current else { return nil }
        let menu = NSMenu()
        for group in show.groups(around: id).reversed() {
            menu.addItem(renumberItem(group))
        }
        let all = NSMenuItem(title: "Renumber All Cues\u{2026}", action: #selector(renumberPicked(_:)), keyEquivalent: "")
        all.target = self
        menu.addItem(all)
        return menu
    }

    /// A heading's: rename, renumber its cues, delete it.
    private func menu(forGroup id: UUID) -> NSMenu? {
        guard let group = current?.groups.first(where: { $0.id == id }) else { return nil }
        let menu = NSMenu()
        let rename = NSMenuItem(title: "Rename", action: #selector(renamePicked(_:)), keyEquivalent: "")
        rename.representedObject = id
        rename.target = self
        menu.addItem(rename)
        menu.addItem(renumberItem(group))
        menu.addItem(.separator())
        let delete = NSMenuItem(title: "Delete Group", action: #selector(deletePicked(_:)), keyEquivalent: "")
        delete.representedObject = id
        delete.target = self
        menu.addItem(delete)
        return menu
    }

    private func renumberItem(_ group: CueGroup) -> NSMenuItem {
        let item = NSMenuItem(title: "Renumber Cues in \u{201C}\(group.name)\u{201D}\u{2026}", action: #selector(renumberPicked(_:)), keyEquivalent: "")
        item.representedObject = group.id
        item.target = self
        item.isEnabled = current.map { !$0.cues(inGroup: group.id).isEmpty } ?? false
        return item
    }

    #if DEBUG
    /// The right-click menus' items, for the document check.
    func menuTitles(forCue id: UUID) -> [String] { menu(forCue: id)?.items.map(\.title) ?? [] }
    func menuTitles(forGroup id: UUID) -> [String] { menu(forGroup: id)?.items.map(\.title) ?? [] }
    #endif

    @objc private func renumberPicked(_ item: NSMenuItem) {
        onRenumber(item.representedObject as? UUID)
    }

    @objc private func renamePicked(_ item: NSMenuItem) {
        if let id = item.representedObject as? UUID { beginRename(id) }
    }

    @objc private func deletePicked(_ item: NSMenuItem) {
        if let id = item.representedObject as? UUID { onDeleteGroup(id) }
    }

    func beginRename(_ id: UUID) {
        guard let row = groupRows[id] else { return }
        byHand[id] = true
        layoutRows()
        document.scrollToVisible(row.frame.insetBy(dx: 0, dy: -24))
        row.beginRename()
    }

    override func layout() {
        super.layout()
        layoutRows()
    }

    // MARK: Reordering

    /// Follows the pointer from a row's grip until the button comes up,
    /// showing where the row will land, then moves the cue or the group there.
    private func drag(_ row: NSView, from event: NSEvent) {
        guard let window, let from = visible.firstIndex(where: { $0.view === row }) else { return }
        let lifted = row as? Liftable
        lifted?.isLifted = true
        NSCursor.closedHand.push()
        var landed: Int?
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking) { event, stop in
            guard let event, event.type == .leftMouseDragged else {
                stop.pointee = true
                return
            }
            document.autoscroll(with: event)
            let landing = slot(at: document.convert(event.locationInWindow, from: nil).y)
            landed = landing
            showInsertion(at: landing)
        }
        NSCursor.pop()
        lifted?.isLifted = false
        insertion.isHidden = true
        guard let landed, landed != from, landed != from + 1 else { return }
        // The outline row it lands before: the row now in that slot, or the end.
        let target = landed < visible.count ? visible[landed].row : outline.count
        if let cue = row as? CueRowView {
            onMoveCue(cue.cue.id, target)
        } else if let group = row as? GroupRowView {
            onMoveGroup(group.id, target)
        }
    }

    /// Where a dragged row would go: before the first row on screen whose
    /// middle is below the pointer, or at the end.
    private func slot(at y: CGFloat) -> Int {
        visible.firstIndex { y < $0.view.frame.midY } ?? visible.count
    }

    private func showInsertion(at slot: Int) {
        let bottom = document.subviews.filter { !$0.isHidden && $0 !== insertion }.map(\.frame.maxY).max() ?? 0
        let y = slot < visible.count ? visible[slot].view.frame.minY - 2.5 : bottom + 0.5
        insertion.frame = NSRect(x: 6, y: y, width: document.bounds.width - 12, height: 2)
        insertion.isHidden = false
    }

    /// The outline in order, each row hidden while a group around it is
    /// folded.
    private func layoutRows() {
        let width = contentSize.width
        var y: CGFloat = 0
        // Whether each group still open around the row being placed is open.
        var folds: [(depth: Int, open: Bool)] = []
        visible = []
        cueRows.values.forEach { $0.isHidden = true }
        groupRows.values.forEach { $0.isHidden = true }
        steps.values.joined().forEach { $0.isHidden = true }
        for (i, entry) in outline.enumerated() {
            switch entry {
            case .group(let group, let depth, let count):
                folds = folds.filter { $0.depth < depth }
                let shows = folds.allSatisfy(\.open)
                folds.append((depth, isOpen(group.id)))
                guard shows, let row = groupRows[group.id] else { continue }
                row.show(group, depth: depth, count: count, open: isOpen(group.id))
                row.isHidden = false
                row.frame = NSRect(x: 0, y: y, width: width, height: GroupRowView.height)
                y += GroupRowView.height + 3
                visible.append((row, i))
            case .cue(let cue, let depth):
                folds = folds.filter { $0.depth < depth }
                guard folds.allSatisfy(\.open), let row = cueRows[cue.id] else { continue }
                row.depth = depth
                row.isHidden = false
                row.frame = NSRect(x: 0, y: y, width: width, height: row.preferredHeight)
                y += row.preferredHeight + 3
                visible.append((row, i))
                for sub in steps[cue.id] ?? [] {
                    sub.depth = depth
                    sub.isHidden = false
                    sub.frame = NSRect(x: 0, y: y, width: width, height: SubCueRowView.height)
                    y += SubCueRowView.height + 1
                }
            }
        }
        document.frame = NSRect(x: 0, y: 0, width: width, height: max(y, contentSize.height))
    }
}

/// A row the list lifts while it is dragged.
@MainActor
protocol Liftable: AnyObject {
    var isLifted: Bool { get set }
}

extension CueRowView: Liftable {}

/// A group's heading: a folding arrow, its name, and how many cues it holds.
/// Clicking the arrow, or anywhere on it in show mode, folds or opens it; it
/// never stands anything by. In edit mode it has its controls at the right,
/// a level out, a level in, delete and a grip to drag it by, and a double
/// click on its name renames it in place.
final class GroupRowView: NSView, Liftable, NSTextFieldDelegate {
    let id: UUID
    private(set) var group: CueGroup?
    private var depth = 0
    private var count = 0
    private var open = false
    var isEditing = false {
        didSet {
            guard isEditing != oldValue else { return }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var isLifted = false { didSet { alphaValue = isLifted ? 0.45 : 1 } }
    var onToggle: (UUID) -> Void = { _ in }
    var onRename: (UUID, String) -> Void = { _, _ in }
    var onLevel: (UUID, Int) -> Void = { _, _ in }
    var onDelete: (UUID) -> Void = { _ in }
    var onGrip: (GroupRowView, NSEvent) -> Void = { _, _ in }
    var onMenu: (UUID) -> NSMenu? = { _ in nil }
    private var nameField: NSTextField?

    override func menu(for event: NSEvent) -> NSMenu? {
        isEditing ? onMenu(id) : nil
    }

    static let height: CGFloat = 30

    init(id: UUID) {
        self.id = id
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func show(_ group: CueGroup, depth: Int, count: Int, open: Bool) {
        guard group != self.group || depth != self.depth || count != self.count || open != self.open else { return }
        self.group = group
        self.depth = depth
        self.count = count
        self.open = open
        toolTip = "\(group.name): \(count) cue\(count == 1 ? "" : "s")"
        needsDisplay = true
    }

    private var inset: CGFloat { CGFloat(depth) * CueRowView.indentStep }
    private var arrowRect: NSRect { NSRect(x: 56 + inset, y: 0, width: 20, height: bounds.height) }
    private var nameRect: NSRect { NSRect(x: 78 + inset, y: 6, width: max(40, bounds.width - 78 - inset - 10 - controlsWidth - 60), height: 18) }
    var gripRect: NSRect { NSRect(x: bounds.width - 26, y: 0, width: 26, height: bounds.height) }
    private var deleteRect: NSRect { NSRect(x: bounds.width - 48, y: 4, width: 22, height: 22) }
    private var inRect: NSRect { NSRect(x: bounds.width - 70, y: 4, width: 22, height: 22) }
    private var outRect: NSRect { NSRect(x: bounds.width - 92, y: 4, width: 22, height: 22) }
    private var controlsWidth: CGFloat { isEditing ? 92 : 0 }

    override func resetCursorRects() {
        if isEditing { addCursorRect(gripRect, cursor: .openHand) }
    }

    private func drawSymbol(_ name: String, centredIn rect: NSRect, size: CGFloat = 10.5) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [Desk.dim]))) else { return }
        let s = image.size
        image.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let group else { return }
        Desk.line.setFill()
        NSRect(x: 8 + inset, y: bounds.height - 1, width: bounds.width - 16 - inset, height: 1).fill()
        drawSymbol(open ? "chevron.down" : "chevron.right", centredIn: arrowRect, size: 9.5)
        func draw(_ text: String, _ font: NSFont, _ colour: NSColor, in rect: NSRect, align: NSTextAlignment = .left) {
            let style = NSMutableParagraphStyle()
            style.alignment = align
            style.lineBreakMode = .byTruncatingTail
            NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: colour, .paragraphStyle: style]).draw(in: rect)
        }
        if nameField == nil { draw(group.name, Desk.sans(12.5, .semibold), Desk.text, in: nameRect) }
        draw("\(count) cue\(count == 1 ? "" : "s")", Desk.sans(11.5), Desk.dim,
             in: NSRect(x: bounds.width - 70 - controlsWidth, y: 7, width: 60, height: 18), align: .right)
        if isEditing {
            drawSymbol("decrease.indent", centredIn: outRect)
            drawSymbol("increase.indent", centredIn: inRect)
            drawSymbol("trash", centredIn: deleteRect)
            drawSymbol("line.3.horizontal", centredIn: NSRect(x: gripRect.minX, y: 4, width: gripRect.width, height: 22), size: 11)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isEditing {
            if gripRect.contains(point) { return onGrip(self, event) }
            if deleteRect.contains(point) { return onDelete(id) }
            if inRect.contains(point) { return onLevel(id, 1) }
            if outRect.contains(point) { return onLevel(id, -1) }
            if event.clickCount == 2, nameRect.contains(point) { return beginRename() }
            if arrowRect.contains(point) { onToggle(id) }
            return
        }
        onToggle(id)
    }

    // MARK: Renaming

    /// A field over the name, which takes the keyboard: edit mode only.
    /// Return keeps the new name; Escape puts the old one back.
    func beginRename() {
        guard isEditing, nameField == nil, let group else { return }
        let field = NSTextField(string: group.name)
        field.font = Desk.sans(12.5, .semibold)
        field.bezelStyle = .roundedBezel
        field.delegate = self
        field.frame = nameRect.insetBy(dx: -4, dy: -3)
        addSubview(field)
        nameField = field
        needsDisplay = true
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private func endRename(keeping: Bool) {
        guard let field = nameField else { return }
        nameField = nil
        field.removeFromSuperview()
        needsDisplay = true
        if keeping { onRename(id, field.stringValue) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            endRename(keeping: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            endRename(keeping: false)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        endRename(keeping: true)
    }
}

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
    /// Set in with its cue.
    var depth = 0 { didSet { if depth != oldValue { needsDisplay = true } } }
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
        let inset = CGFloat(depth) * CueRowView.indentStep
        if isTaken { draw("\u{2713}", Desk.sans(11.5, .semibold), colour, x: 56 + inset, width: 14) }
        let go = "GO \(index + 1)"
        draw(go, Desk.mono(11.5, .semibold), colour, x: 78 + inset, width: 44)
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
        line.draw(in: NSRect(x: 122 + inset, y: 2, width: bounds.width - 132 - inset, height: 18))
    }

    override func mouseDown(with event: NSEvent) {
        onClick(cue, index)
    }
}
