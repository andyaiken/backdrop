import Foundation

/// A cascade cue: columns of glyphs raining down the picture, each streak a
/// bright head with a fading tail, as a screen of code does in the films.
///
/// With a message, the rain stops and clears, and a fast streak comes down
/// each column the message stands in, leaving its letters behind as it
/// passes; then the cue settles on the message alone. With none, the rain
/// runs until the next cue replaces it, as a looping clip does.
public struct CascadeContent: Equatable, Sendable {
    /// The message the rain resolves into, a line to a line. Empty is rain
    /// alone.
    public var text: String
    /// What the rain is drawn in. Each head is near white.
    public var colour: RGB
    /// The cue point of the GO the message waits for, when it waits for one.
    public var goLine: String
    public var settings: CascadeSettings

    /// Phosphor green, as the films have it.
    public static let green = RGB(0x00, 0xFF, 0x41)

    public init(text: String = "", colour: RGB = CascadeContent.green, goLine: String = "", settings: CascadeSettings = .init()) {
        self.text = text
        self.colour = colour
        self.goLine = goLine
        self.settings = settings
    }

    /// What the rain falls in: the half-width katakana, then the digits.
    /// The katakana are sometimes drawn mirrored; the digits never.
    public static let glyphs: [Character] = (0xFF66...0xFF9D).compactMap { UnicodeScalar($0).map(Character.init) } + Array("0123456789")
    /// How many of `glyphs` are katakana, and so may be mirrored.
    public static let katakanaCount = 56

    /// The message's lines as the stage sets them: blank lines at either end
    /// dropped, and the spaces at the end of each.
    public var lines: [String] {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { line in
            String(line.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
        }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }

    /// Whether the rain resolves into anything. Without a message it never
    /// settles.
    public var hasMessage: Bool { lines.contains { $0.contains { !$0.isWhitespace } } }

    /// The message on one line, for the cue list, the sheet and a GO's row.
    public var summary: String { lines.filter { !$0.isEmpty }.joined(separator: " / ") }

    /// Where the cue waits for GO: once, before the message, when it waits.
    public func goPoints() -> [GoPoint] {
        guard hasMessage, settings.messageOnGO else { return [] }
        return [GoPoint(unit: .message, text: summary, cuePoint: goLine)]
    }
}

/// A cascade cue's settings.
public struct CascadeSettings: Codable, Equatable, Sendable {
    /// How long a step takes: a quick streak falls a glyph a step.
    public var clockMs: Int
    /// Steps of rain before the message starts to come out of it, when it
    /// comes by itself.
    public var holdTicks: Int
    /// Either GO choice waits for GO before the message.
    public var advance: AnagramAdvance
    /// Glyphs across the picture. A long message takes more.
    public var columns: Int
    /// How much of the time a column has a streak falling in it, as a
    /// percentage.
    public var density: Int
    /// How many glyphs long a streak is, on average.
    public var streak: Int

    public init(clockMs: Int = 44, holdTicks: Int = 60, advance: AnagramAdvance = .byItself, columns: Int = 48, density: Int = 60,
                streak: Int = 14) {
        self.clockMs = SettingRange.clockMs.clamp(clockMs)
        self.holdTicks = SettingRange.holdTicks.clamp(holdTicks)
        self.advance = advance
        self.columns = SettingRange.cascadeColumns.clamp(columns)
        self.density = SettingRange.cascadeDensity.clamp(density)
        self.streak = SettingRange.cascadeStreak.clamp(streak)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CascadeSettings()
        clockMs = try c.value(.clockMs, d.clockMs, in: SettingRange.clockMs)
        holdTicks = try c.value(.holdTicks, d.holdTicks, in: SettingRange.holdTicks)
        // A hand-edited value that isn't one of the choices is the default.
        advance = (try? c.decodeIfPresent(AnagramAdvance.self, forKey: .advance)) ?? d.advance
        columns = try c.value(.columns, d.columns, in: SettingRange.cascadeColumns)
        density = try c.value(.density, d.density, in: SettingRange.cascadeDensity)
        streak = try c.value(.streak, d.streak, in: SettingRange.cascadeStreak)
    }

    /// Whether the message waits for GO.
    public var messageOnGO: Bool { advance != .byItself }
}
