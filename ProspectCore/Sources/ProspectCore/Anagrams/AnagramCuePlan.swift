import Foundation

/// An anagram cue, worked out once when it loads: each anagram's steps as
/// they stand on stage, the moves between them, and when each move sets off.
///
/// The anagrams stand together from the start and are solved one after
/// another, but for any ignored, which keep their phrase jumbled, and any of
/// one line, solved already. Each move is an `AnagramPlan` from one step to
/// the next. Letters
/// a step of working doesn't use aren't lost: they dim, and gather on a line
/// beneath it in the order they stood, until a later step takes them up. The
/// answer takes what it needs and lets the rest fade, as a move always has.
///
/// The cue runs in parts. The first starts when the cue's hold ends; each
/// after it waits for GO, as the cue's advance says. Within a part, each move
/// sets off a pause after the one before it lands.
public struct AnagramCuePlan: Equatable, Sendable {
    /// One step as it stands on stage.
    public struct Step: Equatable, Sendable {
        /// The step's own lines, then any it leaves unused, dimmed.
        public var lines: [String]
        /// Where the dimmed lines begin: `lines.count` when there are none.
        public var dimFrom: Int

        public func isDim(_ slot: AnagramPlan.Slot) -> Bool {
            slot.line >= dimFrom
        }
    }

    /// From one step to the next.
    public struct Move: Equatable, Sendable {
        public var plan: AnagramPlan
        /// The part of the cue it belongs to.
        public var part: Int
        /// Frames after its part starts that it sets off.
        public var offset: Int
        /// Into the answer, so its letters warm to bone as they land.
        /// Working stays slate, so a wrong guess never looks solved.
        public var warms: Bool
    }

    /// One anagram.
    public struct Track: Equatable, Sendable {
        /// The phrase, each step of working, then the answer.
        public var steps: [Step]
        /// Each move goes from the step at its index to the next.
        public var moves: [Move]
        /// The phrase standing still, for an anagram the cue doesn't solve.
        public var still: AnagramPlan
        /// Solved already, so it stands in bone from the start.
        public var solvedAlready: Bool
    }

    public let tracks: [Track]
    /// The frames each part takes, from its start until its last move lands.
    /// A cue that waits for GO from the start has nothing in its first part.
    public let parts: [Int]

    /// - Parameters:
    ///   - wave: As for a single move.
    ///   - pause: Frames each step rests, landed, before the next sets off.
    ///   - random: Each move's small extra delays, drawn in order.
    public init(_ anagrams: [Anagram], wave: Int, pause: Int, advance: AnagramAdvance, random: inout some UnitRandom) {
        var tracks: [Track] = [], parts = [0], filled = [false]
        for anagram in anagrams {
            // One the cue doesn't solve shows only where it stands.
            let steps = Self.steps(anagram.isSolvedOnStage ? anagram.steps : Array(anagram.steps.prefix(1)))
            guard !steps.isEmpty else { continue }
            var moves: [Move] = []
            for k in steps.indices.dropLast() {
                let plan = AnagramPlan(fromLines: steps[k].lines, toLines: steps[k + 1].lines, wave: wave, random: &random)
                if advance == .eachStep || (advance == .eachAnagram && k == 0) {
                    parts.append(0)
                    filled.append(false)
                }
                let part = parts.count - 1
                let offset = filled[part] ? parts[part] + max(0, pause) : 0
                parts[part] = offset + plan.duration
                filled[part] = true
                moves.append(Move(plan: plan, part: part, offset: offset, warms: k + 1 == steps.count - 1))
            }
            tracks.append(Track(steps: steps, moves: moves, still: .still(steps[0].lines), solvedAlready: anagram.isSolvedAlready))
        }
        self.tracks = tracks
        self.parts = parts
    }

    /// The steps as they stand on stage. Working carries beneath it, dimmed,
    /// every letter of the step before that it doesn't use. The phrase and
    /// the answer stand alone.
    static func steps(_ texts: [String]) -> [Step] {
        var steps: [Step] = []
        for (k, text) in texts.enumerated() {
            let own = AnagramPlan.lines(text)
            guard k > 0, k < texts.count - 1 else {
                steps.append(Step(lines: own, dimFrom: own.count))
                continue
            }
            let spare = unused(by: text, from: steps[k - 1].lines)
            let dim = spare.isEmpty ? [] : AnagramPlan.lines(spare.map(String.init).joined(separator: " "))
            steps.append(Step(lines: own + dim, dimFrom: own.count))
        }
        return steps
    }

    /// The letters and digits of `lines` that `text` doesn't use, in the
    /// order they stand. A step uses the first of each letter it has, in
    /// reading order and whatever its case, as a move matches them, so these
    /// are exactly the letters a move sends to the dimmed line.
    static func unused(by text: String, from lines: [String]) -> [Character] {
        func counts(_ c: Character) -> Bool { c.isLetter || c.isNumber }
        var spare = lines.joined(separator: " ").filter(counts)
        for c in text.filter(counts) {
            if let i = spare.firstIndex(where: { $0.uppercased() == c.uppercased() }) { spare.remove(at: i) }
        }
        return Array(spare)
    }
}

extension AnagramCuePlan {
    /// When each part of a cue starts, as GO lets them go. The first starts
    /// on frame 0, when the hold ends.
    public struct Timeline: Equatable, Sendable {
        public private(set) var starts = [0]
        public let parts: [Int]

        public init(parts: [Int]) {
            self.parts = parts
        }

        /// Whether any part still waits for GO.
        public var hasPartsLeft: Bool { starts.count < parts.count }

        /// When the parts let go so far have all finished.
        private var end: Int { starts[starts.count - 1] + parts[starts.count - 1] }

        /// Done everything it can by frame `f`, with more still to come on GO.
        public func isWaiting(at f: Int) -> Bool {
            hasPartsLeft && f >= end
        }

        /// Every part has run, and the last has landed.
        public func isFinished(at f: Int) -> Bool {
            !hasPartsLeft && f >= end
        }

        /// GO on frame `f`: the next part starts then, or as soon as the part
        /// before it has finished, if that is later, so nothing jumps.
        public mutating func carryOn(at f: Int) {
            guard hasPartsLeft else { return }
            starts.append(max(f, end))
        }

        /// Every part let go, each straight after the one before, as when the
        /// cue is put up finished.
        public mutating func carryOnToEnd() {
            while hasPartsLeft { starts.append(end) }
        }

        /// The frame a move sets off; nil while its part waits for GO.
        public func start(of move: Move) -> Int? {
            starts.indices.contains(move.part) ? starts[move.part] + move.offset : nil
        }
    }

    /// Which of a track's moves is on stage on frame `f`: the latest to have
    /// set off, or the first, waiting to go. Nil for an anagram that stands
    /// still.
    public func shown(_ track: Track, at f: Int, timeline: Timeline) -> (index: Int, start: Int?)? {
        guard !track.moves.isEmpty else { return nil }
        let started = track.moves.indices.last { timeline.start(of: track.moves[$0]).map { $0 <= f } ?? false }
        let index = started ?? 0
        return (index, timeline.start(of: track.moves[index]))
    }
}
