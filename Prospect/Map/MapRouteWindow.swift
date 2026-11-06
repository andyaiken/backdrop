import AppKit
import ImageIO
import ProspectCore
import ProspectStage
import SwiftUI

/// Where a map cue's route is laid: the map, with the route drawn over it.
/// Click the map to add a stop at the end of the route; drag any point to
/// move it; select one to set what it is and what the screen says there.
/// Two places whose latitude and longitude are known give the coordinates.
/// The slider beneath runs the dot along the whole route.
///
/// One window, for one map cue at a time, in edit mode only, so it may take
/// the keyboard. Every change is one step of undo, as in the console.
final class MapRouteWindowController: NSWindowController, NSWindowDelegate {
    let cueID: UUID
    private weak var controller: ShowController?
    private let model: RouteModel
    /// The document's, so Undo here undoes what was done here.
    var undoManagerSource: () -> UndoManager? = { nil }

    init(controller: ShowController, cueID: UUID, mediaURL: @escaping (String) -> URL?) {
        self.controller = controller
        self.cueID = cueID
        model = RouteModel(mediaURL: mediaURL)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 900, height: 600)
        window.backgroundColor = Desk.colour
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: RouteView(model: model))
        window.setContentSize(NSSize(width: 1240, height: 820))
        super.init(window: window)
        window.delegate = self
        window.center()
        model.commit = { [weak self] name, change in
            guard let self else { return }
            self.controller?.updateCue(self.cueID, name) { cue in
                if case .map(var c) = cue.content {
                    change(&c)
                    cue.content = .map(c)
                }
            }
        }
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        undoManagerSource()
    }

    /// Brings the window up to date with the show, after any edit, an undo
    /// included. Closes it if the cue has gone, stopped being a map, or the
    /// show has gone into show mode.
    func refresh() {
        guard let controller, controller.mode == .edit, let cue = controller.show[cueID], case .map(let content) = cue.content else {
            close()
            return
        }
        window?.title = "Map Route \u{2014} Cue \(cue.number.isEmpty ? "(no number)" : cue.number)"
        model.update(content, settings: controller.show.settings.resolved(content.overrides))
    }
}

/// What the route window shows and edits.
@MainActor
final class RouteModel: ObservableObject {
    @Published private(set) var content = MapContent()
    @Published private(set) var settings = MapSettings()
    @Published private(set) var image: NSImage?
    @Published var selected: Int?
    /// While set, the next click on the map places that known place.
    @Published var placing: Anchor?
    /// Where the slider has the dot, from 0 to 1 of the whole route.
    @Published var scrub = 0.0
    /// A point being dragged, and where it is: the show hears when the drag
    /// ends.
    @Published var dragging: (index: Int, at: PicturePoint)?
    private var src = ""
    private let mediaURL: (String) -> URL?
    var commit: (String, @escaping (inout MapContent) -> Void) -> Void = { _, _ in }

    enum Anchor: String {
        case a = "A", b = "B"
    }

    init(mediaURL: @escaping (String) -> URL?) {
        self.mediaURL = mediaURL
    }

    func update(_ content: MapContent, settings: MapSettings) {
        if content.src != src {
            src = content.src
            image = Self.load(mediaURL(content.src))
        }
        if self.content != content { self.content = content }
        if self.settings != settings { self.settings = settings }
        if let selected, selected >= content.route.count { self.selected = nil }
    }

