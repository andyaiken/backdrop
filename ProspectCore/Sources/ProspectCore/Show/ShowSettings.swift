import Foundation

/// The show's defaults for every per-cue setting, plus what is show-wide.
public struct ShowSettings: Equatable, Sendable {
    /// Milliseconds per frame of the cue clock.
    public var clockMs = 44
    /// Frames between successive characters, or diagonal tile steps.
    public var waveTicks = 3
    /// Frames a cue holds its opening state before it starts to resolve.
    public var holdTicks = 44
    public var histogram = true
    public var sceneLine = true
    public var letters = TitleLetters.cycle
    public var bars = TitleBars.letters
    public var gridColumns = 12
    public var flipMs = 420
    public var order = TileOrder.diagonal
    public var reveal = TileReveal.flip
    /// How an anagram cue moves on from each step: by itself, or on GO.
    public var advance = AnagramAdvance.byItself
    /// Frames an anagram rests on each step before the next moves.
    public var pauseTicks = 44
    /// The font family anagram letters are set in. Empty is the stage's own
    /// type, SF Mono.
    public var anagramFont = ""
    /// How long a morph takes, from the first picture to the second.
    public var morphMs = 3000
    /// How the stage changes to each cue, and how long each fade takes.
    public var transition = Transition.standard.style
    public var fadeMs = Transition.standard.fadeMs

    /// Title text size, percent. Show-wide.
    public var textScale = 100
    /// Show-wide.
    public var geometry = Geometry()
    /// The display the projector window last ran on.
    public var projector: DisplayIdentity?

    public init() {}

    public func resolved(_ o: TitleOverrides) -> TitleSettings {
        TitleSettings(
            clockMs: o.clockMs ?? clockMs,
            waveTicks: o.waveTicks ?? waveTicks,
            holdTicks: o.holdTicks ?? holdTicks,
            histogram: o.histogram ?? histogram,
            sceneLine: o.sceneLine ?? sceneLine,
            letters: o.letters ?? letters,
            bars: o.bars ?? bars
        )
    }

    public func resolved(_ o: AnagramOverrides) -> AnagramSettings {
        AnagramSettings(clockMs: o.clockMs ?? clockMs, waveTicks: o.waveTicks ?? waveTicks, holdTicks: o.holdTicks ?? holdTicks,
                        advance: o.advance ?? advance, pauseTicks: o.pauseTicks ?? pauseTicks, font: o.font ?? anagramFont)
    }

    public func resolved(_ o: MorphOverrides) -> MorphSettings {
        MorphSettings(clockMs: o.clockMs ?? clockMs, holdTicks: o.holdTicks ?? holdTicks, morphMs: o.morphMs ?? morphMs)
    }

    public func resolved(_ o: ImageOverrides) -> ImageSettings {
        ImageSettings(
            clockMs: o.clockMs ?? clockMs,
            waveTicks: o.waveTicks ?? waveTicks,
            holdTicks: o.holdTicks ?? holdTicks,
            gridColumns: o.gridColumns ?? gridColumns,
            flipMs: o.flipMs ?? flipMs,
            order: o.order ?? order,
            reveal: o.reveal ?? reveal
        )
    }
}

/// The settings a title cue runs with, once its overrides are applied.
public struct TitleSettings: Equatable, Sendable {
    public var clockMs: Int
    public var waveTicks: Int
    public var holdTicks: Int
    public var histogram: Bool
    public var sceneLine: Bool
    public var letters: TitleLetters
    public var bars: TitleBars

    public init(clockMs: Int, waveTicks: Int, holdTicks: Int, histogram: Bool, sceneLine: Bool, letters: TitleLetters = .cycle,
                bars: TitleBars = .letters) {
        self.clockMs = clockMs
        self.waveTicks = waveTicks
        self.holdTicks = holdTicks
        self.histogram = histogram
        self.sceneLine = sceneLine
        self.letters = letters
        self.bars = bars
    }
}

/// The settings an anagram cue runs with, once its overrides are applied.
public struct AnagramSettings: Equatable, Sendable {
    public var clockMs: Int
    public var waveTicks: Int
    public var holdTicks: Int
    public var advance: AnagramAdvance
    public var pauseTicks: Int
    /// A font family's name. Empty is the stage's own type.
    public var font: String

    public init(clockMs: Int, waveTicks: Int, holdTicks: Int, advance: AnagramAdvance = .byItself, pauseTicks: Int = 44, font: String = "") {
        self.clockMs = clockMs
        self.waveTicks = waveTicks
        self.holdTicks = holdTicks
        self.advance = advance
        self.pauseTicks = pauseTicks
        self.font = font
    }
}

/// The settings a morph cue runs with, once its overrides are applied.
public struct MorphSettings: Equatable, Sendable {
    public var clockMs: Int
    public var holdTicks: Int
    public var morphMs: Int

    public init(clockMs: Int, holdTicks: Int, morphMs: Int) {
        self.clockMs = clockMs
        self.holdTicks = holdTicks
        self.morphMs = morphMs
    }
}

/// The settings an image cue runs with, once its overrides are applied.
public struct ImageSettings: Equatable, Sendable {
    public var clockMs: Int
    public var waveTicks: Int
    public var holdTicks: Int
    public var gridColumns: Int
    public var flipMs: Int
    public var order: TileOrder
    public var reveal: TileReveal

    public init(clockMs: Int, waveTicks: Int, holdTicks: Int, gridColumns: Int, flipMs: Int, order: TileOrder, reveal: TileReveal = .flip) {
        self.clockMs = clockMs
        self.waveTicks = waveTicks
        self.holdTicks = holdTicks
        self.gridColumns = gridColumns
        self.flipMs = flipMs
        self.order = order
        self.reveal = reveal
    }
}

