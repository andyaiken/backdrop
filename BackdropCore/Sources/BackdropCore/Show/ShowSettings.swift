import Foundation

/// What is set for the show as a whole. Everything a cue runs with is stored
/// on the cue itself.
public struct ShowSettings: Equatable, Sendable {
    /// Title text size, percent.
    public var textScale = 100
    public var geometry = Geometry()
    /// The display the projector window last ran on.
    public var projector: DisplayIdentity?

    public init() {}
}

extension ShowSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case textScale, geometry, projector
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ShowSettings()
        textScale = try c.value(.textScale, d.textScale, in: SettingRange.textScale)
        geometry = try c.value(.geometry, d.geometry)
        projector = try c.decodeIfPresent(DisplayIdentity.self, forKey: .projector)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(textScale, forKey: .textScale)
        try c.encode(geometry, forKey: .geometry)
        try c.encodeIfPresent(projector, forKey: .projector)
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
    public static let mapZoom = 1...8
    public static let trailSeconds = 0...30
    public static let fadeMs = 100...3000
    public static let layerMs = 200...5000
    public static let baseLevel = 0...100
    public static let contextLevel = 0...100
    public static let contextTicks = 0...80
    public static let cameraMs = 300...5000
    public static let keypadBoxes = 1...12
    public static let geometrySize = 20...100
    public static let geometryOffset = -40...40
}

extension KeyedDecodingContainer {
    /// The value under a key, or `fallback` where a hand-edited file lacks it.
    func value<T: Decodable>(_ key: Key, _ fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }

    /// A number under a key, kept inside its range.
    func value(_ key: Key, _ fallback: Int, in range: ClosedRange<Int>) throws -> Int {
        range.clamp(try decodeIfPresent(Int.self, forKey: key) ?? fallback)
    }
}

/// How a cue's clock runs: the tick length, and how many ticks it holds its
/// opening state before resolving.
public struct CueTiming: Equatable, Sendable {
    /// The clock of a cue that has none of its own: a video or a blank.
    public static let standardClockMs = 44

    public var clockMs: Int
    public var holdTicks: Int
    /// Nothing to resolve, so no hold.
    public var isInstant: Bool
}

extension Cue {
    public var timing: CueTiming {
        switch content {
        case .title(let c): CueTiming(clockMs: c.settings.clockMs, holdTicks: c.settings.holdTicks, isInstant: false)
        case .anagram(let c): CueTiming(clockMs: c.settings.clockMs, holdTicks: c.settings.holdTicks, isInstant: false)
        case .image(let c): CueTiming(clockMs: c.settings.clockMs, holdTicks: c.settings.holdTicks, isInstant: false)
        case .morph(let c): CueTiming(clockMs: c.settings.clockMs, holdTicks: c.settings.holdTicks, isInstant: false)
        case .map(let c): CueTiming(clockMs: c.settings.clockMs, holdTicks: c.settings.holdTicks, isInstant: false)
        case .layered(let c): CueTiming(clockMs: c.settings.clockMs, holdTicks: c.settings.holdTicks, isInstant: false)
        case .keypad(let c): CueTiming(clockMs: c.settings.clockMs, holdTicks: c.settings.holdTicks, isInstant: false)
        // A video plays on its own clock from GO, and a blank or a text is instant.
        case .video, .blank, .text, .feed: CueTiming(clockMs: CueTiming.standardClockMs, holdTicks: 0, isInstant: true)
        }
    }
}

// MARK: - Per-cue settings

/// A title cue's settings.
public struct TitleSettings: Codable, Equatable, Sendable {
    public var clockMs: Int
    public var waveTicks: Int
    public var holdTicks: Int
    public var histogram: Bool
    public var sceneLine: Bool
    public var letters: TitleLetters
    public var bars: TitleBars

    public init(clockMs: Int = 44, waveTicks: Int = 3, holdTicks: Int = 44, histogram: Bool = true, sceneLine: Bool = true,
                letters: TitleLetters = .cycle, bars: TitleBars = .letters) {
        self.clockMs = clockMs
        self.waveTicks = waveTicks
        self.holdTicks = holdTicks
        self.histogram = histogram
        self.sceneLine = sceneLine
        self.letters = letters
        self.bars = bars
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TitleSettings()
        clockMs = try c.value(.clockMs, d.clockMs, in: SettingRange.clockMs)
        waveTicks = try c.value(.waveTicks, d.waveTicks, in: SettingRange.waveTicks)
        holdTicks = try c.value(.holdTicks, d.holdTicks, in: SettingRange.holdTicks)
        histogram = try c.value(.histogram, d.histogram)
        sceneLine = try c.value(.sceneLine, d.sceneLine)
        letters = try c.value(.letters, d.letters)
        bars = try c.value(.bars, d.bars)
    }
}

