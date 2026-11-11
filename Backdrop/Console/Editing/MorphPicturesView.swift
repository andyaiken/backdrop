import AppKit
import BackdropCore
import SwiftUI
import UniformTypeIdentifiers

/// What the Cue tab's picture strip shows of a morph cue, and what it can
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

/// A morph cue's pictures in order, left to right, each stage between two
/// of them an arrow with its time and points. Drop pictures anywhere on the
/// strip to add them; drag one onto another to move it there. A stage's
/// arrow is a menu: its points, and its own morph time.
///
/// Edit mode only, so it may take the keyboard as any edit-mode control can.
struct MorphPicturesView: View {
    @ObservedObject var state: MorphPicturesState
    @ObservedObject var thumbnails: Thumbnails

    init(state: MorphPicturesState) {
        self.state = state
        thumbnails = state.thumbnails
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(Array(state.pictures.enumerated()), id: \.offset) { i, picture in
                    if i > 0 { StageLink(index: i, picture: picture, state: state) }
                    PictureTile(index: i, picture: picture, count: state.pictures.count, state: state, image: thumbnails.image(picture.src))
                }
                AddTile(first: state.pictures.isEmpty) { state.onChoose(nil) }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.automatic)
        .mediaDrop(accepting: { ShowDocument.accepts($0, for: .morph) }) { [state] urls in state.onAdd(urls) }
    }
}

private enum Strip {
    static let thumb = CGSize(width: 74, height: 44)
    static let text = Color(nsColor: Desk.text)
    static let dim = Color(nsColor: Desk.dim)
    static let brass = Color(nsColor: Desk.brass)
    static let sunk = Color(nsColor: Desk.sunk)
    static let line = Color(nsColor: Desk.lineBright)

    static func seconds(_ ms: Int) -> String {
        SettingKey.morphTime.format(.number(ms))
    }
}

private struct PictureTile: View {
    let index: Int
    let picture: MorphPicture
    let count: Int
    @ObservedObject var state: MorphPicturesState
    let image: NSImage?
    @State private var hovering = false
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3).fill(Strip.sunk)
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: Strip.thumb.width, height: Strip.thumb.height)
                }
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Strip.text)
                    .padding(.horizontal, 3)
                    .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 2))
                    .padding(2)
                if hovering {
                    Button { state.onRemove(index) } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(Strip.text, Color.black.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Remove this picture")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(2)
                }
            }
            .frame(width: Strip.thumb.width, height: Strip.thumb.height)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(targeted ? Strip.brass : Strip.line, lineWidth: targeted ? 2 : 1))
            Text(MorphContent.name(of: picture.src))
                .font(.system(size: 10.5))
                .foregroundStyle(Strip.dim)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: Strip.thumb.width)
        }
        .onHover { hovering = $0 }
        .help(picture.src.isEmpty ? "No picture" : (picture.src as NSString).lastPathComponent)
        // Dragged onto another picture, it moves to that place.
        .onDrag { NSItemProvider(object: "\(index)" as NSString) }
        .onDrop(of: [.plainText], isTargeted: $targeted) { providers in
            guard let provider = providers.first else { return false }
            let to = index
            _ = provider.loadObject(ofClass: NSString.self) { text, _ in
                guard let from = (text as? String).flatMap(Int.init) else { return }
                Task { @MainActor in state.onMove(from, to) }
            }
            return true
        }
        .contextMenu {
            Button("Replace\u{2026}") { state.onChoose(index) }
            Button("Move Earlier") { state.onMove(index, index - 1) }.disabled(index == 0)
            Button("Move Later") { state.onMove(index, index + 1) }.disabled(index == count - 1)
            Divider()
            Button("Remove") { state.onRemove(index) }
        }
    }
}

/// The stage into picture `index`: its time and points, and a menu for
/// both.
private struct StageLink: View {
    let index: Int
    let picture: MorphPicture
    @ObservedObject var state: MorphPicturesState

    static let presets = [500, 1000, 1500, 2000, 3000, 4000, 5000, 6000, 8000, 10_000, 12_000, 15_000]

    var body: some View {
        Menu {
            Button("Edit Points\u{2026}") { state.onPoints(index - 1) }
            Picker("Morph Time", selection: Binding(get: { picture.morphMs ?? 0 }, set: { state.onTime(index, $0 == 0 ? nil : $0) })) {
                Text("The Cue\u{2019}s, \(Strip.seconds(state.cueMorphMs))").tag(0)
                ForEach(Self.presets, id: \.self) { Text(Strip.seconds($0)).tag($0) }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .medium)).foregroundStyle(Strip.dim)
                Text(Strip.seconds(picture.morphMs ?? state.cueMorphMs))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(picture.morphMs == nil ? Strip.dim : Strip.brass)
                Text(picture.pairs.isEmpty ? "dissolve" : "\(picture.pairs.count) pt\(picture.pairs.count == 1 ? "" : "s")")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Strip.dim)
            }
            .frame(width: 52, height: Strip.thumb.height + 16)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Stage \(index): its points, and how long it takes. Brass is its own time; the rest take the cue\u{2019}s morph time.")
    }
}

private struct AddTile: View {
    let first: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: "plus").font(.system(size: 14, weight: .medium))
                Text(first ? "Add pictures" : "Add").font(.system(size: 10.5))
            }
            .foregroundStyle(Strip.dim)
            .frame(width: Strip.thumb.width, height: Strip.thumb.height)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Strip.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Choose pictures to add, or drop them anywhere here. Each becomes the next in turn.")
    }
}
