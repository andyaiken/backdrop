import AppKit
import QuartzCore
import SwiftUI

/// A show with no cues: the app's model box in perspective, an empty stage
/// with the wordmark decrypting on its back wall, and under it what to do.
/// Pictures and clips dropped on it start the sheet.
@MainActor
final class BareStage: NSView {
    private let wordmark = WordmarkView()
    private let model = CALayer()
    private let note = NSHostingView(rootView: BareStageNote())
    /// Files dropped, to start the sheet with.
    var onDrop: ([URL]) -> Void = { _ in }
    var onAddCue: () -> Void = {} {
        didSet { note.rootView = BareStageNote(onAddCue: onAddCue) }
    }
    private var dragged: MediaDrop?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(model)
        addSubview(wordmark)
        addSubview(note)
        registerForDraggedTypes(MediaDrop.pasteboardTypes)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func decrypt() { wordmark.decryptWordmark() }

    #if DEBUG
    func holdWordmark(atFrame frame: Int) { wordmark.holdWordmark(atFrame: frame) }
    #endif

    override func layout() {
        super.layout()
        let noteHeight: CGFloat = 80
        let room = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - noteHeight))
        // The box at 16:9, as large as fits, centred.
        let w = min(room.width, room.height * 16 / 9), h = w * 9 / 16
        let box = NSRect(x: (room.width - w) / 2, y: (room.height - h) / 2, width: w, height: h)
        // The back wall: the far end of the stage, where the wordmark plays.
        let back = box.insetBy(dx: w * 0.2, dy: h * 0.2).offsetBy(dx: 0, dy: -h * 0.04)
        wordmark.frame = back
        drawModel(box: box, back: back)
        note.frame = NSRect(x: 0, y: room.maxY, width: bounds.width, height: noteHeight)
    }

    /// The model box: a floor of boards, two side walls and a ceiling, drawn
    /// from the front edges to the back wall.
    private func drawModel(box: NSRect, back: NSRect) {
        model.sublayers?.forEach { $0.removeFromSuperlayer() }
        model.frame = bounds
        // The view is flipped, and its layer with it, so the paths are drawn
        // top down as they are worked out.
        func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, fill: CGColor, stroke: CGColor? = nil) {
            let shape = CAShapeLayer()
            let path = CGMutablePath()
            path.addLines(between: [a, b, c, d])
            path.closeSubpath()
            shape.path = path
            shape.fillColor = fill
            shape.strokeColor = stroke
            shape.lineWidth = 1
            model.addSublayer(shape)
        }
        let tl = CGPoint(x: box.minX, y: box.minY), tr = CGPoint(x: box.maxX, y: box.minY)
        let bl = CGPoint(x: box.minX, y: box.maxY), br = CGPoint(x: box.maxX, y: box.maxY)
        let btl = CGPoint(x: back.minX, y: back.minY), btr = CGPoint(x: back.maxX, y: back.minY)
        let bbl = CGPoint(x: back.minX, y: back.maxY), bbr = CGPoint(x: back.maxX, y: back.maxY)
        let wall = CGColor(red: 0.09, green: 0.12, blue: 0.20, alpha: 1)
        let side = CGColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 1)
        let line = CGColor(red: 0.86, green: 0.71, blue: 0.42, alpha: 0.5)
        quad(tl, tr, btr, btl, fill: side, stroke: line)              // the ceiling
        quad(tl, btl, bbl, bl, fill: wall, stroke: line)              // the left wall
        quad(tr, btr, bbr, br, fill: wall, stroke: line)              // the right wall
        quad(bl, bbl, bbr, br, fill: CGColor(red: 0.36, green: 0.25, blue: 0.14, alpha: 1), stroke: line) // the floor
        // The floor's boards, running back to the wall.
        for i in 1..<8 {
            let t = CGFloat(i) / 8
            let shape = CAShapeLayer()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: bl.x + (br.x - bl.x) * t, y: bl.y))
            path.addLine(to: CGPoint(x: bbl.x + (bbr.x - bbl.x) * t, y: bbl.y))
            shape.path = path
            shape.strokeColor = CGColor(red: 0.2, green: 0.13, blue: 0.07, alpha: 1)
            shape.lineWidth = 1
            model.addSublayer(shape)
        }
    }

    // MARK: Dropping

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dragged = MediaDrop(sender.draggingPasteboard)
        let usable = (dragged?.types ?? []).contains { ShowDocument.cueKind(for: $0) != nil }
        return usable ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { dragged = nil }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let offer = dragged else { return false }
        dragged = nil
        offer.receive { [weak self] urls in
            let usable = urls.filter { ShowDocument.cueKind(for: $0) != nil }
            if !usable.isEmpty { self?.onDrop(usable) }
        }
        return true
    }
}

/// Under the bare stage: what to do first.
struct BareStageNote: View {
    var onAddCue: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            Text("Drop pictures and clips onto the stage, or add a cue.")
                .foregroundStyle(.secondary)
            Button("+ Add cue", action: onAddCue).focusable(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
