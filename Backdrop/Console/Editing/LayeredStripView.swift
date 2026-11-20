import AppKit
import BackdropCore
import SwiftUI

/// What the Inspector's layer strip shows of a layered cue, and what it can
/// ask for. The panel fills it in from the cue standing by.
@MainActor
final class LayeredStripState: ObservableObject {
    @Published var layers: [ImageLayer] = []
    /// The fade a layer without its own takes.
    @Published var cueLayerMs = 800
    /// The entrance a layer without its own makes.
    @Published var cueEntrance: LayerEntrance = .outline
    /// What each thumbnail shows faintly behind its layer, so a small part
    /// can be seen where it sits: the base, or the first layer without one.
    @Published var backdrop = ""
    let thumbnails: Thumbnails

    init(thumbnails: Thumbnails = Thumbnails()) {
        self.thumbnails = thumbnails
    }

    /// Pictures dropped on the strip, added at the end in order.
    var onAdd: ([URL]) -> Void = { _ in }
    /// Choose a file: to replace that layer, or with nil to add layers.
    var onChoose: (Int?) -> Void = { _ in }
    var onRemove: (Int) -> Void = { _ in }
    var onMove: (_ from: Int, _ to: Int) -> Void = { _, _ in }
    /// Any other change to one layer: one undoable edit.
    var onChange: (_ layer: Int, _ name: String, _ change: @escaping (inout ImageLayer) -> Void) -> Void = { _, _, _ in }
}

/// A layered cue's layers, top to bottom in the order they arrive, which is
/// also the order they stack: the last sits on top. Drop pictures anywhere
/// on the list to add them at the end; drag a row up or down to move it, a
/// brass line showing where it will land. Each row's menu sets its level,
/// blend, life, own fade time and how it arrives.
///
/// Edit mode only, so it may take the keyboard as any edit-mode control can.
struct LayeredStripView: View {
    @ObservedObject var state: LayeredStripState
    @ObservedObject var thumbnails: Thumbnails
    /// Where a row being dragged would land, while one is over the list.
    @State private var drop: RowDropTarget?

    init(state: LayeredStripState) {
        self.state = state
        thumbnails = state.thumbnails
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(state.layers.enumerated()), id: \.offset) { i, layer in
                LayerRow(index: i, layer: layer, count: state.layers.count, state: state,
                         image: thumbnails.image(layer.src), backdrop: thumbnails.image(state.backdrop), drop: $drop)
                Divider()
            }
            AddLayerRow(first: state.layers.isEmpty) { state.onChoose(nil) }
        }
        .mediaDrop(accepting: { ShowDocument.accepts($0, for: .layered) }) { [state] urls in state.onAdd(urls) }
        .clearsStaleRowDrop($drop)
    }

    /// The marks that say how a layer behaves, under its name.
    static func marks(_ layer: ImageLayer) -> String {
        var marks: [String] = []
        if layer.withPrevious { marks.append("+") }
        switch layer.life {
        case .stays: break
        case .untilNextLayer: marks.append("\u{2715} next")
        case .untilNextGo: marks.append("\u{2715} GO")
        }
        if let level = layer.level { marks.append("\(level)%") }
        if layer.blend != .normal { marks.append(layer.blend.rawValue) }
        return marks.joined(separator: " ")
    }

    /// How the list works, for the tip beside its heading.
    static let explanation = "Choose layers to add, or drop them anywhere on the list. Each arrives on the next GO. Every layer should be the base\u{2019}s size, with transparency. A layer\u{2019}s name is what the operator and the book call that part."
}

private enum Strip {
    static let thumb = CGSize(width: 64, height: 36)
    static let brass = Color(nsColor: Desk.brass)
    static let line = Color(nsColor: Desk.lineBright)
}

private struct LayerRow: View {
    let index: Int
    let layer: ImageLayer
    let count: Int
    @ObservedObject var state: LayeredStripState
    let image: NSImage?
    let backdrop: NSImage?
    @Binding var drop: RowDropTarget?
    @State private var name = ""
    @State private var seeded = false
    @State private var showDetails = false
    @State private var hovering = false

    static let height: CGFloat = 48

