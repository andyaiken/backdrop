import AppKit
import ImageIO
import ProspectCore
import ProspectStage

/// Where a morph's points are placed, a stage at a time: the stage's two
/// pictures side by side, the same numbered points on each, and beneath them
/// the stage itself, scrubbed through with a slider. A morph of more than two
/// pictures chooses its stage at the top. Click either picture to add a point to both, drag
/// a point to place it on that picture, and Delete removes the one selected.
/// Find Faces matches two faces' features at once.
///
/// One window, for one morph cue at a time, in edit mode only. Every change
/// is one step of undo, as in the console.
final class MorphPointsWindowController: NSWindowController, NSWindowDelegate {
    let cueID: UUID
    private weak var controller: ShowController?
    private let mediaURL: (String) -> URL?
    /// The document's, so Undo here undoes what was done here.
    var undoManagerSource: () -> UndoManager? = { nil }

    private let root = PointsRootView()
    private let hint = Desk.label("Click either picture to add a point to both, then drag it onto the same feature on each. "
                                  + "Select a point and press Delete to remove it.", font: Desk.sans(12.5), colour: Desk.dim, wraps: true)
    private let firstTitle = Desk.label("First picture", font: Desk.sans(12, .semibold), colour: Desk.dim)
    private let secondTitle = Desk.label("Second picture", font: Desk.sans(12, .semibold), colour: Desk.dim)
    /// Which stage: hidden for a morph of two pictures, which has only one.
    private let stageChooser = NSPopUpButton(frame: .zero, pullsDown: false)
    /// The stage whose points are shown: from picture `stage` to the next.
    private(set) var stage = 0
    private let firstView = MorphPointsView()
    private let secondView = MorphPointsView()
    private let previewTitle = Desk.label("The morph", font: Desk.sans(12, .semibold), colour: Desk.dim)
    private let preview = PreviewView()
    private let scrub = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let fromLabel = Desk.label("first", font: Desk.sans(11.5), colour: Desk.dim)
    private let toLabel = Desk.label("second", font: Desk.sans(11.5), colour: Desk.dim)
    private let findFaces = NSButton(title: "Find Faces", target: nil, action: nil)
    private let clearAll = NSButton(title: "Clear All", target: nil, action: nil)
    private let status = Desk.label("", font: Desk.sans(12), colour: Desk.dim, wraps: true)

    private let morph = MorphPreview()
    private var pairs: [MorphPair] = []
    private var selected: Int?
    /// While a point is being dragged, the window's own pairs lead the
    /// show's, which only hear when the drag ends.
    private var dragging = false
    private var pictures: (first: String, second: String)?
    /// The stages the chooser lists, so it is rebuilt only when they change.
    private var stageNames: [String] = []
    private var images: (first: CGImage, second: CGImage)?

    init(controller: ShowController, cueID: UUID, mediaURL: @escaping (String) -> URL?) {
        self.controller = controller
        self.cueID = cueID
        self.mediaURL = mediaURL
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 860, height: 640)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Desk.colour
        window.isReleasedWhenClosed = false
        window.contentView = root
        super.init(window: window)
        window.delegate = self
        window.center()

