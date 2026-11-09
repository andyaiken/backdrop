import Foundation

/// A map cue, worked out once when it loads: each leg of the route from one
/// stop to the next, when each sets off, and so where the dot is, what the
/// view centres on and what the screen says at any moment.
///
/// The dot starts at the route's first point. Each leg after it ends at a
/// stop: travelling, the dot follows the points between at the speed of a
/// vehicle, pulling away and slowing to a halt; jumping, the dot and its
/// trail vanish, SIGNAL LOST flashes, the view cuts to the stop and the dot
/// comes back with SIGNAL ACQUIRED.
///
/// The cue runs in parts, timed by a `GoTimeline`, as a morph does: moving on
/// by itself, every leg is in the first part, each a pause after the one
/// before ends; with each stop on GO, every leg is a part of its own, and
/// the first part is the dot at its start.
///
/// Times are in the cue's milliseconds: 0 is when the hold ends, so the hold
/// runs from minus its length.
public struct MapCuePlan: Equatable, Sendable {
    public struct Leg: Equatable, Sendable {
        /// The places in the route it runs between.
        public let from: Int
        public let to: Int
        /// The points it passes, the stops at each end included. A jump has
        /// only the two.
        public let path: [PicturePoint]
        public let jump: Bool
        /// How long it takes: the travel, or the jump's lost signal and its
        /// return.
        public let ms: Int
        /// The part of the cue it belongs to.
        public let part: Int
        /// Frames after its part starts that it sets off.
        public let offset: Int
        /// How far along the path each point is, the first at 0, measured
        /// at the map's own shape.
        let distances: [Double]
    }

    /// How long a jump's signal stays lost, and how long SIGNAL ACQUIRED
    /// shows once the dot is back.
    public static let lostMs = 1800
    public static let acquiredMs = 1600
    /// How long each letter of the screen's text takes to type.
    public static let typeMs = 40
    /// The share of a leg spent pulling away, and as much slowing down.
    static let easing = 0.2

    public let start: PicturePoint
    public let legs: [Leg]
    /// The frames each part takes, from its start until its last leg ends.
    public let parts: [Int]
    public let clockMs: Int
    /// The map's width over its height.
    public let aspect: Double
    /// The closest a still view comes: the map's width over this.
    let zoom: Int
    /// When the cue starts, before the hold, in the cue's milliseconds.
    public let startMs: Double
    let content: MapContent

    /// - Parameter aspect: The map's width over its height, so distances,
    ///   and with them the dot's speed, are true on it.
    public init(_ content: MapContent, settings: MapSettings, aspect: Double = 1) {
        self.content = content
        clockMs = max(1, settings.clockMs)
        self.aspect = max(aspect, 0.01)
        zoom = max(settings.zoom, 1)
        startMs = -Double(settings.holdTicks * clockMs)
        start = content.route.first?.at ?? PicturePoint(x: 0.5, y: 0.5)
        var legs: [Leg] = [], parts = [0], filled = [false]
        let stops = content.stops
        for (from, to) in zip(stops, stops.dropFirst()) {
            let stop = content.stop(at: to)
            let jump = stop.arrival == .jump
            let path = jump ? [content.route[from].at, content.route[to].at] : content.route[from...to].map(\.at)
            let ms = jump ? Self.lostMs + Self.acquiredMs : stop.travelMs
            if settings.eachStopOnGO {
                parts.append(0)
                filled.append(false)
            }
            let part = parts.count - 1
            let offset = filled[part] ? parts[part] + max(0, settings.pauseTicks) : 0
            parts[part] = offset + Int((Double(ms) / Double(clockMs)).rounded(.up))
            filled[part] = true
            var distances = [0.0]
            for (a, b) in zip(path, path.dropFirst()) {
                distances.append(distances[distances.count - 1] + hypot((b.x - a.x) * aspect, b.y - a.y))
            }
            legs.append(Leg(from: from, to: to, path: path, jump: jump, ms: ms, part: part, offset: offset, distances: distances))
        }
        self.legs = legs
        self.parts = parts
    }

    // MARK: Where things are

    /// The signal, as the readout and the status line show it.
    public enum Signal: Equatable, Sendable {
        case live, lost, acquired
    }

    /// A line of text, and when it started to type.
    public struct Line: Equatable, Sendable {
        public var text: String
        public var since: Double

