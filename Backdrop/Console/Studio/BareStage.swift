import AppKit
import BackdropStage
import SwiftUI

/// A show with no cues: the wordmark decrypting on a plain preview screen,
/// and under it what to do. Pictures and clips dropped on it start the sheet.
@MainActor
final class BareStage: NSView {
    private let wordmark = WordmarkView()
    private let screen = PanelView(fill: .black, border: Desk.line, radius: Desk.previewRadius)
    private let note = NSHostingView(rootView: BareStageNote())
    /// Files dropped, to start the sheet with.
    var onDrop: ([URL]) -> Void = { _ in }
    var onAddCue: () -> Void = {} {
        didSet { note.rootView = BareStageNote(onAddCue: onAddCue) }
    }
    private var dragged: MediaDrop?

    init() {
        super.init(frame: .zero)
        screen.addSubview(wordmark)
        addSubview(screen)
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
        // The screen at 16:9, as large as fits, centred.
        let w = min(room.width, room.height * 16 / 9).rounded(.down), h = (w * 9 / 16).rounded(.down)
        screen.frame = NSRect(x: ((room.width - w) / 2).rounded(), y: ((room.height - h) / 2).rounded(), width: w, height: h)
        wordmark.frame = screen.bounds.insetClamped(dx: 1, dy: 1)
        note.frame = NSRect(x: 0, y: room.maxY, width: bounds.width, height: noteHeight)
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