/// How a cue's clock runs: the tick length, and how many ticks it holds its
/// opening state before resolving.
public struct CueTiming: Equatable, Sendable {
    public var clockMs: Int
    public var holdTicks: Int
    /// Nothing to resolve, so no hold.
    public var isInstant: Bool
}

extension Cue {
    public func timing(defaults: ShowSettings) -> CueTiming {
        switch content {
        case .title(let c):
            let s = defaults.resolved(c.overrides)
            return CueTiming(clockMs: s.clockMs, holdTicks: s.holdTicks, isInstant: false)
        case .anagram(let c):
            let s = defaults.resolved(c.overrides)
            return CueTiming(clockMs: s.clockMs, holdTicks: s.holdTicks, isInstant: false)
        case .image(let c):
            let s = defaults.resolved(c.overrides)
            return CueTiming(clockMs: s.clockMs, holdTicks: s.holdTicks, isInstant: false)
        case .morph(let c):
            let s = defaults.resolved(c.overrides)
            return CueTiming(clockMs: s.clockMs, holdTicks: s.holdTicks, isInstant: false)
        case .video, .blank:
            // A video plays on its own clock from GO, and a blank is instant.
            return CueTiming(clockMs: defaults.clockMs, holdTicks: 0, isInstant: true)
        }
    }
}

/// The ranges the sliders allow. Values from a file are clamped to them.
public enum SettingRange {
    public static let clockMs = 18...110
    public static let waveTicks = 0...10
    public static let holdTicks = 0...80
    /// Longer than a hold: working is read, not glanced at.
    public static let pauseTicks = 0...160
    public static let textScale = 40...130
    public static let gridColumns = 4...28
    public static let flipMs = 150...1200
    public static let morphMs = 500...15000
    public static let fadeMs = 100...3000
    public static let geometrySize = 20...100
    public static let geometryOffset = -40...40
}

extension ShowSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case clockMs, waveTicks, holdTicks, histogram, sceneLine, letters, bars, gridColumns, flipMs, order
        case reveal, advance, pauseTicks, anagramFont, morphMs, transition, fadeMs, textScale, geometry, projector
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ShowSettings()
        func int(_ key: CodingKeys, _ fallback: Int, _ range: ClosedRange<Int>) throws -> Int {
            range.clamp(try c.decodeIfPresent(Int.self, forKey: key) ?? fallback)
        }
        clockMs = try int(.clockMs, d.clockMs, SettingRange.clockMs)
        waveTicks = try int(.waveTicks, d.waveTicks, SettingRange.waveTicks)
        holdTicks = try int(.holdTicks, d.holdTicks, SettingRange.holdTicks)
        histogram = try c.decodeIfPresent(Bool.self, forKey: .histogram) ?? d.histogram
        sceneLine = try c.decodeIfPresent(Bool.self, forKey: .sceneLine) ?? d.sceneLine
        letters = try c.decodeIfPresent(TitleLetters.self, forKey: .letters) ?? d.letters
        bars = try c.decodeIfPresent(TitleBars.self, forKey: .bars) ?? d.bars
        gridColumns = try int(.gridColumns, d.gridColumns, SettingRange.gridColumns)
        flipMs = try int(.flipMs, d.flipMs, SettingRange.flipMs)
        order = try c.decodeIfPresent(TileOrder.self, forKey: .order) ?? d.order
        reveal = try c.decodeIfPresent(TileReveal.self, forKey: .reveal) ?? d.reveal
        advance = try c.decodeIfPresent(AnagramAdvance.self, forKey: .advance) ?? d.advance
        pauseTicks = try int(.pauseTicks, d.pauseTicks, SettingRange.pauseTicks)
        anagramFont = try c.decodeIfPresent(String.self, forKey: .anagramFont) ?? d.anagramFont
        morphMs = try int(.morphMs, d.morphMs, SettingRange.morphMs)
        transition = try c.decodeIfPresent(TransitionStyle.self, forKey: .transition) ?? d.transition
        fadeMs = try int(.fadeMs, d.fadeMs, SettingRange.fadeMs)
        textScale = try int(.textScale, d.textScale, SettingRange.textScale)
        geometry = try c.decodeIfPresent(Geometry.self, forKey: .geometry) ?? d.geometry
        projector = try c.decodeIfPresent(DisplayIdentity.self, forKey: .projector)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clockMs, forKey: .clockMs)
        try c.encode(waveTicks, forKey: .waveTicks)
        try c.encode(holdTicks, forKey: .holdTicks)
        try c.encode(histogram, forKey: .histogram)
        try c.encode(sceneLine, forKey: .sceneLine)
        try c.encode(letters, forKey: .letters)
        try c.encode(bars, forKey: .bars)
        try c.encode(gridColumns, forKey: .gridColumns)
        try c.encode(flipMs, forKey: .flipMs)
        try c.encode(order, forKey: .order)
        try c.encode(reveal, forKey: .reveal)
        try c.encode(advance, forKey: .advance)
        try c.encode(pauseTicks, forKey: .pauseTicks)
        try c.encode(anagramFont, forKey: .anagramFont)
        try c.encode(morphMs, forKey: .morphMs)
        try c.encode(transition, forKey: .transition)
        try c.encode(fadeMs, forKey: .fadeMs)
        try c.encode(textScale, forKey: .textScale)
        try c.encode(geometry, forKey: .geometry)
        try c.encodeIfPresent(projector, forKey: .projector)
    }
}