        /// As much as has typed by `ms`.
        public func typed(at ms: Double) -> String {
            String(text.prefix(max(0, Int((ms - since) / Double(MapCuePlan.typeMs)) + 1)))
        }

        /// Still typing at `ms`.
        public func isTyping(at ms: Double) -> Bool {
            typed(at: ms).count < text.count
        }
    }

    /// Everything on screen at a moment.
    public struct State: Equatable, Sendable {
        public var dot: PicturePoint
        public var dotVisible: Bool
        /// The point on the map at the middle of the stage, for a view that
        /// follows the dot.
        public var view: PicturePoint
        public var signal: Signal
        public var header: Line
        public var status: Line
        public var place: Line
        /// No trail from before this, in the cue's milliseconds: a jump
        /// leaves its old trail behind.
        public var trailSince: Double
    }

    /// Words the screen uses unless a stop says its own.
    public enum Words {
        public static let moving = "IN TRANSIT"
        public static let stationary = "STATIONARY"
        public static let lost = "SIGNAL LOST"
        public static let acquired = "SIGNAL ACQUIRED"
    }

    /// The part of the map a view that holds still shows on a stage of
    /// `stageAspect`, width over height: the whole route with a margin round
    /// it, the stage's shape, never closer than Zoom and never wider than
    /// the whole map, and kept inside the map's edges where it fits. Its
    /// middle, and its width as a share of the map's.
    public func stillView(stageAspect: Double) -> (centre: PicturePoint, width: Double) {
        // Measured in map heights, so across and down are alike.
        let points = content.route.map(\.at)
        guard !points.isEmpty else { return (PicturePoint(x: 0.5, y: 0.5), 1) }
        let xs = points.map { $0.x * aspect }, ys = points.map(\.y)
        let left = xs.min()!, right = xs.max()!, top = ys.min()!, bottom = ys.max()!
        let margin = 0.15 * max(right - left, bottom - top, 0.05)
        let stage = max(stageAspect, 0.01)
        var width = max(right - left + 2 * margin, (bottom - top + 2 * margin) * stage)
        width = max(width, aspect / Double(zoom))
        width = min(width, max(aspect, stage))
        let height = width / stage
        func keep(_ middle: Double, _ span: Double, within size: Double) -> Double {
            span >= size ? size / 2 : min(max(middle, span / 2), size - span / 2)
        }
        let x = keep((left + right) / 2, width, within: aspect), y = keep((top + bottom) / 2, height, within: 1)
        return (PicturePoint(x: x / aspect, y: y), width / aspect)
    }

    /// The milliseconds into the cue at `position` frames.
    public func ms(at position: Double) -> Double {
        position * Double(clockMs)
    }

    /// When a leg set off, in the cue's milliseconds, or nil while it waits
    /// for GO.
    func startMs(of leg: Leg, timeline: GoTimeline) -> Double? {
        timeline.start(part: leg.part, offset: leg.offset).map { Double($0 * clockMs) }
    }

    /// Everything on screen `position` frames in, fractions and all.
    public func state(at position: Double, timeline: GoTimeline) -> State {
        let now = ms(at: position)
        let first = content.stop(at: 0)
        var state = State(dot: start, dotVisible: true, view: start, signal: .live,
                          header: Line(text: content.text, since: startMs),
                          status: Line(text: first.status.isEmpty ? Words.stationary : first.status, since: startMs),
                          place: Line(text: first.place, since: startMs), trailSince: startMs)
        for leg in legs {
            guard let begin = startMs(of: leg, timeline: timeline), begin <= now else { break }
            let stop = content.stop(at: leg.to), end = leg.path[leg.path.count - 1]
            let arrived = Line(text: stop.status.isEmpty ? Words.stationary : stop.status, since: begin + Double(leg.ms))
            let place = Line(text: stop.place, since: begin + Double(leg.ms))
            let t = now - begin
            if leg.jump {
                let cut = begin + Double(Self.lostMs)
                if t < Double(Self.lostMs) {
                    state.dotVisible = false
                    state.signal = .lost
                    state.status = Line(text: Words.lost, since: begin)
                    state.place = Line(text: "", since: begin)
                } else {
                    state.dot = end
                    state.view = end
                    state.dotVisible = true
                    state.trailSince = cut
                    if t < Double(leg.ms) {
                        state.signal = .acquired
                        state.status = Line(text: Words.acquired, since: cut)
                        state.place = Line(text: "", since: cut)
                    } else {
                        state.signal = .live
                        state.status = arrived
                        state.place = place
                    }
                }
            } else if t < Double(leg.ms) {
                state.dot = point(on: leg, at: Self.travelled(t / Double(leg.ms)))
                state.view = state.dot
                state.signal = .live
                state.status = Line(text: Words.moving, since: begin)
                state.place = Line(text: "", since: begin)
            } else {
                state.dot = end
                state.view = end
                state.signal = .live
                state.status = arrived
                state.place = place
            }
        }
        return state
    }