    static let levels = [20, 30, 40, 50, 60, 70, 80, 90, 100]
    static let fades = [200, 400, 600, 800, 1200, 1600, 2000, 3000, 4000]

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 16, alignment: .trailing)
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                // A grouped form keeps a label column, and sets text to the
                // trailing edge, for any field that might have a label.
                TextField("", text: $name, prompt: Text(MorphContent.name(of: layer.src)))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .onSubmit { commitName() }
                let marks = LayeredStripView.marks(layer)
                if !marks.isEmpty {
                    Text(marks)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Strip.brass)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fadesUnderRowControls(hovering)
        }
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .overlay(alignment: .trailing) {
            RowControls(showing: hovering, menuHelp: "This layer\u{2019}s settings", removeHelp: "Remove this layer",
                        dragHelp: "Drag to move this layer earlier or later", remove: { state.onRemove(index) }) { menu }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .overlay(alignment: .top) { if drop?.gap == index { RowReorder.insertion.offset(y: -1) } }
        .overlay(alignment: .bottom) { if drop?.gap == count, index == count - 1 { RowReorder.insertion.offset(y: 1) } }
        .onAppear {
            guard !seeded else { return }
            seeded = true
            name = layer.name
        }
        .onChange(of: layer.name) { _, new in if new != name { name = new } }
        .help(layer.src.isEmpty ? "No picture" : (layer.src as NSString).lastPathComponent)
        // The top half of a row puts a dragged one before it, the bottom half after.
        .onDrag { RowReorder.payload("layer", index) }
        .onDrop(of: [.plainText], delegate: RowReorderDrop(list: "layer", row: index, gap: { $0 < Self.height / 2 ? index : index + 1 },
                                                           target: $drop, move: { [state] from, to in state.onMove(from, to) }))
        .contextMenu { menu }
        .popover(isPresented: $showDetails, arrowEdge: .leading) {
            LayerDetails(index: index, layer: layer, state: state)
        }
    }

    /// The layer as the stage shows it: on black, over the whole picture
    /// faintly, so even a small part reads, and where it sits.
    private var thumbnail: some View {
        ZStack {
            Color.black
            if let backdrop, layer.src != state.backdrop {
                Image(nsImage: backdrop).resizable().aspectRatio(contentMode: .fit).opacity(0.3)
            }
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

    private func commitName() {
        let value = name.trimmingCharacters(in: .whitespaces)
        guard value != layer.name else { return }
        state.onChange(index, "Rename Layer") { $0.name = value }
    }

    @ViewBuilder
    private var menu: some View {
        Toggle("Arrives With The One Before", isOn: Binding(get: { layer.withPrevious },
                                                            set: { on in state.onChange(index, "Change Layer Arrival") { $0.withPrevious = on } }))
            .disabled(index == 0)
        Picker("Lasts", selection: Binding(get: { layer.life }, set: { life in state.onChange(index, "Change Layer Life") { $0.life = life } })) {
            Text("To the end").tag(LayerLife.stays)
            Text("Until the next layer").tag(LayerLife.untilNextLayer)
            Text("Until the next GO").tag(LayerLife.untilNextGo)
        }
        Picker("Comes up to", selection: Binding(get: { layer.level ?? 100 }, set: { level in
            state.onChange(index, "Change Layer Level") { $0.level = level == 100 ? nil : level }
        })) {
            ForEach(Self.levels, id: \.self) { Text("\($0)%").tag($0) }
        }
        Picker("Blend", selection: Binding(get: { layer.blend }, set: { blend in state.onChange(index, "Change Layer Blend") { $0.blend = blend } })) {
            ForEach(LayerBlend.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
        Picker("Arrives In", selection: Binding(get: { layer.fadeMs ?? 0 }, set: { ms in
            state.onChange(index, "Change Layer Fade") { $0.fadeMs = ms == 0 ? nil : ms }
        })) {
            Text("The Cue\u{2019}s, \(SettingKey.layerTime.format(.number(state.cueLayerMs)))").tag(0)
            ForEach(Self.fades, id: \.self) { Text(SettingKey.layerTime.format(.number($0))).tag($0) }
        }
        Picker("While It Arrives", selection: Binding(get: { layer.highlight?.context.map { $0.rawValue } ?? "" }, set: { raw in
            state.onChange(index, "Change Layer Treatment") { l in
                var h = l.highlight ?? LayerHighlight()
                h.context = LayerContext(rawValue: raw)
                l.highlight = h.isEmpty ? nil : h
            }
        })) {
            Text("The Cue\u{2019}s").tag("")
            ForEach(LayerContext.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0.rawValue) }
        }
        // Any mix of effects. Following the cue's, the boxes show the cue's;
        // ticking one gives the layer its own, starting from those.
        Menu("Entrance") {
            Toggle("The Cue\u{2019}s, \(SettingKey.entrance.format(.entrance(state.cueEntrance)))",
                   isOn: Binding(get: { layer.highlight?.entrance == nil }, set: { on in
                       guard on else { return }
                       setEntrance(nil)
                   }))
            Divider()
            ForEach(LayerEntrance.each, id: \.rawValue) { effect in
                Toggle(effect.name.capitalized, isOn: Binding(get: { entrance.contains(effect) }, set: { on in
                    var own = entrance
                    if on { own.insert(effect) } else { own.remove(effect) }
                    setEntrance(own)
                }))
            }
        }
        Divider()
        Button("Cue Points and Frame\u{2026}") { showDetails = true }
        Button("Replace\u{2026}") { state.onChoose(index) }
        Button("Move Up") { state.onMove(index, index - 1) }.disabled(index == 0)
        Button("Move Down") { state.onMove(index, index + 1) }.disabled(index == count - 1)
        Divider()
        Button("Remove") { state.onRemove(index) }
    }

    /// The entrance this layer makes: its own, or the cue's.
    private var entrance: LayerEntrance { layer.highlight?.entrance ?? state.cueEntrance }

    private func setEntrance(_ entrance: LayerEntrance?) {
        state.onChange(index, "Change Layer Entrance") { l in
            var h = l.highlight ?? LayerHighlight()
            h.entrance = entrance
            l.highlight = h.isEmpty ? nil : h
        }
    }
}

private struct AddLayerRow: View {
    let first: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(first ? "Add Layers\u{2026}" : "Add\u{2026}", systemImage: "plus")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 8)
    }
}

