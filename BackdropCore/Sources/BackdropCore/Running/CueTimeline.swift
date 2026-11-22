import Foundation

/// A cue laid out in time, as the Studio's timeline draws it: the
/// transition in, the hold, the kind's own tracks, where it waits for GO,
/// and what happens after.
///
/// Worked out from the same plans the renderers run, with the dice they
/// roll seeded at 0, so it shows what the stage does. Frames are steps of
/// the cue's clock from GO: the hold is frames 0 up to `holdTicks`, and the
/// kind's own tracks start where it ends.
public struct CueTimeline: Codable, Equatable, Sendable {
    public var clockMs: Int
    /// Zero for kinds with no hold.
    public var holdTicks: Int
    /// The transition into the cue. Nil for the first cue.
    public var transitionIn: Span?
    /// The kind's own tracks, in order.
    public var tracks: [Track]
    /// The frames of each GO the cue waits for partway, each part let go
    /// straight after the one before.
    public var goes: [Int]
    public var then: Then
    /// When the last of it finishes, with every part let go.
    public var endFrame: Int

    public struct Track: Codable, Equatable, Sendable {
        public var name: String
        public var spans: [Span]
    }

    public struct Span: Codable, Equatable, Sendable {
        public var start: Int
        public var end: Int
        public var label: String?
        /// The setting this span shows: what a click opens, and what
        /// dragging its handle changes.
        public var key: SettingKey?
        /// Where it can be dragged, if it can.
        public var handle: Handle?

        public init(start: Int, end: Int, label: String? = nil, key: SettingKey? = nil, handle: Handle? = nil) {
            self.start = start
            self.end = end
            self.label = label
            self.key = key
            self.handle = handle
        }
    }

    /// What dragging a span does.
    public enum Handle: String, Codable, Equatable, Sendable {
        /// Its end: the setting is its length.
        case end
        /// The slope across a fan of spans: the wave between letters.
        case slope
    }

    /// After the cue.
    public enum Then: Codable, Equatable, Sendable {
        case waits
        case after(ms: Int)
        case whenFinished(waitMs: Int)
    }

    /// The seconds a frame stands for.
    public func seconds(_ frame: Int) -> Double { Double(frame * clockMs) / 1000 }

    // MARK: Building