    /// Every leg let go, and the last one over, by `position`; for a route
    /// of one stop, once the hold is over.
    public func isFinished(at position: Double, timeline: GoTimeline) -> Bool {
        guard !timeline.hasPartsLeft else { return false }
        guard let last = legs.last, let begin = startMs(of: last, timeline: timeline) else { return position >= 0 }
        return ms(at: position) - begin >= Double(last.ms)
    }

    /// How far along a leg the dot is, from 0 to 1, `t` of the way through
    /// its time: pulling away, at speed, then slowing to a halt.
    public static func travelled(_ t: Double) -> Double {
        let t = min(max(t, 0), 1), a = easing, top = 1 / (1 - a)
        if t < a { return top * t * t / (2 * a) }
        if t > 1 - a { return 1 - top * (1 - t) * (1 - t) / (2 * a) }
        return top * (t - a / 2)
    }

    /// The point `u` of the way along a leg's path, by distance.
    func point(on leg: Leg, at u: Double) -> PicturePoint {
        let total = leg.distances[leg.distances.count - 1]
        guard total > 0 else { return leg.path[leg.path.count - 1] }
        let d = u * total
        for i in 1..<leg.path.count where d <= leg.distances[i] {
            let span = leg.distances[i] - leg.distances[i - 1]
            return leg.path[i - 1].mix(leg.path[i], span > 0 ? (d - leg.distances[i - 1]) / span : 1)
        }
        return leg.path[leg.path.count - 1]
    }

    /// The trail behind the dot at `position`: where it was every `stepMs`
    /// over the last `seconds`, oldest first, each with how faded it is, from
    /// 0, just now, to 1, gone. None from before a jump, or while the
    /// signal is lost.
    public func trail(at position: Double, timeline: GoTimeline, seconds: Int, stepMs: Double = 80) -> [(point: PicturePoint, age: Double)] {
        guard seconds > 0 else { return [] }
        let now = ms(at: position), length = Double(seconds * 1000)
        let current = state(at: position, timeline: timeline)
        guard current.dotVisible else { return [] }
        let from = max(now - length, current.trailSince)
        var samples: [(PicturePoint, Double)] = []
        var t = from
        while t < now {
            samples.append((state(at: t / Double(clockMs), timeline: timeline).dot, (now - t) / length))
            t += stepMs
        }
        samples.append((current.dot, 0))
        return samples
    }
}

/// The dot's blink, once a second on the cue's clock: it lights hard and
/// fades, and a ring spreads out from it and fades.
public enum MapPulse {
    /// How long the ring takes to spread out.
    public static let ringMs = 800.0

    /// The dot's brightness, from 1 as it lights to a glow between.
    public static func brightness(at ms: Double) -> Double {
        let phase = ms.truncatingRemainder(dividingBy: 1000)
        let p = phase < 0 ? phase + 1000 : phase
        return 0.35 + 0.65 * exp(-p / 140)
    }

    /// How far the ring has spread, from 0 to 1, or nil once it has gone.
    public static func ring(at ms: Double) -> Double? {
        let phase = ms.truncatingRemainder(dividingBy: 1000)
        let p = phase < 0 ? phase + 1000 : phase
        return p < ringMs ? p / ringMs : nil
    }
}

extension MapContent {
    /// Where the cue waits for GO, in order: before the dot leaves for each
    /// stop, with each stop on GO. None when it moves on by itself.
    public func goPoints(eachStopOnGO: Bool) -> [GoPoint] {
        guard eachStopOnGO else { return [] }
        return stops.dropFirst().enumerated().map { n, index in
            let stop = stop(at: index)
            let name = [stop.place, stop.status].first { !$0.isEmpty } ?? "stop \(n + 1)"
            return GoPoint(unit: .stop, text: stop.arrival == .jump ? name + " (jump)" : name, cuePoint: stop.cuePoint)
        }
    }
}
