import AppKit
import BackdropCore
import BackdropStage
import os

/// The cue sheet as it reads, in both rooms: every cue in running order,
/// with a join between each pair saying how the stage changes, and under the
/// live or standby cue the GOs it waits for. A cue that runs on by itself is
/// linked to the next by a brass spine between their margin boxes.
///
/// In the Studio a cue is dragged by its grip to anywhere in the sheet, a +
/// between rows adds one there, and pictures and clips dragged in from
/// Finder, Photos, Safari or another app become cues where they are dropped.
final class CueListView: NSScrollView {
    private let document = RailDocument()
    private var cueRows: [UUID: CueRowView] = [:]
    /// The GOs of the cues whose steps are open: live or standing by.
    private var steps: [UUID: [SubCueRowView]] = [:]
    private var shown: [Cue] = []
    private var shownBooth = false
    /// The joins on screen, by the cue they lead into.
    private var joins: [UUID: JoinView] = [:]
    /// The Studio's + above the first cue.
    private var lead: JoinView?
    /// Below the last cue: the + to add one at the end.
    private var tail: JoinView?
    /// The cue rows on screen, in sheet order.
    private var visible: [CueRowView] = []
    private var room = Room.studio
    private var settings = ShowSettings()
    /// Under the chain that starts at the standby cue, in the Booth: what
    /// one GO runs.
    private let reachLine: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = Desk.sans(11.5)
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    private var reachAfter: UUID?
    /// Where files dropped now would land, opened out.
    private let slot = DropSlot()
    let thumbnails = ThumbnailCache()

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
    /// A join clicked: the cue it leads into.
    var onTransitionClick: (UUID) -> Void = { _ in }
    /// A join's menu: put the cue's transition back to the standard.
    var onClearTransition: (UUID) -> Void = { _ in }
    /// A cue dragged to stand before the cue at this index, or at the end.
    var onMoveCue: (UUID, Int) -> Void = { _, _ in }
    /// A cue moved a place up or down, by VoiceOver.
    var onMoveBy: (UUID, Int) -> Void = { _, _ in }
    /// A + between rows: add a cue after this index, or at the start for -1.
    var onInsert: (Int) -> Void = { _ in }
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
        slot.isHidden = true
        reachLine.isHidden = true
        document.addSubview(reachLine)
        document.addSubview(slot)
        document.addSubview(insertion)
        registerForDraggedTypes(MediaDrop.pasteboardTypes)
        thumbnails.onReady = { [weak self] id in
            guard let self, let row = self.cueRows[id] else { return }
            row.thumbnail = self.thumbnails.image(for: row.cue, settings: self.settings)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static let log = OSLog(subsystem: "Backdrop", category: .pointsOfInterest)

    /// - Parameters:
    ///   - standbyStep: The GO of the standby cue that stands by, if one does.
    ///   - taken: How many of the live cue's GOs it has reached.
    ///   - issues: What is wrong with each cue that has an issue.
    ///   - selectedTransition: The cue whose transition in is selected, if one is.
    func update(show: Show, standby: UUID?, standbyStep: Int?, live: UUID?, taken: Int, issues: [UUID: String],
                room: ShowController.Mode, selectedTransition: UUID? = nil) {
        let signpost = OSSignpostID(log: Self.log)
        os_signpost(.begin, log: Self.log, name: "Rail update", signpostID: signpost)
        defer { os_signpost(.end, log: Self.log, name: "Rail update", signpostID: signpost) }

        let cues = show.cues
        let booth = room == .show
        let palette = Desk.room(room)
        let paletteChanged = palette.background != self.room.background
        self.room = palette
        let settingsChanged = show.settings != settings
        settings = show.settings
        // Rows are made again only when the sheet or the room changed.
        let rebuilt = cues != shown || booth != shownBooth
        if rebuilt {
            rebuild(cues, booth: booth)
        }
        if rebuilt || settingsChanged {
            for row in cueRows.values { row.thumbnail = thumbnails.image(for: row.cue, settings: settings) }
            let onScreen = Set(cueRows.values.filter { !$0.visibleRect.isEmpty }.map(\.cue.id))
            thumbnails.request(cues, settings: settings, onScreen: onScreen)
        }
        if paletteChanged || rebuilt {
            for row in cueRows.values { row.room = palette }
            for join in joins.values { join.room = palette }
            lead?.room = palette
            tail?.room = palette
            document.room = palette
            reachLine.textColor = palette.dim
            slot.room = palette
        }
        for (id, join) in joins { join.isSelected = id == selectedTransition }
        var open: [UUID: [SubCueRowView]] = [:]
        for row in cueRows.values {
            let id = row.cue.id
            row.isStandby = id == standby && standbyStep == nil
            row.isLive = id == live
            row.issue = issues[id]
            row.isEditing = !booth
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
                    document.addSubview(sub, positioned: .below, relativeTo: reachLine)
                    return sub
                }
            }
            for sub in subRows {
                sub.room = palette
                sub.isStandby = id == standby && standbyStep == sub.index
                sub.isTaken = id == live && sub.index < taken
            }
            open[id] = subRows
        }
        for (id, subRows) in steps where open[id] == nil { subRows.forEach { $0.removeFromSuperview() } }
        steps = open

