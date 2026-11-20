import AppKit
import BackdropCore
import SwiftUI
import UniformTypeIdentifiers

/// What the Inspector's picture strip shows of a morph cue, and what it can
/// ask for. The panel fills it in from the cue standing by.
@MainActor
final class MorphPicturesState: ObservableObject {
    @Published var pictures: [MorphPicture] = []
    /// The morph time a stage without its own takes.
    @Published var cueMorphMs = 3000
    let thumbnails = Thumbnails()

    /// Pictures dropped on the strip, added at the end in order.
    var onAdd: ([URL]) -> Void = { _ in }
    /// Choose a file: to replace that picture, or with nil to add pictures.
    var onChoose: (Int?) -> Void = { _ in }
    var onRemove: (Int) -> Void = { _ in }
    var onMove: (_ from: Int, _ to: Int) -> Void = { _, _ in }
    /// The stage into a picture takes its own time, or with nil the cue's.
    var onTime: (_ picture: Int, _ ms: Int?) -> Void = { _, _ in }
    /// Open the points window on a stage.
    var onPoints: (_ stage: Int) -> Void = { _ in }
}

/// A morph cue's pictures, top to bottom in the order they come, and
/// between each two the stage that changes one into the next: its time and
/// its points, and a menu for both. Drop pictures anywhere on the list to
/// add them at the end; drag a row up or down to move it, a brass line
/// showing where it will land.
///
/// Edit mode only, so it may take the keyboard as any edit-mode control can.
struct MorphPicturesView: View {
    @ObservedObject var state: MorphPicturesState
    @ObservedObject var thumbnails: Thumbnails
    /// Where a row being dragged would land, while one is over the list.
    @State private var drop: RowDropTarget?

    init(state: MorphPicturesState) {
        self.state = state
        thumbnails = state.thumbnails
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(state.pictures.enumerated()), id: \.offset) { i, picture in
                if i > 0 { StageRow(index: i, picture: picture, state: state, drop: $drop) }
                PictureRow(index: i, picture: picture, count: state.pictures.count, state: state,
                           image: thumbnails.image(picture.src), drop: $drop)
            }
            if !state.pictures.isEmpty { Divider() }
            AddPictureRow(first: state.pictures.isEmpty) { state.onChoose(nil) }
        }
        .mediaDrop(accepting: { ShowDocument.accepts($0, for: .morph) }) { [state] urls in state.onAdd(urls) }
        .clearsStaleRowDrop($drop)
    }
}

private enum Strip {
    static let thumb = CGSize(width: 64, height: 36)
    static let brass = Color(nsColor: Desk.brass)
    static let line = Color(nsColor: Desk.lineBright)
    /// How far in a stage's arrow sits, under the middle of the pictures.
    static let arrowInset: CGFloat = 16 + 8 + thumb.width / 2 - 7

    static func seconds(_ ms: Int) -> String {
        SettingKey.morphTime.format(.number(ms))
    }

    /// Dragged rows of this list carry this.
    static let list = "picture"
}

private struct PictureRow: View {
    let index: Int
    let picture: MorphPicture
    let count: Int
    @ObservedObject var state: MorphPicturesState
    let image: NSImage?
    @Binding var drop: RowDropTarget?
    @State private var hovering = false

    static let height: CGFloat = 48

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 16, alignment: .trailing)
            thumbnail
            Text(MorphContent.name(of: picture.src))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fadesUnderRowControls(hovering)
        }
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .overlay(alignment: .trailing) {
            RowControls(showing: hovering, menuHelp: "Replace or move this picture", removeHelp: "Remove this picture",
                        dragHelp: "Drag to move this picture earlier or later", remove: { state.onRemove(index) }) { menu }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .overlay(alignment: .top) { if index == 0, drop?.gap == 0 { RowReorder.insertion.offset(y: -1) } }
        .overlay(alignment: .bottom) { if drop?.gap == count, index == count - 1 { RowReorder.insertion.offset(y: 1) } }
        .help(picture.src.isEmpty ? "No picture" : (picture.src as NSString).lastPathComponent)
        // The top half of a row puts a dragged one before it, the bottom half after.
        .onDrag { RowReorder.payload(Strip.list, index) }
        .onDrop(of: [.plainText], delegate: RowReorderDrop(list: Strip.list, row: index, gap: { $0 < Self.height / 2 ? index : index + 1 },
                                                           target: $drop, move: { [state] from, to in state.onMove(from, to) }))
        .contextMenu { menu }
    }

    private var thumbnail: some View {
        ZStack {
            Color.black
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo").foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: Strip.thumb.width, height: Strip.thumb.height)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Strip.line, lineWidth: 1))
    }

    @ViewBuilder
    private var menu: some View {
        Button("Replace\u{2026}") { state.onChoose(index) }
        Button("Move Up") { state.onMove(index, index - 1) }.disabled(index == 0)
        Button("Move Down") { state.onMove(index, index + 1) }.disabled(index == count - 1)
        Divider()
        Button("Remove") { state.onRemove(index) }
    }
}

/// The stage into picture `index`, between it and the one before: its time
/// and points, and a menu for both. A row dragged onto it lands between the
/// two.
private struct StageRow: View {
    let index: Int
    let picture: MorphPicture
    @ObservedObject var state: MorphPicturesState
    @Binding var drop: RowDropTarget?

    static let presets = [500, 1000, 1500, 2000, 3000, 4000, 5000, 6000, 8000, 10_000, 12_000, 15_000]

    var body: some View {
        HStack(spacing: 0) {
            Menu {
                Button("Edit Points\u{2026}") { state.onPoints(index - 1) }
                Picker("Morph Time", selection: Binding(get: { picture.morphMs ?? 0 }, set: { state.onTime(index, $0 == 0 ? nil : $0) })) {
                    Text("The Cue\u{2019}s, \(Strip.seconds(state.cueMorphMs))").tag(0)
                    ForEach(Self.presets, id: \.self) { Text(Strip.seconds($0)).tag($0) }
                }
            } label: {
                // A menu's label keeps one image and one text, so the time
                // and the points are one text in two styles.
                let time = Text(Strip.seconds(picture.morphMs ?? state.cueMorphMs))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(picture.morphMs == nil ? Color.secondary : Strip.brass)
                let points = picture.pairs.isEmpty ? "dissolve" : "\(picture.pairs.count) point\(picture.pairs.count == 1 ? "" : "s")"
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Text("\(time) \u{00B7} \(points)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Stage \(index): its points, and how long it takes. Brass is its own time; the rest take the cue\u{2019}s morph time.")
            Spacer(minLength: 0)
        }
        .padding(.leading, Strip.arrowInset)
        .frame(height: 22)
        .contentShape(Rectangle())
        .overlay(alignment: .top) { if drop?.gap == index { RowReorder.insertion.offset(y: -1) } }
        .onDrop(of: [.plainText], delegate: RowReorderDrop(list: Strip.list, row: -index, gap: { _ in index },
                                                           target: $drop, move: { [state] from, to in state.onMove(from, to) }))
    }
}

private struct AddPictureRow: View {
    let first: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(first ? "Add Pictures\u{2026}" : "Add\u{2026}", systemImage: "plus")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 8)
        .help("Choose pictures to add, or drop them anywhere on the list. Each becomes the next in turn.")
    }
}
