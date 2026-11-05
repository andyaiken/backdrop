import AppKit
import ProspectCore

/// Where a picture or clip is dropped: shows the file a cue has, and takes
/// a new one from Finder.
final class MediaWell: NSView {
    var onDrop: (URL) -> Void = { _ in }
    private var kind = Cue.Kind.image
    private var text = ""
    private var hasFile = false
    private var targeted = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(path: String, kind: Cue.Kind, empty: String) {
        self.kind = kind
        hasFile = !path.isEmpty
        text = hasFile ? (path as NSString).lastPathComponent : empty
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        (targeted ? Desk.raised : Desk.sunk).setFill()
        path.fill()
        (targeted ? Desk.brass : Desk.lineBright).setStroke()
        path.setLineDash([3, 3], count: 2, phase: 0)
        path.stroke()
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        let attributed = NSAttributedString(string: text, attributes: [
            .font: hasFile ? Desk.mono(12) : Desk.sans(12), .foregroundColor: hasFile ? Desk.text : Desk.dim, .paragraphStyle: style,
        ])
        let size = attributed.size()
        attributed.draw(in: NSRect(x: 10, y: (bounds.height - size.height) / 2, width: bounds.width - 20, height: size.height))
    }

    private func droppedURL(_ info: any NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        guard let url = urls?.first, ShowDocument.accepts(url, for: kind) else { return nil }
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
        onDrop(url)
        return true
    }
}
