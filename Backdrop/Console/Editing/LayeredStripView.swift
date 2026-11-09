import AppKit
import BackdropCore
import SwiftUI

/// What the Cue tab's layer strip shows of a layered cue, and what it can
/// ask for. The panel fills it in from the cue standing by.
@MainActor
final class LayeredStripState: ObservableObject {
    @Published var layers: [ImageLayer] = []
    /// The fade a layer without its own takes.
    @Published var cueLayerMs = 800
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

/// A layered cue's layers in the order they arrive, left to right, which is
/// also the order they stack. Drop pictures anywhere on the strip to add them
/// at the end; drag one onto another to move it there. Each layer is a menu:
/// its level, blend, life, own fade time and how it arrives.
///
/// Edit mode only, so it may take the keyboard as any edit-mode control can.
struct LayeredStripView: View {
    @ObservedObject var state: LayeredStripState
    @ObservedObject var thumbnails: Thumbnails

    init(state: LayeredStripState) {
        self.state = state
        thumbnails = state.thumbnails
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(state.layers.enumerated()), id: \.offset) { i, layer in
                    LayerTile(index: i, layer: layer, count: state.layers.count, state: state, image: thumbnails.image(layer.src))
                }
                AddLayerTile(first: state.layers.isEmpty) { state.onChoose(nil) }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.automatic)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            MorphPicturesView.urls(from: providers) { state.onAdd($0) }
            return true
        }
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
}

private enum Strip {
    static let thumb = CGSize(width: 74, height: 44)
    static let text = Color(nsColor: Desk.text)
    static let dim = Color(nsColor: Desk.dim)
    static let brass = Color(nsColor: Desk.brass)
    static let sunk = Color(nsColor: Desk.sunk)
    static let line = Color(nsColor: Desk.lineBright)
}

private struct LayerTile: View {
    let index: Int
    let layer: ImageLayer
    let count: Int
    @ObservedObject var state: LayeredStripState
    let image: NSImage?
    @State private var hovering = false
    @State private var targeted = false
    @State private var name = ""
    @State private var seeded = false
    @State private var showDetails = false

    static let levels = [20, 30, 40, 50, 60, 70, 80, 90, 100]
    static let fades = [200, 400, 600, 800, 1200, 1600, 2000, 3000, 4000]

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topLeading) {
                // A checkerboard-ish dark ground, so a layer's transparency reads.
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
                    .help("Remove this layer")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(2)
                }
            }
            .frame(width: Strip.thumb.width, height: Strip.thumb.height)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(targeted ? Strip.brass : Strip.line, lineWidth: targeted ? 2 : 1))
            TextField("", text: $name, prompt: Text(MorphContent.name(of: layer.src)))
                .textFieldStyle(.plain)
                .font(.system(size: 10.5))
                .multilineTextAlignment(.center)
                .frame(width: Strip.thumb.width + 8)
                .onSubmit { commitName() }
                .help("What the operator and the book call this part")
            Text(LayeredStripView.marks(layer))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(layer.fadeMs == nil && layer.level == nil && layer.life == .stays && !layer.withPrevious ? Strip.dim : Strip.brass)
                .lineLimit(1)
                .frame(width: Strip.thumb.width + 8)
        }
        .onAppear {
            guard !seeded else { return }
            seeded = true
            name = layer.name
        }
        .onChange(of: layer.name) { _, new in if new != name { name = new } }
        .onHover { hovering = $0 }
        .help(layer.src.isEmpty ? "No picture" : (layer.src as NSString).lastPathComponent)
        // Dragged onto another layer, it moves to that place: arrival and
        // stacking together.
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
        .contextMenu { menu }
        .popover(isPresented: $showDetails, arrowEdge: .bottom) {
            LayerDetails(index: index, layer: layer, state: state)
        }
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
        Picker("Entrance", selection: Binding(get: { layer.highlight?.entrance.map { $0.rawValue } ?? "" }, set: { raw in
            state.onChange(index, "Change Layer Entrance") { l in
                var h = l.highlight ?? LayerHighlight()
                h.entrance = LayerEntrance(rawValue: raw)
                l.highlight = h.isEmpty ? nil : h
            }
        })) {
            Text("The Cue\u{2019}s").tag("")
            ForEach(LayerEntrance.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0.rawValue) }
        }
        Divider()
        Button("Cue Points and Frame\u{2026}") { showDetails = true }
        Button("Replace\u{2026}") { state.onChoose(index) }
        Button("Move Earlier") { state.onMove(index, index - 1) }.disabled(index == 0)
        Button("Move Later") { state.onMove(index, index + 1) }.disabled(index == count - 1)
        Divider()
        Button("Remove") { state.onRemove(index) }
    }
}

private struct AddLayerTile: View {
    let first: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: "plus").font(.system(size: 14, weight: .medium))
                Text(first ? "Add layers" : "Add").font(.system(size: 10.5))
            }
            .foregroundStyle(Strip.dim)
            .frame(width: Strip.thumb.width, height: Strip.thumb.height)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Strip.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Choose layers to add, or drop them anywhere here. Each arrives on the next GO. Every layer should be the base\u{2019}s size, with transparency.")
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
