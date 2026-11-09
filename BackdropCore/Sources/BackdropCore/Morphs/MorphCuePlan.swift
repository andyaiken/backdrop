import Foundation

/// A morph cue, worked out once when it loads: each stage's mesh and morph
/// time, and when each sets off.
///
/// The first picture stands from the start. Each stage after it becomes the
/// next picture. The cue runs in parts, timed by a `GoTimeline`: moving on by
/// itself, every stage is in the first part, each a pause after the one
/// before lands; with each stage on GO, every stage is a part of its own,
/// and the first part, before any GO, is the first picture standing.
public struct MorphCuePlan: Equatable, Sendable {
    public struct Stage: Equatable, Sendable {
        /// From the picture at the stage's index to the next.
        public let mesh: MorphMesh
        public let morphMs: Int
        /// The part of the cue it belongs to.
        public let part: Int
        /// Frames after its part starts that it sets off.
        public let offset: Int
    }

    /// What the stage shows at a moment.
    public struct Shown: Equatable, Sendable {
        /// The stage under way or last landed; nil before the first sets off,
        /// with the first picture standing.
        public let stage: Int?
        /// How far through it is, from 0 to 1, eased.
        public let progress: Double

        /// The picture it comes from, and the one it becomes.
        public init(stage: Int?, progress: Double) {
            self.stage = stage
            self.progress = progress
        }

        public var from: Int { stage ?? 0 }
        public var to: Int { stage.map { $0 + 1 } ?? 0 }
    }

    public let stages: [Stage]
    /// The frames each part takes, from its start until its last stage lands.
    public let parts: [Int]
    public let clockMs: Int

    public init(_ content: MorphContent, settings: MorphSettings) {
        clockMs = max(1, settings.clockMs)
        var stages: [Stage] = [], parts = [0], filled = [false]
        for k in 0..<content.stageCount {
            let into = content.pictures[k + 1]
            let ms = into.morphMs ?? settings.morphMs
            if settings.eachStageOnGO {
                parts.append(0)
                filled.append(false)
            }
            let part = parts.count - 1
            let offset = filled[part] ? parts[part] + max(0, settings.pauseTicks) : 0
            parts[part] = offset + Self.frames(ms: ms, clockMs: clockMs)
            filled[part] = true
            stages.append(Stage(mesh: MorphMesh(pairs: into.pairs), morphMs: ms, part: part, offset: offset))
        }
        self.stages = stages
        self.parts = parts
    }

    /// The clock's frames a stage of `ms` takes, rounded up so it has landed
    /// by the frame its part ends.
    static func frames(ms: Int, clockMs: Int) -> Int {
        Int((Double(ms) / Double(max(clockMs, 1))).rounded(.up))
    }

    /// Where the cue stands `position` frames in, fractions and all: the last
    /// stage to have set off, and how far through it is.
    public func shown(at position: Double, timeline: GoTimeline) -> Shown {
        for k in stages.indices.reversed() {
            guard let start = timeline.start(part: stages[k].part, offset: stages[k].offset), Double(start) <= position else { continue }
            let ms = (position - Double(start)) * Double(clockMs)
            return Shown(stage: k, progress: MorphTiming.progress(ms: ms, morphMs: stages[k].morphMs))
        }
        return Shown(stage: nil, progress: 0)
    }

    /// Every stage let go, and the last landed, by `position`; for a cue
    /// of one picture, once its hold is over.
    public func isFinished(at position: Double, timeline: GoTimeline) -> Bool {
        guard !timeline.hasPartsLeft else { return false }
        guard let last = stages.last, let start = timeline.start(part: last.part, offset: last.offset) else { return position >= 0 }
        return (position - Double(start)) * Double(clockMs) >= Double(last.morphMs)
    }
}

extension MorphContent {
    /// Where the cue waits for GO, in order: before each stage, with each
    /// stage on GO. None when it moves on by itself.
    public func goPoints(eachStageOnGO: Bool) -> [GoPoint] {
        guard eachStageOnGO else { return [] }
        return pictures.dropFirst().map { GoPoint(unit: .stage, text: Self.name(of: $0.src), cuePoint: $0.cuePoint) }
    }

    /// A picture as the cue list and the sheet name it: its file's name.
    public static func name(of path: String) -> String {
        path.isEmpty ? "no picture" : ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}
