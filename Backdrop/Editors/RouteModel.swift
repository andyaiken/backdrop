import AppKit
import BackdropCore
import Combine
import ImageIO

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
