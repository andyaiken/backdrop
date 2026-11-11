import AppKit
import BackdropCore

/// The cue sheet as it reads: every cue in running order, and under the live
/// or standby cue the GOs it waits for. In edit mode a cue is dragged by its
/// grip to anywhere in the sheet, and pictures and clips dragged in from
/// Finder become cues where they are dropped.
final class CueListView: NSScrollView {
    private let document = PanelView()
    private var cueRows: [UUID: CueRowView] = [:]
    /// The GOs of the cues whose sub-cues are open: live or standing by.
    private var steps: [UUID: [SubCueRowView]] = [:]
    private var shown: [Cue] = []
    private var shownNotes: [String?] = []
    private var shownEditing = false
    /// The transition rows on screen, by the cue they sit above.
    private var transitionRows: [UUID: TransitionRowView] = [:]
    /// The cue rows on screen, in sheet order.
    private var visible: [CueRowView] = []

    var onClick: (UUID) -> Void = { _ in }
    /// A sub-cue clicked: its cue, and which GO.
    var onStepClick: (UUID, Int) -> Void = { _, _ in }
    /// A picture or clip dropped on a cue that takes it, as its file.
    var onDrop: (URL, UUID) -> Void = { _, _ in }
    /// Files dropped between cues, to be new cues standing before the cue
    /// at this index, or at the end.
    var onDropFiles: ([URL], Int) -> Void = { _, _ in }
    var onDelete: (UUID) -> Void = { _ in }
    var onDuplicate: (UUID) -> Void = { _ in }
    /// A transition row clicked: the cue it leads into.
    var onTransitionClick: (UUID) -> Void = { _ in }
    /// A transition row's menu: put the cue's transition back to the standard.
    var onClearTransition: (UUID) -> Void = { _ in }
    /// A cue dragged to stand before the cue at this index, or at the end.
    var onMoveCue: (UUID, Int) -> Void = { _, _ in }
    /// Renumber every cue: the console asks first.
    var onRenumberAll: () -> Void = {}
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
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// - Parameters:
    ///   - standbyStep: The GO of the standby cue that stands by, if one does.
    ///   - taken: How many of the live cue's GOs it has reached.
    ///   - selectedTransition: The cue whose transition in is selected, if one is.
    func update(show: Show, standby: UUID?, standbyStep: Int?, live: UUID?, taken: Int, issues: Set<UUID>, editing: Bool,
                selectedTransition: UUID? = nil) {
        let cues = show.cues
        // Edit mode puts a transition between each pair of cues, so none above the first.
        let notes: [String?] = cues.enumerated().map { i, cue in
            editing && i > 0 ? TransitionRowView.note(for: cue) : nil
        }
        if cues != shown || notes != shownNotes || editing != shownEditing {
            cueRows.values.forEach { $0.removeFromSuperview() }
            transitionRows.values.forEach { $0.removeFromSuperview() }
            cueRows = [:]
            transitionRows = [:]
            for (cue, note) in zip(cues, notes) {
                if let note {
                    let transition = TransitionRowView(cue: cue.id, note: note, isChanged: cue.transition != .standard)
                    transition.onClick = { [weak self] in self?.onTransitionClick($0) }
                    transition.onClear = { [weak self] in self?.onClearTransition($0) }
                    document.addSubview(transition, positioned: .below, relativeTo: insertion)
                    transitionRows[cue.id] = transition
                }
                let row = CueRowView(cue: cue)
                row.onClick = { [weak self] in self?.onClick($0) }
                row.onDelete = { [weak self] in self?.onDelete($0) }
                row.onGrip = { [weak self] row, event in self?.drag(row, from: event) }
                row.onMenu = { [weak self] id in self?.menu(forCue: id) }
                document.addSubview(row, positioned: .below, relativeTo: insertion)
                cueRows[cue.id] = row
            }
            shown = cues
            shownNotes = notes
            shownEditing = editing
        }
        for (id, row) in transitionRows { row.isSelected = id == selectedTransition }
        var open: [UUID: [SubCueRowView]] = [:]
        for row in cueRows.values {
            let id = row.cue.id
            row.isStandby = id == standby && standbyStep == nil
            row.isLive = id == live
            row.hasIssue = issues.contains(id)
            row.isEditing = editing
            // A cue's GOs open out while it is live or standing by, and fold
            // to a count otherwise.
            let points = row.cue.goPoints()
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

    // MARK: Right-click menus

    /// A cue's: renumber every cue in the sheet.
    private func menu(forCue id: UUID) -> NSMenu? {
        let menu = NSMenu()
        let copy = NSMenuItem(title: "Duplicate Cue", action: #selector(duplicatePicked(_:)), keyEquivalent: "")
        copy.target = self
        copy.representedObject = id
        menu.addItem(copy)
        menu.addItem(.separator())
        let all = NSMenuItem(title: "Renumber All Cues\u{2026}", action: #selector(renumberPicked(_:)), keyEquivalent: "")
        all.target = self
        menu.addItem(all)
        return menu
    }

    #if DEBUG
    /// The right-click menu's items, for the document check.
    func menuTitles(forCue id: UUID) -> [String] { menu(forCue: id)?.items.map(\.title) ?? [] }
    #endif

    @objc private func duplicatePicked(_ item: NSMenuItem) {
        if let id = item.representedObject as? UUID { onDuplicate(id) }
    }

    @objc private func renumberPicked(_ item: NSMenuItem) {
        onRenumberAll()
    }

    override func layout() {
        super.layout()
        layoutRows()
    }

    // MARK: Reordering

    /// Follows the pointer from a row's grip until the button comes up,
    /// showing where the row will land, then moves the cue there.
    private func drag(_ row: CueRowView, from event: NSEvent) {
        guard let window, let from = visible.firstIndex(where: { $0 === row }) else { return }
        row.isLifted = true
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
        row.isLifted = false
        insertion.isHidden = true
        guard let landed, landed != from, landed != from + 1 else { return }
        onMoveCue(row.cue.id, landed)
    }

    /// Where a dragged row would go: before the first row on screen whose
    /// middle is below the pointer, or at the end.
    private func slot(at y: CGFloat) -> Int {
        visible.firstIndex { y < $0.frame.midY } ?? visible.count
    }

    // MARK: Dropping files

    /// Where files dragged over the list would go.
    private enum Drop: Equatable {
        /// Onto a cue that takes the file, as its picture or clip.
        case onto(UUID)
        /// New cues, standing before the cue at this index, or at the end.
        case before(Int)
    }

    /// The files being dragged over the list, in edit mode.
    private var dragged: [URL] = []
    private var drop: Drop? { didSet { if drop != oldValue { showDrop() } } }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dragged = shownEditing ? sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [] : []
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        autoscroll(toward: sender)
        drop = target(at: document.convert(sender.draggingLocation, from: nil))
        return drop == nil ? [] : .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        endDrop()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        endDrop()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = dragged, target = drop
        endDrop()
        switch target {
        case .onto(let id):
            guard let url = urls.first(where: { ShowDocument.cueKind(for: $0) != nil }) else { return false }
            onDrop(url, id)
        case .before(let index):
            onDropFiles(urls, index)
        case nil:
            return false
        }
        return true
    }

    /// A single picture or clip over the middle of a cue that takes it goes
    /// to that cue. Anywhere else, over the top or bottom edge of a row,
    /// between rows or below them, the files make new cues there.
    private func target(at point: NSPoint) -> Drop? {
        let usable = dragged.filter { ShowDocument.cueKind(for: $0) != nil }
        guard shownEditing, !usable.isEmpty else { return nil }
        if usable.count == 1, let row = visible.first(where: { $0.frame.contains(point) }),
           row.takesMedia, ShowDocument.accepts(usable[0], for: row.cue.kind) {
            let edge = min(10, row.frame.height / 4)
            if point.y > row.frame.minY + edge, point.y < row.frame.maxY - edge { return .onto(row.cue.id) }
        }
        return .before(slot(at: point.y))
    }

    private func showDrop() {
        for row in cueRows.values { row.isTargeted = drop == .onto(row.cue.id) }
        if case .before(let index) = drop { showInsertion(at: index) } else { insertion.isHidden = true }
    }

    private func endDrop() {
        dragged = []
        drop = nil
    }

    /// Near the top or bottom of the list a drag scrolls it, so files can be
    /// dropped anywhere in a long sheet.
    private func autoscroll(toward sender: any NSDraggingInfo) {
        let clip = contentView, shownRect = clip.bounds
        let y = clip.convert(sender.draggingLocation, from: nil).y
        let edge: CGFloat = 24
        let step: CGFloat = y < shownRect.minY + edge ? -10 : y > shownRect.maxY - edge ? 10 : 0
        guard step != 0 else { return }
        let top = min(max(shownRect.minY + step, 0), max(document.frame.height - shownRect.height, 0))
        guard top != shownRect.minY else { return }
        clip.scroll(to: NSPoint(x: shownRect.minX, y: top))
        reflectScrolledClipView(clip)
    }

    private func showInsertion(at slot: Int) {
        let bottom = document.subviews.filter { !$0.isHidden && $0 !== insertion }.map(\.frame.maxY).max() ?? 0
        // Above the cue's transition row, which travels with it.
        let y = slot < visible.count ? (transitionRows[visible[slot].cue.id] ?? visible[slot]).frame.minY - 2.5 : bottom + 0.5
        insertion.frame = NSRect(x: 6, y: y, width: document.bounds.width - 12, height: 2)
        insertion.isHidden = false
    }

    /// Every cue in sheet order, each with its open GOs beneath it.
    private func layoutRows() {
        let width = contentSize.width
        var y: CGFloat = 0
        visible = []
        cueRows.values.forEach { $0.isHidden = true }
        transitionRows.values.forEach { $0.isHidden = true }
        steps.values.joined().forEach { $0.isHidden = true }
        for cue in shown {
            guard let row = cueRows[cue.id] else { continue }
            if let transition = transitionRows[cue.id] {
                transition.isHidden = false
                transition.frame = NSRect(x: 0, y: y, width: width, height: TransitionRowView.height)
                y += TransitionRowView.height
            }
            row.isHidden = false
            row.frame = NSRect(x: 0, y: y, width: width, height: row.preferredHeight)
            y += row.preferredHeight + 3
            visible.append(row)
            for sub in steps[cue.id] ?? [] {
                sub.isHidden = false
                sub.frame = NSRect(x: 0, y: y, width: width, height: SubCueRowView.height)
                y += SubCueRowView.height + 1
            }
        }
        document.frame = NSRect(x: 0, y: 0, width: width, height: max(y, contentSize.height))
    }
}