    /// The map, at a size that keeps drawing the window quick.
    private static func load(_ url: URL?) -> NSImage? {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 3000,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// The route with any point mid-drag where it is being dragged.
    var route: [RoutePoint] {
        var route = content.route
        if let dragging, route.indices.contains(dragging.index) { route[dragging.index].at = dragging.at }
        return route
    }

    var aspect: Double {
        guard let image, image.size.height > 0 else { return 16.0 / 9 }
        return image.size.width / image.size.height
    }

    // MARK: Editing

    /// A click on the map: a known place set, or a stop added at the end.
    func click(at p: PicturePoint) {
        if let placing {
            self.placing = nil
            commit("Place \(placing.rawValue)") { c in
                var reference = c.reference ?? Self.defaultReference
                if placing == .a { reference.a.at = p } else { reference.b.at = p }
                c.reference = reference
            }
            return
        }
        let first = content.route.isEmpty
        commit(first ? "Place Start" : "Add Stop") { c in
            c.route.append(RoutePoint(at: p, stop: MapStop()))
        }
        selected = content.route.count
    }

    func moved(_ index: Int, to p: PicturePoint) {
        dragging = nil
        commit("Move Point") { c in
            guard c.route.indices.contains(index) else { return }
            c.route[index].at = p
        }
    }

    func delete(_ index: Int) {
        selected = nil
        commit("Delete Point") { c in
            guard c.route.indices.contains(index) else { return }
            c.route.remove(at: index)
        }
    }

    /// A point halfway to the next, passed through rather than stopped at.
    func insert(after index: Int) {
        guard content.route.indices.contains(index) else { return }
        let here = content.route[index].at
        let next = content.route.indices.contains(index + 1) ? content.route[index + 1].at : PicturePoint(x: here.x + 0.05, y: here.y)
        commit("Add Point") { c in
            c.route.insert(RoutePoint(at: PicturePoint(x: (here.x + next.x) / 2, y: (here.y + next.y) / 2).clamped), at: index + 1)
        }
        selected = index + 1
    }

    func setStop(_ index: Int, _ stop: Bool) {
        commit(stop ? "Make Stop" : "Make Pass-Through") { c in
            guard c.route.indices.contains(index) else { return }
            c.route[index].stop = stop ? (c.route[index].stop ?? MapStop()) : nil
        }
    }

    func change(_ index: Int, _ name: String, _ body: @escaping (inout MapStop) -> Void) {
        commit(name) { c in
            guard c.route.indices.contains(index) else { return }
            var stop = c.route[index].stop ?? MapStop()
            body(&stop)
            c.route[index].stop = stop
        }
    }

    func setReference(_ anchor: Anchor, latitude: Double?, longitude: Double?) {
        commit("Change Coordinates") { c in
            var reference = c.reference ?? Self.defaultReference
            if anchor == .a {
                if let latitude { reference.a.latitude = latitude }
                if let longitude { reference.a.longitude = longitude }
            } else {
                if let latitude { reference.b.latitude = latitude }
                if let longitude { reference.b.longitude = longitude }
            }
            c.reference = reference
        }
    }

    func clearReference() {
        commit("Remove Coordinates") { $0.reference = nil }
    }

    /// Two corners of central London, to be moved and retyped.
    static let defaultReference = MapReference(a: MapAnchor(at: PicturePoint(x: 0.1, y: 0.1), latitude: 51.53, longitude: -0.16),
                                               b: MapAnchor(at: PicturePoint(x: 0.9, y: 0.9), latitude: 51.49, longitude: -0.06))

    // MARK: The scrubber

    /// Where the slider has the cue, in frames: the start, before anything
    /// moves, at the far left.
    var position: Double {
        scrub > 0 ? scrub * preview.frames : -1
    }

    /// The route run by itself from end to end, for the slider.
    var preview: (plan: MapCuePlan, timeline: GoTimeline, frames: Double) {
        var settings = settings
        settings.advance = .byItself
        settings.holdTicks = 0
        let plan = MapCuePlan(content, settings: settings, aspect: aspect)
        var timeline = GoTimeline(parts: plan.parts)
        timeline.carryOnToEnd()
        return (plan, timeline, Double(plan.parts.reduce(0, +)))
    }
}

// MARK: - Views

private enum Look {
    static let text = Color(nsColor: Desk.text)
    static let dim = Color(nsColor: Desk.dim)
    static let brass = Color(nsColor: Desk.brass)
    static let sunk = Color(nsColor: Desk.sunk)
    static let red = Color(red: 1, green: 0.17, blue: 0.17)
}

struct RouteView: View {
    @ObservedObject var model: RouteModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.placing.map { "Click the map where place \($0.rawValue) is." }
                     ?? "Click the map to add a stop at the end of the route. Drag a point to move it; right-click one for more.")
                    .foregroundStyle(model.placing == nil ? Look.dim : Look.brass)
                MapCanvas(model: model)
                Scrubber(model: model)
            }
            Inspector(model: model)
                .frame(width: 290)
        }
        .padding(20)
        .background(Color(nsColor: Desk.colour))
        .onDeleteCommand { if let selected = model.selected { model.delete(selected) } }
    }
}