/// A layer's cue points, for the GO that brings it on and, for a false step on
/// a GO of its own, the one that takes it off; and a frame for the camera to
/// look at, where the one derived from the layer's opaque pixels is wrong.
private struct LayerDetails: View {
    let index: Int
    let layer: ImageLayer
    @ObservedObject var state: LayeredStripState
    @State private var cuePoint = ""
    @State private var exitCuePoint = ""
    @State private var frame = [String](repeating: "", count: 4)
    @State private var seeded = false

    private static let labels = ["Left", "Top", "Width", "Height"]

    var body: some View {
        Form {
            TextField("Arrives on", text: $cuePoint, prompt: Text("The line or action"))
                .onSubmit { commit() }
            if layer.life == .untilNextGo || layer.life == .untilNextLayer {
                TextField("Goes on", text: $exitCuePoint, prompt: Text("Only when it goes on its own GO"))
                    .onSubmit { commit() }
            }
            Section("Camera frame, as a % of the picture") {
                ForEach(0..<4, id: \.self) { i in
                    TextField(Self.labels[i], text: $frame[i], prompt: Text("Derived"))
                        .onSubmit { commit() }
                }
                Text("Leave empty to frame the part from its own pixels. All four set it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 320)
        .onAppear {
            guard !seeded else { return }
            seeded = true
            cuePoint = layer.cuePoint
            exitCuePoint = layer.exitCuePoint
            if let f = layer.frame {
                frame = [f.x, f.y, f.width, f.height].map { String(Int(($0 * 100).rounded())) }
            }
        }
        .onDisappear { commit() }
    }

    private func commit() {
        let cue = cuePoint.trimmingCharacters(in: .whitespaces), exit = exitCuePoint.trimmingCharacters(in: .whitespaces)
        let numbers = frame.map { Double($0.trimmingCharacters(in: .whitespaces)) }
        let rect: PictureRect? = numbers.allSatisfy({ $0 != nil }) && numbers.count == 4
            ? PictureRect(x: numbers[0]! / 100, y: numbers[1]! / 100, width: numbers[2]! / 100, height: numbers[3]! / 100).clamped : nil
        guard cue != layer.cuePoint || exit != layer.exitCuePoint || rect != layer.frame else { return }
        state.onChange(index, "Change Layer Cue Points") { l in
            l.cuePoint = cue
            l.exitCuePoint = exit
            l.frame = rect
        }
    }
}