        // What one GO runs, under the chain that starts at the standby cue.
        let reach = booth ? standby.map { show.reach(from: $0) } ?? [] : []
        if reach.count > 1, let first = reach.first, let last = reach.last {
            reachLine.stringValue = CueText.reach(reach)?.replacingOccurrences(of: "One GO runs", with: "One GO on cue \(first.cue.number) runs") ?? ""
            reachAfter = last.cue.id
        } else {
            reachAfter = nil
        }
        reachLine.isHidden = reachAfter == nil

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

    /// Every row and join made afresh, for a changed sheet or room.
    private func rebuild(_ cues: [Cue], booth: Bool) {
        cueRows.values.forEach { $0.removeFromSuperview() }
        joins.values.forEach { $0.removeFromSuperview() }
        lead?.removeFromSuperview()
        tail?.removeFromSuperview()
        cueRows = [:]
        joins = [:]
        lead = nil
        tail = nil
        if !booth, !cues.isEmpty {
            func end(after: Int) -> JoinView {
                let join = JoinView(cue: nil, transition: nil, link: nil, after: after)
                join.isEditing = true
                join.onInsert = { [weak self] in self?.onInsert($0) }
                document.addSubview(join, positioned: .below, relativeTo: reachLine)
                return join
            }
            lead = end(after: -1)
            tail = end(after: cues.count - 1)
        }
        for (i, cue) in cues.enumerated() {
            if i > 0 {
                let join = JoinView(cue: cue.id, transition: cue.transition, link: JoinView.link(for: cues[i - 1].continueMode),
                                    after: i - 1)
                join.isEditing = !booth
                join.onClick = { [weak self] in self?.onTransitionClick($0) }
                join.onClear = { [weak self] in self?.onClearTransition($0) }
                join.onInsert = { [weak self] in self?.onInsert($0) }
                document.addSubview(join, positioned: .below, relativeTo: reachLine)
                joins[cue.id] = join
            }
            let row = CueRowView(cue: cue)
            row.isBooth = booth
            row.onClick = { [weak self] in self?.onClick($0) }
            row.onDelete = { [weak self] in self?.onDelete($0) }
            row.onGrip = { [weak self] row, event in self?.drag(row, from: event) }
            row.onMenu = { [weak self] id in self?.menu(forCue: id) }
            row.onMove = { [weak self] id, by in self?.onMoveBy(id, by) }
            document.addSubview(row, positioned: .below, relativeTo: reachLine)
            cueRows[cue.id] = row
        }
        shown = cues
        shownBooth = booth
    }

    #if DEBUG
    /// For snapshots, which have no pointer: a row as if under it.
    func pretendHovered(_ id: UUID) {
        cueRows[id]?.pretendHovered(true)
    }

    /// For snapshots: the slot files would open, as if they were dragged in.
    func pretendDrop(count: Int, before index: Int) {
        dropCount = count
        drop = index < 0 ? nil : .before(index)
    }
    #endif

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

    /// What is being dragged over the list, in edit mode: files from Finder,
    /// or pictures and clips from Photos, Safari or another app.
    private var dragged: MediaDrop?
    private var drop: Drop? { didSet { if drop != oldValue { showDrop() } } }
    /// How many usable files are being dragged, for the slot's words.
    private var dropCount = 0

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dragged = shownBooth ? nil : MediaDrop(sender.draggingPasteboard)
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