/// The map with the route over it.
private struct MapCanvas: View {
    @ObservedObject var model: RouteModel
    @State private var pressed: (index: Int?, start: CGPoint)?

    var body: some View {
        GeometryReader { geometry in
            let frame = Self.fit(aspect: model.aspect, in: geometry.size)
            ZStack(alignment: .topLeading) {
                Look.sunk
                if let image = model.image {
                    Image(nsImage: image).resizable().interpolation(.high)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                } else {
                    Text("No map yet. Add one in the Cue tab.").foregroundStyle(Look.dim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Canvas { context, _ in draw(&context, in: frame) }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if pressed == nil { pressed = (hit(drag.startLocation, in: frame), drag.startLocation) }
                    guard let index = pressed?.index, hypot(drag.translation.width, drag.translation.height) > 2 else { return }
                    model.dragging = (index, point(drag.location, in: frame))
                }
                .onEnded { drag in
                    defer { pressed = nil }
                    let moved = hypot(drag.translation.width, drag.translation.height) > 2
                    if let index = pressed?.index {
                        model.selected = index
                        if moved { model.moved(index, to: point(drag.location, in: frame)) }
                    } else if !moved, frame.contains(drag.location) {
                        model.click(at: point(drag.location, in: frame))
                    } else {
                        model.selected = nil
                    }
                })
            .contextMenu {
                if let selected = model.selected, model.content.route.indices.contains(selected) {
                    if selected > 0 {
                        Button(model.content.route[selected].stop == nil ? "Make Stop" : "Make Pass-Through") {
                            model.setStop(selected, model.content.route[selected].stop == nil)
                        }
                    }
                    Button("Insert Point After") { model.insert(after: selected) }
                    Divider()
                    Button("Delete Point") { model.delete(selected) }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    static func fit(aspect: Double, in size: CGSize) -> CGRect {
        let w = min(size.width, size.height * aspect), h = w / aspect
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func point(_ location: CGPoint, in frame: CGRect) -> PicturePoint {
        PicturePoint(x: (location.x - frame.minX) / frame.width, y: (location.y - frame.minY) / frame.height).clamped
    }

    private func location(_ p: PicturePoint, in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + p.x * frame.width, y: frame.minY + p.y * frame.height)
    }

    /// The point under a click, the last drawn first.
    private func hit(_ location: CGPoint, in frame: CGRect) -> Int? {
        model.route.indices.reversed().first { hypot(self.location(model.route[$0].at, in: frame).x - location.x,
                                                     self.location(model.route[$0].at, in: frame).y - location.y) <= 10 }
    }

    private func draw(_ context: inout GraphicsContext, in frame: CGRect) {
        let route = model.route
        // The legs: solid where the dot travels, dashed where it jumps.
        let stops = model.content.stops
        for (from, to) in zip(stops, stops.dropFirst()) where to < route.count {
            var path = Path()
            let jump = model.content.stop(at: to).arrival == .jump
            let points = jump ? [route[from].at, route[to].at] : route[from...to].map(\.at)
            path.addLines(points.map { location($0, in: frame) })
            context.stroke(path, with: .color(Look.red.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: jump ? [6, 6] : []))
        }
        // Points after the last stop lead nowhere: drawn faint.
        if let last = stops.last, last < route.count - 1 {
            var path = Path()
            path.addLines(route[last...].map { location($0.at, in: frame) })
            context.stroke(path, with: .color(Look.red.opacity(0.3)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
        }
        for (i, point) in route.enumerated() {
            let c = location(point.at, in: frame), on = i == model.selected
            if i == 0 || point.stop != nil {
                let r: CGFloat = 7
                let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                context.fill(ring, with: .color(on ? Look.brass : Look.red))
                context.stroke(ring, with: .color(.black.opacity(0.7)), lineWidth: 1.5)
                let n = stops.firstIndex(of: i) ?? 0
                // On a dark tag, so it reads on a light map or a dark one.
                let label = context.resolve(Text(n == 0 ? "Start" : "\(n)").font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(on ? Look.brass : .white))
                let size = label.measure(in: CGSize(width: 200, height: 40))
                let tag = CGRect(x: c.x + 9, y: c.y - 10 - size.height - 2, width: size.width + 8, height: size.height + 4)
                context.fill(Path(roundedRect: tag, cornerRadius: 3), with: .color(.black.opacity(0.75)))
                context.draw(label, at: CGPoint(x: tag.minX + 4, y: tag.minY + 2), anchor: .topLeading)
            } else {
                let r: CGFloat = 4
                let dot = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                context.fill(dot, with: .color(.black.opacity(0.6)))
                context.stroke(dot, with: .color(on ? Look.brass : Look.red), lineWidth: 1.5)
            }
        }
        // The two known places.
        if let reference = model.content.reference {
            for (name, anchor) in [("A", reference.a), ("B", reference.b)] {
                let c = location(anchor.at, in: frame)
                var cross = Path()
                cross.move(to: CGPoint(x: c.x - 8, y: c.y))
                cross.addLine(to: CGPoint(x: c.x + 8, y: c.y))
                cross.move(to: CGPoint(x: c.x, y: c.y - 8))
                cross.addLine(to: CGPoint(x: c.x, y: c.y + 8))
                context.stroke(cross, with: .color(Look.brass), lineWidth: 1.5)
                context.draw(Text(name).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(Look.brass),
                             at: CGPoint(x: c.x + 6, y: c.y + 6), anchor: .topLeading)
            }
        }
        // The dot where the slider has it.
        let preview = model.preview
        if preview.frames > 0, model.scrub > 0 {
            let state = preview.plan.state(at: model.position, timeline: preview.timeline)
            if state.dotVisible {
                let c = location(state.dot, in: frame)
                context.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(.white))
                context.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(Look.red))
            }
        }
    }
}

/// The dot run along the whole route, by itself, from end to end.
private struct Scrubber: View {
    @ObservedObject var model: RouteModel

    var body: some View {
        let preview = model.preview
        let state = preview.frames > 0 ? preview.plan.state(at: model.position, timeline: preview.timeline) : nil
        HStack(spacing: 12) {
            Slider(value: $model.scrub, in: 0...1)
                .disabled(preview.frames == 0)
            Text(state.map { "\($0.status.text)\($0.place.text.isEmpty ? "" : " \u{00B7} " + $0.place.text)" } ?? "No stops yet")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Look.dim)
                .frame(width: 280, alignment: .leading)
                .lineLimit(1)
        }
        .help("Runs the dot along the route, every stop moving on by itself, to see how it goes")
    }
}

/// The selected point, and the known places.
private struct Inspector: View {
    @ObservedObject var model: RouteModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let index = model.selected, model.content.route.indices.contains(index) {
                    // Fresh fields for each point, so one being typed in
                    // never lands on another.
                    point(index).id(index)
                } else {
                    section("Route") {
                        Text(summary).foregroundStyle(Look.dim).fixedSize(horizontal: false, vertical: true)
                    }
                }
                coordinates
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summary: String {
        let route = model.content.route
        guard !route.isEmpty else { return "Click the map where the dot starts." }
        let stops = model.content.stops.count - 1, through = route.count - 1 - stops
        return "The start, \(stops) stop\(stops == 1 ? "" : "s") and \(through) point\(through == 1 ? "" : "s") passed through. "
            + "Click a point to set it; click the map to add a stop at the end."
    }

    @ViewBuilder
    private func point(_ index: Int) -> some View {
        let point = model.content.route[index]
        let stop = model.content.stop(at: index)
        let stopNumber = model.content.stops.firstIndex(of: index)
        section(index == 0 ? "The start" : stopNumber.map { "Stop \($0)" } ?? "A point passed through") {
            if index > 0 {
                Picker("", selection: Binding(get: { point.stop != nil }, set: { model.setStop(index, $0) })) {
                    Text("Stop").tag(true)
                    Text("Passes through").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if index == 0 || point.stop != nil {
                if index > 0 {
                    Picker("Arrives", selection: Binding(get: { stop.arrival }, set: { arrival in
                        model.change(index, arrival == .jump ? "Jump to Stop" : "Travel to Stop") { $0.arrival = arrival }
                    })) {
                        Text("Travelling").tag(MapArrival.travel)
                        Text("By a jump").tag(MapArrival.jump)
                    }
                    if stop.arrival == .travel {
                        Stepper(value: Binding(get: { Double(stop.travelMs) / 1000 }, set: { seconds in
                            model.change(index, "Change Travel Time") {
                                $0.travelMs = min(max(Int((seconds * 1000).rounded()), MapStop.travelRange.lowerBound), MapStop.travelRange.upperBound)
                            }
                        }), in: 0.5...60, step: 0.5) {
                            Text("Takes \(SettingKey.morphTime.format(.number(stop.travelMs)))")
                        }
                    } else {
                        Text("SIGNAL LOST, then the view cuts here and the dot returns with SIGNAL ACQUIRED.")
                            .font(.caption).foregroundStyle(Look.dim).fixedSize(horizontal: false, vertical: true)
                    }
                }
                CommitField(label: "Status", value: stop.status, placeholder: MapCuePlan.Words.stationary) { text in
                    model.change(index, "Change Status") { $0.status = text }
                }
                CommitField(label: "Place", value: stop.place, placeholder: "e.g. KING\u{2019}S CROSS") { text in
                    model.change(index, "Change Place") { $0.place = text }
                }
            } else {
                Text("The dot passes through on its way to the next stop.").foregroundStyle(Look.dim)
            }
            HStack {
                Button("Insert Point After") { model.insert(after: index) }
                Spacer()
                Button("Delete") { model.delete(index) }
            }
        }
    }

    private var coordinates: some View {
        section("Coordinates") {
            Text("Two places whose latitude and longitude you know give the live coordinates on screen. Without them, none are shown.")
                .font(.caption).foregroundStyle(Look.dim).fixedSize(horizontal: false, vertical: true)
            ForEach([RouteModel.Anchor.a, .b], id: \.rawValue) { anchor in
                let known = model.content.reference.map { anchor == .a ? $0.a : $0.b }
                HStack {
                    Text(anchor.rawValue).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Look.brass)
                    Button(model.placing == anchor ? "Click the map\u{2026}" : (known == nil ? "Place on the Map" : "Move")) {
                        model.placing = model.placing == anchor ? nil : anchor
                    }
                }
                if let known {
                    HStack {
                        CommitField(label: "Lat", value: String(known.latitude), placeholder: "51.5") { text in
                            model.setReference(anchor, latitude: Double(text), longitude: nil)
                        }
                        CommitField(label: "Long", value: String(known.longitude), placeholder: "-0.12") { text in
                            model.setReference(anchor, latitude: nil, longitude: Double(text))
                        }
                    }
                }
            }
            if model.content.reference != nil {
                Button("Remove Coordinates") { model.clearReference() }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Look.dim)
            content()
        }
    }
}

/// A text field that changes the show once, when Return is pressed or it is
/// left, rather than at every key.
private struct CommitField: View {
    let label: String
    let value: String
    let placeholder: String
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(label) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
        }
        .onAppear { text = value }
        .onChange(of: value) { _, new in if !focused { text = new } }
        .onChange(of: focused) { _, now in if !now { save() } }
    }

    private func save() {
        if text != value { commit(text) }
    }
}
