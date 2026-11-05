import Foundation

public struct TitleContent: Equatable, Sendable {
    /// The text that resolves out of the ciphertext.
    public var text: String
    /// The subtext, on the line beneath it.
    public var sub: String
    /// Drives the ciphertext. Never shown on stage or in the cue list.
    public var key: String
    public var overrides: TitleOverrides

    public init(text: String = "", sub: String = "", key: String = "", overrides: TitleOverrides = .init()) {
        self.text = text
        self.sub = sub
        self.key = key
        self.overrides = overrides
    }
}

public struct AnagramContent: Equatable, Sendable {
    /// On stage together, stacked, and solved one after another.
    public var anagrams: [Anagram]
    public var overrides: AnagramOverrides

    public init(anagrams: [Anagram] = [], overrides: AnagramOverrides = .init()) {
        self.anagrams = anagrams
        self.overrides = overrides
    }

    /// One anagram with no working, as most cues have.
    public init(text: String, answer: String, overrides: AnagramOverrides = .init()) {
        self.init(anagrams: [Anagram(text: text, answer: answer)], overrides: overrides)
    }

    /// One anagram with no working, not ignored, or none at all, which
    /// show.json keeps flat as it always has.
    var isPlain: Bool { anagrams.count < 2 && anagrams.first.map { $0.working.isEmpty && !$0.ignored } ?? true }
}

public struct ImageContent: Equatable, Sendable {
    /// The cue's name, and what the stage shows when there is no picture.
    public var text: String
    /// Relative path inside the package. Empty shows the cue's label on black.
    public var src: String
    public var overrides: ImageOverrides

    public init(text: String = "", src: String = "", overrides: ImageOverrides = .init()) {
        self.text = text
        self.src = src
        self.overrides = overrides
    }
}

public struct MorphContent: Equatable, Sendable {
    /// The cue's name, and what the stage shows for a missing picture.
    public var text: String
    /// The first picture, and the second it becomes: relative paths inside
    /// the package.
    public var src: String
    public var into: String
    /// The features matched across the two.
    public var pairs: [MorphPair]
    public var overrides: MorphOverrides

    public init(text: String = "", src: String = "", into: String = "", pairs: [MorphPair] = [], overrides: MorphOverrides = .init()) {
        self.text = text
        self.src = src
        self.into = into
        self.pairs = pairs
        self.overrides = overrides
    }
}

public struct VideoContent: Equatable, Sendable {
    public var text: String
    /// The caption.
    public var sub: String
    /// Relative path inside the package. Empty is a sheet problem.
    public var src: String
    public var atEnd: VideoEnd

    public init(text: String = "", sub: String = "", src: String = "", atEnd: VideoEnd = .hold) {
        self.text = text
        self.sub = sub
        self.src = src
        self.atEnd = atEnd
    }
}

/// What a video cue does on reaching the end of its clip. Audio is always
/// muted, so there is no setting for it.
public enum VideoEnd: String, Codable, Sendable, CaseIterable {
    /// Freeze on the last frame. The cue settles here.
    case hold
    /// Cut to black, as a blank cue. The cue settles here.
    case black
    /// Repeat until the next cue fires. The cue never settles.
    case loop
}

public struct BlankContent: Equatable, Sendable {
    public var text: String
    public var colour: RGB

    public init(text: String = "BLANK", colour: RGB = .black) {
        self.text = text
        self.colour = colour
    }
}

// MARK: - Per-cue overrides

/// A title cue's own values for settings the show holds defaults for. Nil
/// inherits the show's default.
public struct TitleOverrides: Codable, Equatable, Sendable {
    public var clockMs: Int?
    public var waveTicks: Int?
    public var holdTicks: Int?
    public var histogram: Bool?
    public var sceneLine: Bool?
    public var letters: TitleLetters?
    public var bars: TitleBars?

    public init(clockMs: Int? = nil, waveTicks: Int? = nil, holdTicks: Int? = nil, histogram: Bool? = nil, sceneLine: Bool? = nil,
                letters: TitleLetters? = nil, bars: TitleBars? = nil) {
        self.clockMs = clockMs
        self.waveTicks = waveTicks
        self.holdTicks = holdTicks
        self.histogram = histogram
        self.sceneLine = sceneLine
        self.letters = letters
        self.bars = bars
    }