    /// - Parameters:
    ///   - isFirst: The first cue has no transition in.
    ///   - clipSeconds: A video's length, which the model can't read from
    ///     its file.
    public init(cue: Cue, show: ShowSettings, isFirst: Bool, clipSeconds: Double? = nil) {
        let timing = cue.timing
        let clock = max(1, timing.clockMs)
        let hold = timing.isInstant ? 0 : timing.holdTicks
        clockMs = clock
        holdTicks = hold
        func frames(_ ms: Int) -> Int { Int((Double(ms) / Double(clock)).rounded(.up)) }
        let transitionIn: Span? = isFirst ? nil : Span(start: 0, end: cue.transition.hasLength ? frames(cue.transition.fadeMs) : 0,
                                            label: cue.transition.style.rawValue, key: .fade, handle: .end)
        var tracks: [Track] = []
        var parts: [Int] = []

        /// One span per part of the cue, each let go straight after the one
        /// before: their starts, from the hold's end.
        func starts(of parts: [Int]) -> [Int] {
            var timeline = GoTimeline(parts: parts.isEmpty ? [0] : parts)
            timeline.carryOnToEnd()
            return timeline.starts
        }

        switch cue.content {
        case .title(let c):
            var random = SeededRandom(seed: 0)
            let reveal = TitleReveal(cue: c, settings: c.settings, random: &random)
            let moving = reveal.titlePlan.characters.filter(\.moves)
            tracks.append(Track(name: "Letters", spans: moving.map {
                Span(start: hold + $0.start, end: hold + $0.start + $0.total, key: .wave, handle: .slope)
            }))
            parts = [moving.map { $0.start + $0.total }.max() ?? 0]

        case .anagram(let c):
            var random = SeededRandom(seed: 0)
            let plan = AnagramCuePlan(c.anagrams, wave: c.settings.waveTicks, pause: c.settings.pauseTicks,
                                      advance: c.settings.advance, random: &random)
            parts = plan.parts
            let at = starts(of: parts)
            tracks.append(Track(name: "Working", spans: parts.indices.map { i in
                Span(start: hold + at[i], end: hold + at[i] + parts[i], label: "Part \(i + 1)", key: .wave, handle: .slope)
            }))

        case .image(let c):
            let s = c.settings
            var random = SeededRandom(seed: 0)
            let grid = TileGrid(imageWidth: 16, imageHeight: 9, columns: s.gridColumns)
            let schedule = TileSchedule(grid: grid, order: s.order == .quarters ? .random : s.order, wave: s.waveTicks,
                                        random: &random)
            let end = schedule.settleFrame(flipMs: s.flipMs, clockMs: clockMs)
            tracks.append(Track(name: "Tiles", spans: [
                Span(start: hold, end: hold + end, label: "\(s.order.rawValue) \u{00B7} wave \(s.waveTicks)", key: .flip, handle: .end),
            ]))
            parts = [end]

        case .morph(let c):
            let plan = MorphCuePlan(c, settings: c.settings)
            parts = plan.parts
            let at = starts(of: parts)
            tracks.append(Track(name: "Stages", spans: plan.stages.enumerated().map { i, stage in
                let start = hold + at[stage.part] + stage.offset
                return Span(start: start, end: start + frames(stage.morphMs), label: "Picture \(i + 2)",
                            key: .morphTime, handle: .end)
            }))

        case .map(let c):
            let plan = MapCuePlan(c, settings: c.settings)
            parts = plan.parts
            let at = starts(of: parts)
            tracks.append(Track(name: "Legs", spans: plan.legs.enumerated().map { i, leg in
                let start = hold + at[leg.part] + leg.offset
                return Span(start: start, end: start + frames(leg.ms), label: "Stop \(i + 1)", key: .pause)
            }))

        case .layered(let c):
            let plan = LayeredCuePlan(c, settings: c.settings)
            parts = plan.parts
            let at = starts(of: parts)
            tracks.append(Track(name: "Layers", spans: plan.steps.enumerated().map { i, step in
                let start = hold + at[step.part] + step.offset
                return Span(start: start, end: start + frames(step.ms), label: "Step \(i + 1)", key: .layerTime, handle: .end)
            }))

        case .keypad(let c):
            let plan = KeypadCuePlan(c)
            parts = plan.parts
            let at = starts(of: parts)
            var presses: [Span] = [], flashes: [Span] = []
            for (i, stage) in c.stages.enumerated() {
                let base = hold + at[i]
                for p in stage.presses.indices {
                    presses.append(Span(start: base + p * plan.interval, end: base + p * plan.interval + 1, key: .pause))
                }
                if stage.verdict != nil {
                    let start = base + stage.presses.count * plan.interval
                    flashes.append(Span(start: start, end: start + KeypadCuePlan.flashTicks, label: "flash"))
                }
            }
            tracks.append(Track(name: "Keys", spans: presses))
            if !flashes.isEmpty { tracks.append(Track(name: "Verdict", spans: flashes)) }

        case .cascade(let c):
            var random = SeededRandom(seed: 0)
            let plan = CascadeCuePlan(c, aspect: 16 / 9, random: &random)
            parts = plan.parts
            let at = starts(of: parts)
            var spans = [Span(start: 0, end: hold, label: "rain", key: .hold, handle: .end)]
            if c.hasMessage {
                let start = hold + (at.last ?? 0)
                spans.append(Span(start: start, end: start + plan.resolveTicks, label: "message"))
            }
            tracks.append(Track(name: "Rain", spans: spans))

        case .conversation(let c):
            let plan = ConversationCuePlan(c)
            parts = plan.parts
            let at = starts(of: parts)
            tracks.append(Track(name: "Messages", spans: parts.indices.map { i in
                Span(start: at[i], end: at[i] + max(1, parts[i]), label: "Part \(i + 1)", key: .pause)
            }))

        case .sms(let c):
            let end = frames(c.settings.entranceMs)
            tracks.append(Track(name: "Entrance", spans: [Span(start: 0, end: max(1, end), label: c.settings.entrance.rawValue)]))
            parts = [end]

        case .video:
            let end = clipSeconds.map { frames(Int($0 * 1000)) } ?? 0
            if end > 0 { tracks.append(Track(name: "Clip", spans: [Span(start: 0, end: end, label: "plays")])) }
            parts = [end]

        case .text, .blank, .feed:
            parts = [0]
        }

        let ends = starts(of: parts)
        goes = ends.dropFirst().map { hold + $0 }
        let last = zip(ends, parts.isEmpty ? [0] : parts).map { $0 + $1 }.max() ?? 0
        endFrame = hold + last
        then = switch cue.continueMode {
        case .whenCued: .waits
        case .after(let ms): .after(ms: ms)
        case .whenFinished(let ms): .whenFinished(waitMs: ms)
        }
        self.tracks = tracks
        self.transitionIn = transitionIn
    }
}