    /// Promised files arrive after the drop, so the cues are made then, at
    /// the place the drop was aimed.
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let offer = dragged, let target = drop else {
            endDrop()
            return false
        }
        endDrop()
        offer.receive { [weak self] urls in
            guard let self else { return }
            switch target {
            case .onto(let id):
                if let url = urls.first(where: { ShowDocument.cueKind(for: $0) != nil }) { onDrop(url, id) }
            case .before(let index):
                if !urls.isEmpty { onDropFiles(urls, index) }
            }
        }
        return true
    }

    /// A single picture or clip over the middle of a cue that takes it goes
    /// to that cue. Anywhere else, over the top or bottom edge of a row,
    /// between rows or below them, the files make new cues there.
    private func target(at point: NSPoint) -> Drop? {
        let usable = (dragged?.types ?? []).filter { ShowDocument.cueKind(for: $0) != nil }
        dropCount = usable.count
        guard !shownBooth, !usable.isEmpty else { return nil }
        if usable.count == 1, let row = visible.first(where: { $0.frame.contains(point) }),
           row.takesMedia, ShowDocument.accepts(usable[0], for: row.cue.kind) {
            let edge = min(10, row.frame.height / 4)
            if point.y > row.frame.minY + edge, point.y < row.frame.maxY - edge { return .onto(row.cue.id) }
        }
        return .before(slot(at: point.y))
    }

    /// Over a cue that takes the file, that row says so. Between rows, a
    /// slot opens where the files would go, and the rows below move down.
    private func showDrop() {
        for row in cueRows.values { row.isTargeted = drop == .onto(row.cue.id) }
        if case .before = drop {
            slot.count = dropCount
        }
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animate ? 0.18 : 0
            context.allowsImplicitAnimation = animate
            layoutRows(animated: animate)
        }
    }

    private func endDrop() {
        dragged = nil
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
        // Above the cue's join, which travels with it.
        let y = slot < visible.count ? (joins[visible[slot].cue.id] ?? visible[slot]).frame.minY - 2.5 : bottom + 0.5
        insertion.frame = NSRect(x: 6, y: y, width: document.bounds.width - 12, height: 2)
        insertion.isHidden = false
    }

    /// Every cue in sheet order: the join into it, the cue, then its open
    /// GOs. While files are dragged between rows, a slot opens where they
    /// would land.
    private func layoutRows(animated: Bool = false) {
        let width = contentSize.width
        var y: CGFloat = 0
        visible = []
        cueRows.values.forEach { $0.isHidden = true }
        joins.values.forEach { $0.isHidden = true }
        steps.values.joined().forEach { $0.isHidden = true }
        var spines: [(from: CGFloat, to: CGFloat)] = []
        var boxes: [UUID: CGFloat] = [:]
        let slotAt: Int? = if case .before(let index) = drop { index } else { nil }
        slot.isHidden = slotAt == nil
        func place(_ view: NSView, _ frame: NSRect) {
            if animated { view.animator().frame = frame } else { view.frame = frame }
        }
        if let lead {
            lead.isHidden = false
            place(lead, NSRect(x: 0, y: y, width: width, height: JoinView.leadHeight))
            y += JoinView.leadHeight
        }
        for (i, cue) in shown.enumerated() {
            guard let row = cueRows[cue.id] else { continue }
            if slotAt == i {
                place(slot, NSRect(x: 0, y: y, width: width, height: DropSlot.height))
                y += DropSlot.height
            }
            if let join = joins[cue.id] {
                join.isHidden = false
                let h = join.link == nil ? JoinView.height : JoinView.linkedHeight
                place(join, NSRect(x: 0, y: y, width: width, height: h))
                y += h
            }
            row.isHidden = false
            let h = row.preferredHeight(width: width)
            place(row, NSRect(x: 0, y: y, width: width, height: h))
            boxes[cue.id] = y + row.boxRect.midY
            y += h
            visible.append(row)
            for sub in steps[cue.id] ?? [] {
                sub.isHidden = false
                place(sub, NSRect(x: 0, y: y, width: width, height: SubCueRowView.height))
                y += SubCueRowView.height
            }
            if reachAfter == cue.id {
                reachLine.frame = NSRect(x: CueRowView.textX, y: y + 2, width: max(0, width - CueRowView.textX - 10), height: 16)
                y += 20
            }
        }
        if slotAt == shown.count {
            place(slot, NSRect(x: 0, y: y, width: width, height: DropSlot.height))
            y += DropSlot.height
        }
        if let tail {
            tail.isHidden = false
            place(tail, NSRect(x: 0, y: y, width: width, height: JoinView.leadHeight))
            y += JoinView.leadHeight
        }
        // A spine from each cue that runs on to the next one's margin box.
        for (i, cue) in shown.enumerated() where i + 1 < shown.count && cue.continueMode.continues {
            if let from = boxes[cue.id], let to = boxes[shown[i + 1].id] { spines.append((from, to)) }
        }
        document.spines = spines
        document.frame = NSRect(x: 0, y: 0, width: width, height: max(y + 8, contentSize.height))
    }
}

/// The rail's own surface: the spines that link one cue's margin box to the
/// next when it runs on by itself, drawn under the rows.
final class RailDocument: NSView {
    var spines: [(from: CGFloat, to: CGFloat)] = [] { didSet { needsDisplay = true } }
    var room = Room.studio { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        room.brass.setFill()
        let x = CueRowView.boxX + CueRowView.box.width / 2 - 1
        for spine in spines {
            NSRect(x: x, y: spine.from, width: 2, height: spine.to - spine.from).fill()
        }
    }
}

/// Where files dragged over the rail would land: "Drop to add 3 cues here".
final class DropSlot: NSView {
    static let height: CGFloat = 28
    var count = 0 { didSet { needsDisplay = true } }
    var room = Room.studio { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 6, dy: 3)
        let path = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)
        room.brass.withAlphaComponent(0.12).setFill()
        path.fill()
        path.setLineDash([4, 3], count: 2, phase: 0)
        room.brass.setStroke()
        path.stroke()
        let words = "Drop to add \(count) cue\(count == 1 ? "" : "s") here"
        let text = NSAttributedString(string: words, attributes: [.font: Desk.sans(11.5, .semibold), .foregroundColor: room.brass])
        let size = text.size()
        text.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
    }
}