    public var isEmpty: Bool { self == TitleOverrides() }

    func clamped() -> TitleOverrides {
        var o = self
        o.clockMs = clockMs.map { SettingRange.clockMs.clamp($0) }
        o.waveTicks = waveTicks.map { SettingRange.waveTicks.clamp($0) }
        o.holdTicks = holdTicks.map { SettingRange.holdTicks.clamp($0) }
        return o
    }
}

/// An anagram cue's own values for settings the show holds defaults for. Nil
/// inherits the show's default.
public struct AnagramOverrides: Codable, Equatable, Sendable {
    public var clockMs: Int?
    public var waveTicks: Int?
    public var holdTicks: Int?
    public var advance: AnagramAdvance?
    public var pauseTicks: Int?
    /// A font family's name. Empty is the stage's own type.
    public var font: String?

    public init(clockMs: Int? = nil, waveTicks: Int? = nil, holdTicks: Int? = nil, advance: AnagramAdvance? = nil, pauseTicks: Int? = nil,
                font: String? = nil) {
        self.clockMs = clockMs
        self.waveTicks = waveTicks
        self.holdTicks = holdTicks
        self.advance = advance
        self.pauseTicks = pauseTicks
        self.font = font
    }

    public var isEmpty: Bool { self == AnagramOverrides() }

    func clamped() -> AnagramOverrides {
        var o = self
        o.clockMs = clockMs.map { SettingRange.clockMs.clamp($0) }
        o.waveTicks = waveTicks.map { SettingRange.waveTicks.clamp($0) }
        o.holdTicks = holdTicks.map { SettingRange.holdTicks.clamp($0) }
        o.pauseTicks = pauseTicks.map { SettingRange.pauseTicks.clamp($0) }
        return o
    }
}

/// A morph cue's own values for settings the show holds defaults for. Nil
/// inherits the show's default.
public struct MorphOverrides: Codable, Equatable, Sendable {
    public var clockMs: Int?
    public var holdTicks: Int?
    public var morphMs: Int?

    public init(clockMs: Int? = nil, holdTicks: Int? = nil, morphMs: Int? = nil) {
        self.clockMs = clockMs
        self.holdTicks = holdTicks
        self.morphMs = morphMs
    }

    public var isEmpty: Bool { self == MorphOverrides() }

    func clamped() -> MorphOverrides {
        var o = self
        o.clockMs = clockMs.map { SettingRange.clockMs.clamp($0) }
        o.holdTicks = holdTicks.map { SettingRange.holdTicks.clamp($0) }
        o.morphMs = morphMs.map { SettingRange.morphMs.clamp($0) }
        return o
    }
}

/// An image cue's own values for settings the show holds defaults for. Nil
/// inherits the show's default.
public struct ImageOverrides: Codable, Equatable, Sendable {
    public var clockMs: Int?
    public var waveTicks: Int?
    public var holdTicks: Int?
    public var gridColumns: Int?
    public var flipMs: Int?
    public var order: TileOrder?
    public var reveal: TileReveal?

    public init(clockMs: Int? = nil, waveTicks: Int? = nil, holdTicks: Int? = nil, gridColumns: Int? = nil, flipMs: Int? = nil,
                order: TileOrder? = nil, reveal: TileReveal? = nil) {
        self.clockMs = clockMs
        self.waveTicks = waveTicks
        self.holdTicks = holdTicks
        self.gridColumns = gridColumns
        self.flipMs = flipMs
        self.order = order
        self.reveal = reveal
    }

    public var isEmpty: Bool { self == ImageOverrides() }

    func clamped() -> ImageOverrides {
        var o = self
        o.clockMs = clockMs.map { SettingRange.clockMs.clamp($0) }
        o.waveTicks = waveTicks.map { SettingRange.waveTicks.clamp($0) }
        o.holdTicks = holdTicks.map { SettingRange.holdTicks.clamp($0) }
        o.gridColumns = gridColumns.map { SettingRange.gridColumns.clamp($0) }
        o.flipMs = flipMs.map { SettingRange.flipMs.clamp($0) }
        return o
    }
}