/// An anagram cue's settings.
public struct AnagramSettings: Codable, Equatable, Sendable {
    public var clockMs: Int
    public var waveTicks: Int
    public var holdTicks: Int
    public var advance: AnagramAdvance
    public var pauseTicks: Int
    /// A font family's name. Empty is the stage's own type.
    public var font: String

    public init(clockMs: Int = 44, waveTicks: Int = 3, holdTicks: Int = 44, advance: AnagramAdvance = .byItself, pauseTicks: Int = 44,
                font: String = "") {
        self.clockMs = clockMs
        self.waveTicks = waveTicks
        self.holdTicks = holdTicks
        self.advance = advance
        self.pauseTicks = pauseTicks
        self.font = font
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AnagramSettings()
        clockMs = try c.value(.clockMs, d.clockMs, in: SettingRange.clockMs)
        waveTicks = try c.value(.waveTicks, d.waveTicks, in: SettingRange.waveTicks)
        holdTicks = try c.value(.holdTicks, d.holdTicks, in: SettingRange.holdTicks)
        advance = try c.value(.advance, d.advance)
        pauseTicks = try c.value(.pauseTicks, d.pauseTicks, in: SettingRange.pauseTicks)
        font = try c.value(.font, d.font)
    }
}

/// A morph cue's settings.
public struct MorphSettings: Codable, Equatable, Sendable {
    public var clockMs: Int
    public var holdTicks: Int
    public var morphMs: Int
    /// Either GO choice waits for GO before each stage.
    public var advance: AnagramAdvance
    /// Frames each picture rests before the next stage, when the cue moves
    /// on by itself.
    public var pauseTicks: Int

    public init(clockMs: Int = 44, holdTicks: Int = 44, morphMs: Int = 3000, advance: AnagramAdvance = .byItself, pauseTicks: Int = 44) {
        self.clockMs = clockMs
        self.holdTicks = holdTicks
        self.morphMs = morphMs
        self.advance = advance
        self.pauseTicks = pauseTicks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MorphSettings()
        clockMs = try c.value(.clockMs, d.clockMs, in: SettingRange.clockMs)
        holdTicks = try c.value(.holdTicks, d.holdTicks, in: SettingRange.holdTicks)
        morphMs = try c.value(.morphMs, d.morphMs, in: SettingRange.morphMs)
        advance = try c.value(.advance, d.advance)
        pauseTicks = try c.value(.pauseTicks, d.pauseTicks, in: SettingRange.pauseTicks)
    }

    /// Whether each stage waits for GO.
    public var eachStageOnGO: Bool { advance != .byItself }
}

/// An image cue's settings.
public struct ImageSettings: Codable, Equatable, Sendable {
    public var clockMs: Int
    public var waveTicks: Int
    public var holdTicks: Int
    public var gridColumns: Int
    public var flipMs: Int
    public var order: TileOrder
    public var reveal: TileReveal

    public init(clockMs: Int = 44, waveTicks: Int = 3, holdTicks: Int = 44, gridColumns: Int = 12, flipMs: Int = 420,
                order: TileOrder = .diagonal, reveal: TileReveal = .flip) {
        self.clockMs = clockMs
        self.waveTicks = waveTicks
        self.holdTicks = holdTicks
        self.gridColumns = gridColumns
        self.flipMs = flipMs
        self.order = order
        self.reveal = reveal
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ImageSettings()
        clockMs = try c.value(.clockMs, d.clockMs, in: SettingRange.clockMs)
        waveTicks = try c.value(.waveTicks, d.waveTicks, in: SettingRange.waveTicks)
        holdTicks = try c.value(.holdTicks, d.holdTicks, in: SettingRange.holdTicks)
        gridColumns = try c.value(.gridColumns, d.gridColumns, in: SettingRange.gridColumns)
        flipMs = try c.value(.flipMs, d.flipMs, in: SettingRange.flipMs)
        order = try c.value(.order, d.order)
        reveal = try c.value(.reveal, d.reveal)
    }
}
