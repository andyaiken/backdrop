import AppKit
import BackdropCore

/// The Studio's storyboard: every cue's finished frame in a grid, labelled
/// with its number, in place of the stage. A click stands a cue by; a
/// double-click goes back to the stage with it.
@MainActor
final class StoryboardView: NSScrollView {
    private let grid = StoryboardGrid()
    let thumbnails = ThumbnailCache(width: 320)

    var onSelect: (UUID) -> Void = { _ in } { didSet { grid.onSelect = onSelect } }
    var onOpen: (UUID) -> Void = { _ in } { didSet { grid.onOpen = onOpen } }

    init() {
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = true
        autohidesScrollers = true
        documentView = grid
        thumbnails.onReady = { [weak self] _ in self?.grid.needsDisplay = true }
        grid.image = { [weak self] cue in self?.thumbnails.image(for: cue, settings: self?.settings ?? ShowSettings()) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var settings = ShowSettings()

    func update(cues: [Cue], settings: ShowSettings, standby: UUID?) {
        if cues != grid.cues || settings != self.settings {
            self.settings = settings
            grid.cues = cues
            thumbnails.request(cues, settings: settings, onScreen: [])
        }
        grid.standby = standby
        layoutGrid()
    }

    override func layout() {
        super.layout()
        layoutGrid()
    }

    private func layoutGrid() {
        grid.frame = NSRect(x: 0, y: 0, width: contentSize.width, height: max(contentSize.height, grid.height(for: contentSize.width)))
        grid.needsDisplay = true
    }
}

/// The frames themselves, drawn.
private final class StoryboardGrid: NSView {
    var cues: [Cue] = [] { didSet { needsDisplay = true } }
    var standby: UUID? { didSet { needsDisplay = true } }
    var image: (Cue) -> CGImage? = { _ in nil }
    var onSelect: (UUID) -> Void = { _ in }
    var onOpen: (UUID) -> Void = { _ in }

    static let cell = NSSize(width: 200, height: 112 + 24)
    static let gap: CGFloat = 16

    override var isFlipped: Bool { true }

    private func columns(for width: CGFloat) -> Int { max(1, Int((width + Self.gap) / (Self.cell.width + Self.gap))) }

    func height(for width: CGFloat) -> CGFloat {
        let rows = (cues.count + columns(for: width) - 1) / columns(for: width)
        return CGFloat(rows) * (Self.cell.height + Self.gap) + Self.gap
    }

    private func frame(of index: Int) -> NSRect {
        let columns = columns(for: bounds.width)
        let used = CGFloat(columns) * Self.cell.width + CGFloat(columns - 1) * Self.gap
        let left = max(0, (bounds.width - used) / 2)
        return NSRect(x: left + CGFloat(index % columns) * (Self.cell.width + Self.gap),
                      y: Self.gap + CGFloat(index / columns) * (Self.cell.height + Self.gap),
                      width: Self.cell.width, height: Self.cell.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, cue) in cues.enumerated() {
            let cell = frame(of: i)
            guard cell.intersects(dirtyRect) else { continue }
            let picture = NSRect(x: cell.minX, y: cell.minY, width: cell.width, height: cell.width * 9 / 16)
            let path = NSBezierPath(roundedRect: picture, xRadius: 6, yRadius: 6)
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            NSColor.black.setFill()
            picture.fill()
            if let image = image(cue), let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.translateBy(x: picture.minX, y: picture.maxY)
                context.scaleBy(x: 1, y: -1)
                context.draw(image, in: CGRect(x: 0, y: 0, width: picture.width, height: picture.height))
                context.restoreGState()
            }
            NSGraphicsContext.restoreGraphicsState()
            let standing = cue.id == standby
            (standing ? Room.studio.brass : Room.studio.line).setStroke()
            path.lineWidth = standing ? 2.5 : 1
            path.stroke()
            let label = NSAttributedString(string: "\(cue.number)  \(CueText.name(cue))", attributes: [
                .font: Desk.mono(12, standing ? .semibold : .regular),
                .foregroundColor: standing ? Room.studio.brass : Room.studio.ink,
            ])
            label.draw(with: NSRect(x: cell.minX, y: picture.maxY + 5, width: cell.width, height: 16),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let i = cues.indices.first(where: { frame(of: $0).contains(point) }) else { return }
        if event.clickCount > 1 { onOpen(cues[i].id) } else { onSelect(cues[i].id) }
    }
}