        for button in [findFaces, clearAll] {
            button.bezelStyle = .rounded
            button.target = self
            button.refusesFirstResponder = true
        }
        stageChooser.target = self
        stageChooser.action = #selector(stageChosen)
        stageChooser.toolTip = "The stage whose points these are: from one picture to the next"
        findFaces.action = #selector(findFacesPressed)
        findFaces.toolTip = "Matches the features of the largest face on each picture: eyes, brows, nose, mouth, jaw and the top of the head"
        clearAll.action = #selector(clearAllPressed)
        scrub.target = self
        scrub.action = #selector(scrubbed)
        scrub.isContinuous = true
        scrub.refusesFirstResponder = true
        scrub.toolTip = "Any moment of the morph, from the first picture to the second"
        for (view, other) in [(firstView, secondView), (secondView, firstView)] {
            view.onAdd = { [weak self] point in self?.add(at: point) }
            view.onSelect = { [weak self] index in self?.select(index) }
            view.onMove = { [weak self] index, point, done in self?.move(index, to: point, onFirst: view === self?.firstView, done: done) }
            view.onDelete = { [weak self] index in self?.delete(index) }
            view.partner = other
        }
        for view in [hint, stageChooser, firstTitle, secondTitle, firstView, secondView, previewTitle, preview, scrub, fromLabel, toLabel,
                     findFaces, clearAll, status] as [NSView] {
            root.addSubview(view)
        }
        root.onLayout = { [weak self] in self?.layout() }
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        undoManagerSource()
    }

    // MARK: Showing the cue

    /// Brings the window up to date with the show, after any edit, an undo
    /// included. Closes it if the cue has gone, stopped being a morph, or
    /// the show has gone into show mode.
    func refresh() {
        guard let controller, controller.mode == .edit, let cue = controller.show[cueID], case .morph(let content) = cue.content else {
            close()
            return
        }
        window?.title = "Morph Points \u{2014} Cue \(cue.number.isEmpty ? "(no number)" : cue.number)"
        stage = min(stage, max(content.stageCount - 1, 0))
        let names = content.pictures.map { MorphContent.name(of: $0.src) }
        let stages = (0..<content.stageCount).map { "Stage \($0 + 1): \(names[$0]) \u{2192} \(names[$0 + 1])" }
        if stages != stageNames {
            stageNames = stages
            stageChooser.removeAllItems()
            stageChooser.addItems(withTitles: stages)
            stageChooser.isHidden = stages.count < 2
            root.needsLayout = true
        }
        if !stages.isEmpty { stageChooser.selectItem(at: stage) }
        firstTitle.stringValue = content.stageCount > 1 ? "Picture \(stage + 1): \(names[stage])" : "First picture"
        secondTitle.stringValue = content.stageCount > 1 ? "Picture \(stage + 2): \(names[stage + 1])" : "Second picture"
        let first = content.pictures.indices.contains(stage) ? content.pictures[stage].src : ""
        let second = content.pictures.indices.contains(stage + 1) ? content.pictures[stage + 1].src : ""
        if pictures?.first != first || pictures?.second != second {
            pictures = (first, second)
            load(first: first, second: second)
        }
        if !dragging { pairs = content.pictures.indices.contains(stage + 1) ? content.pictures[stage + 1].pairs : [] }
        if let selected, selected >= pairs.count { self.selected = nil }
        findFaces.isEnabled = images != nil
        clearAll.isEnabled = !pairs.isEmpty
        showPoints()
        showPreview()
    }

    /// Shows a stage's points, from picture `stage` to the next.
    func show(stage: Int) {
        guard stage != self.stage else { return }
        self.stage = max(stage, 0)
        selected = nil
        refresh()
    }

    @objc private func stageChosen() {
        show(stage: stageChooser.indexOfSelectedItem)
    }

    /// Both pictures, at a size that keeps placing points quick.
    private func load(first: String, second: String) {
        func image(_ path: String) -> CGImage? {
            guard !path.isEmpty, let url = mediaURL(path), let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2048,
                                            kCGImageSourceCreateThumbnailWithTransform: true]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        firstView.image = image(first)
        secondView.image = image(second)
        if let first = firstView.image, let second = secondView.image {
            images = (first, second)
            morph.setPictures(first: first, second: second)
            status.stringValue = morph.isAvailable ? "" : "This Mac can\u{2019}t draw morphs: it has no Metal graphics."
        } else {
            images = nil
            status.stringValue = "The morph needs two pictures at least. Add them in the Cue tab."
        }
    }

    private func showPoints() {
        firstView.points = pairs.map(\.from)
        secondView.points = pairs.map(\.to)
        firstView.selected = selected
        secondView.selected = selected
    }

    private func showPreview() {
        let size = preview.bounds.size, scale = window?.backingScaleFactor ?? 2
        guard images != nil, size.width > 0, size.height > 0 else {
            preview.image = nil
            return
        }
        preview.image = morph.image(pairs: pairs, at: scrub.doubleValue, size: CGSize(width: size.width * scale, height: size.height * scale))
    }

    // MARK: Editing

    private func commit(_ name: String) {
        let pairs = self.pairs, into = stage + 1
        controller?.updateCue(cueID, name) { cue in
            if case .morph(var c) = cue.content, c.pictures.indices.contains(into) {
                c.pictures[into].pairs = pairs
                cue.content = .morph(c)
            }
        }
    }

    /// A new point, on both pictures in the same place to start with, and
    /// ready to drag at once.
    private func add(at point: PicturePoint) {
        pairs.append(MorphPair(from: point, to: point))
        selected = pairs.count - 1
        showPoints()
        showPreview()
        commit("Add Point")
    }

    private func select(_ index: Int?) {
        selected = index
        showPoints()
    }

    private func move(_ index: Int, to point: PicturePoint, onFirst: Bool, done: Bool) {
        guard pairs.indices.contains(index) else { return }
        if onFirst { pairs[index].from = point } else { pairs[index].to = point }
        dragging = !done
        showPoints()
        showPreview()
        if done { commit("Move Point") }
    }

    private func delete(_ index: Int) {
        guard pairs.indices.contains(index) else { return }
        pairs.remove(at: index)
        selected = nil
        commit("Delete Point")
    }

    @objc private func scrubbed() {
        showPreview()
    }

    @objc private func findFacesPressed() {
        guard let images, let window else { return }
        findFaces.isEnabled = false
        status.stringValue = "Looking for faces\u{2026}"
        let (first, second) = images, forStage = stage
        Task.detached(priority: .userInitiated) {
            let found = (FacePoints.find(in: first), FacePoints.find(in: second))
            await MainActor.run { [weak self] in
                // Another stage chosen meanwhile: these faces aren't its.
                guard let self, stage == forStage else { return }
                findFaces.isEnabled = true
                switch found {
                case (nil, nil): status.stringValue = "Neither picture has a face the Mac can find."
                case (nil, _): status.stringValue = "The first picture has no face the Mac can find."
                case (_, nil): status.stringValue = "The second picture has no face the Mac can find."
                case (let a?, let b?):
                    status.stringValue = ""
                    let faces = FacePoints.pairs(a, b)
                    guard !pairs.isEmpty else { return place(faces) }
                    let alert = NSAlert()
                    alert.messageText = "Replace the \(pairs.count) point\(pairs.count == 1 ? "" : "s") already placed with the faces\u{2019} \(faces.count)?"
                    alert.addButton(withTitle: "Replace")
                    alert.addButton(withTitle: "Cancel")
                    alert.beginSheetModal(for: window) { [weak self] response in
                        guard response == .alertFirstButtonReturn else { return }
                        MainActor.assumeIsolated { self?.place(faces) }
                    }
                }
            }
        }
    }

    private func place(_ faces: [MorphPair]) {
        pairs = faces
        selected = nil
        commit("Find Faces")
    }

    @objc private func clearAllPressed() {
        guard let window, !pairs.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Remove all \(pairs.count) point\(pairs.count == 1 ? "" : "s")?"
        alert.informativeText = "Without points the morph is a plain dissolve. Undo brings them back."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pairs = []
                self.selected = nil
                self.commit("Clear Points")
            }
        }
    }

    // MARK: Layout

    private func layout() {
        let b = root.bounds, margin: CGFloat = 20, gap: CGFloat = 16
        let width = b.width - 2 * margin
        var y: CGFloat = 14
        if !stageChooser.isHidden {
            let chooserWidth = min(width, max(260, stageChooser.fittingSize.width))
            stageChooser.frame = NSRect(x: margin, y: y, width: chooserWidth, height: 26)
            y += 34
        }
        hint.frame = NSRect(x: margin, y: y, width: width, height: Desk.height(of: hint, width: width))
        let bottomHeight: CGFloat = 250
        let top = hint.frame.maxY + 12, pictureBottom = b.height - bottomHeight - margin
        let half = (width - gap) / 2
        firstTitle.frame = NSRect(x: margin, y: top, width: half, height: 16)
        secondTitle.frame = NSRect(x: margin + half + gap, y: top, width: half, height: 16)
        firstView.frame = NSRect(x: margin, y: top + 22, width: half, height: max(0, pictureBottom - top - 22))
        secondView.frame = NSRect(x: margin + half + gap, y: top + 22, width: half, height: max(0, pictureBottom - top - 22))

        // Beneath: the morph, at the stage's shape, with its slider.
        let previewHeight = bottomHeight - 22 - 44, previewWidth = (previewHeight * 16 / 9).rounded()
        let previewX = margin + (width - previewWidth) / 2, previewY = pictureBottom + 16
        previewTitle.frame = NSRect(x: previewX, y: previewY, width: previewWidth, height: 16)
        preview.frame = NSRect(x: previewX, y: previewY + 22, width: previewWidth, height: previewHeight)
        scrub.frame = NSRect(x: previewX, y: preview.frame.maxY + 8, width: previewWidth, height: 20)
        fromLabel.frame = NSRect(x: previewX - 70, y: scrub.frame.minY + 2, width: 60, height: 16)
        fromLabel.alignment = .right
        toLabel.frame = NSRect(x: scrub.frame.maxX + 10, y: scrub.frame.minY + 2, width: 60, height: 16)
        toLabel.alignment = .left
        let buttonsWidth = findFaces.fittingSize.width + clearAll.fittingSize.width + 8
        findFaces.frame = NSRect(x: b.width - margin - buttonsWidth, y: preview.frame.minY, width: findFaces.fittingSize.width, height: 28)
        clearAll.frame = NSRect(x: findFaces.frame.maxX + 8, y: preview.frame.minY, width: clearAll.fittingSize.width, height: 28)
        status.frame = NSRect(x: b.width - margin - 240, y: findFaces.frame.maxY + 10, width: 240, height: Desk.height(of: status, width: 240))
        showPreview()
    }
}

/// The window's content: the desk's colour, flipped, and laid out by the
/// window controller.
final class PointsRootView: NSView {
    var onLayout: () -> Void = {}
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Desk.colour.setFill()
        dirtyRect.fill()
    }

    override func layout() {
        super.layout()
        onLayout()
    }
}

/// The morph at the slider's moment, on black, as the stage shows it.
final class PreviewView: NSView {
    var image: CGImage? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        if let image, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.interpolationQuality = .high
            ctx.draw(image, in: bounds)
        }
        Desk.lineBright.setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
}

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
