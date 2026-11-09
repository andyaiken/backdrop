import Foundation

/// A layered image cue, worked out once when it loads: when each step sets
/// off, and how long the layers it brings on or takes off need.
///
/// The cue runs in parts, timed by a `GoTimeline`, as a morph does: moving on
/// by itself, every step is in the first part, each a pause after the one
/// before ends; with each step on GO, every step is a part of its own, and the
/// first part is the base picture standing alone.
///
/// Times are in the cue's frames: 0 is when the hold ends.
public struct LayeredCuePlan: Equatable, Sendable {
    public struct Timed: Equatable, Sendable {
        public let step: LayerStep
        /// The part of the cue it belongs to.
        public let part: Int
        /// Frames after its part starts that it sets off.
        public let offset: Int
        /// How long its slowest layer takes to arrive or go.
        public let ms: Int
    }

    public let steps: [Timed]
    /// The frames each part takes, from its start until its last step ends.
    public let parts: [Int]
    public let clockMs: Int
    public let layerMs: Int
    private let layerFades: [Int?]

    public init(_ content: LayeredContent, settings: LayeredSettings) {
        clockMs = max(1, settings.clockMs)
        layerMs = settings.layerMs
        layerFades = content.layers.map(\.fadeMs)
        var timed: [Timed] = [], parts = [0], filled = [false]
        for step in content.steps {
            let arrive = step.arriving.map { content.layers[$0].fadeMs ?? settings.layerMs }
            let leave = step.leaving.map { (content.layers[$0].fadeMs ?? settings.layerMs) / 2 }
            let ms = (arrive + leave).max() ?? 0
            if settings.eachStepOnGO {
                parts.append(0)
                filled.append(false)
            }
            let part = parts.count - 1
            let offset = filled[part] ? parts[part] + max(0, settings.pauseTicks) : 0
            parts[part] = offset + Self.frames(ms: ms, clockMs: clockMs)
            filled[part] = true
            timed.append(Timed(step: step, part: part, offset: offset, ms: ms))
        }
        steps = timed
        self.parts = parts
    }

    /// The clock's frames `ms` takes, rounded up so it has landed by the
    /// frame its part ends.
    static func frames(ms: Int, clockMs: Int) -> Int {
        Int((Double(ms) / Double(max(clockMs, 1))).rounded(.up))
    }

    /// How long layer `index` takes to arrive, in milliseconds.
    public func arriveMs(of index: Int) -> Int { layerFades[index] ?? layerMs }

    /// How long it takes to go: half as long, since a correction is brisk.
    public func leaveMs(of index: Int) -> Int { arriveMs(of: index) / 2 }

    /// The last step to have set off by frame `f`, or -1 before the first.
    public func reached(at f: Int, timeline: GoTimeline) -> Int {
        for k in steps.indices.reversed() {
            if let start = timeline.start(part: steps[k].part, offset: steps[k].offset), start <= f { return k }
        }
        return -1
    }

    /// Every step let go, and the last landed, by frame `f`; with no steps,
    /// once the hold is over.
    public func isFinished(at f: Int, timeline: GoTimeline) -> Bool {
        guard !timeline.hasPartsLeft else { return false }
        guard let last = steps.last, let start = timeline.start(part: last.part, offset: last.offset) else { return f >= 0 }
        return f >= start + Self.frames(ms: last.ms, clockMs: clockMs)
    }
}
