import Foundation

public struct TitleContent: Equatable, Sendable {
    /// The text that resolves out of the ciphertext.
    public var text: String
    /// The subtext, on the line beneath it.
    public var sub: String
    /// Drives the ciphertext. Never shown on stage or in the cue list.
    public var key: String
    public var settings: TitleSettings

    public init(text: String = "", sub: String = "", key: String = "", settings: TitleSettings = .init()) {
        self.text = text
        self.sub = sub
        self.key = key
        self.settings = settings
    }
}

public struct AnagramContent: Equatable, Sendable {
    /// On stage together, stacked, and solved one after another.
    public var anagrams: [Anagram]
    public var settings: AnagramSettings

    public init(anagrams: [Anagram] = [], settings: AnagramSettings = .init()) {
        self.anagrams = anagrams
        self.settings = settings
    }

    /// One anagram with no working, as most cues have.
    public init(text: String, answer: String, settings: AnagramSettings = .init()) {
        self.init(anagrams: [Anagram(text: text, answer: answer)], settings: settings)
    }

    /// One anagram with no working, not ignored, or none at all, which
    /// show.json keeps flat as it always has.
    var isPlain: Bool { anagrams.count < 2 && anagrams.first.map { $0.working.isEmpty && !$0.ignored && $0.cuePoints.isEmpty } ?? true }
}

public struct ImageContent: Equatable, Sendable {
    /// The cue's name, and what the stage shows when there is no picture.
    public var text: String
    /// Relative path inside the package. Empty shows the cue's label on black.
    public var src: String
    public var settings: ImageSettings

    public init(text: String = "", src: String = "", settings: ImageSettings = .init()) {
        self.text = text
        self.src = src
        self.settings = settings
    }
}

public struct MorphContent: Equatable, Sendable {
    /// The cue's name, and what the stage shows for a missing picture.
    public var text: String
    /// The pictures in turn, each becoming the next: a stage for each change.
    /// The first comes up with the cue's transition.
    public var pictures: [MorphPicture]
    public var settings: MorphSettings

    public init(text: String = "", pictures: [MorphPicture] = [], settings: MorphSettings = .init()) {
        self.text = text
        self.pictures = pictures
        self.settings = settings
    }

    /// One picture becoming another, as a morph cue first was.
    public init(text: String = "", src: String, into: String = "", pairs: [MorphPair] = [], settings: MorphSettings = .init()) {
        var pictures = [MorphPicture(src: src), MorphPicture(src: into, pairs: pairs)].filter { !$0.src.isEmpty }
        if !pictures.isEmpty { pictures[0].pairs = [] }
        self.init(text: text, pictures: pictures, settings: settings)
    }

    /// Each change from one picture to the next: stage k becomes picture k + 1.
    public var stageCount: Int { max(pictures.count - 1, 0) }

    /// Whether show.json can hold it as one picture becoming another, the
    /// shape a version 2 reader knows.
    public var isPlain: Bool {
        pictures.count <= 2 && pictures.dropFirst().allSatisfy { $0.morphMs == nil && $0.cuePoint.isEmpty }
    }

    /// Picture `from` moved to `to`, as dragging it in the list does.
    public mutating func movePicture(from: Int, to: Int) {
        guard pictures.indices.contains(from), pictures.indices.contains(to), from != to else { return }
        var order = Array(pictures.indices)
        order.insert(order.remove(at: from), at: to)
        rearrange(order)
    }

    public mutating func removePicture(at index: Int) {
        guard pictures.indices.contains(index) else { return }
        rearrange(pictures.indices.filter { $0 != index })
    }

    /// The pictures in a new order. A stage keeps its matched points only
    /// while it still joins the same two pictures: points matched from one
    /// picture mean nothing on another. Its own morph time stays with the
    /// picture it becomes.
    private mutating func rearrange(_ order: [Int]) {
        pictures = order.enumerated().map { i, old in
            var picture = pictures[old]
            if i == 0 || order[i - 1] != old - 1 { picture.pairs = [] }
            if i == 0 { picture.morphMs = nil }
            return picture
        }
    }
}

/// One of a morph cue's pictures, and the stage that becomes it.
public struct MorphPicture: Codable, Equatable, Sendable {
    /// Relative path inside the package.
    public var src: String
    /// The features matched from the picture before onto this one. The first
    /// picture has none.
    public var pairs: [MorphPair]
    /// How long the change into this picture takes, if not the cue's morph
    /// time.
    public var morphMs: Int?
    /// The cue point of the GO before the change into it, when the cue waits
    /// for one.
    public var cuePoint: String

    public init(src: String, pairs: [MorphPair] = [], morphMs: Int? = nil, cuePoint: String = "") {
        self.src = src
        self.pairs = pairs
        self.morphMs = morphMs
        self.cuePoint = cuePoint
    }

    enum CodingKeys: String, CodingKey {
        case src, pairs, morphMs, cuePoint
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        src = try c.decodeIfPresent(String.self, forKey: .src) ?? ""
        pairs = try c.decodeIfPresent([MorphPair].self, forKey: .pairs) ?? []
        morphMs = try c.decodeIfPresent(Int.self, forKey: .morphMs).map { SettingRange.morphMs.clamp($0) }
        cuePoint = try c.decodeIfPresent(String.self, forKey: .cuePoint) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(src, forKey: .src)
        if !pairs.isEmpty { try c.encode(pairs, forKey: .pairs) }
        try c.encodeIfPresent(morphMs, forKey: .morphMs)
        if !cuePoint.isEmpty { try c.encode(cuePoint, forKey: .cuePoint) }
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

/// How a text cue's lines sit across the picture.
public enum TextAlign: String, Codable, Sendable, CaseIterable {
    case left, centre, right

    public var name: String { rawValue.capitalized }
}

/// Where a text cue's block of words sits down the picture.
public enum TextVertical: String, Codable, Sendable, CaseIterable {
    case top, middle, bottom

    public var name: String { rawValue.capitalized }
}

/// A text cue: some words, set in a font and colour, aligned across the
/// picture. Instant, like a blank.
public struct TextContent: Equatable, Sendable {
    public var text: String
    /// A font family, or empty for the stage font.
    public var font: String
    public var colour: RGB
    public var alignment: TextAlign
    public var vertical: TextVertical
    /// What fills the picture behind the words.
    public var background: RGB

    public init(text: String = "", font: String = "", colour: RGB = RGB(255, 255, 255), alignment: TextAlign = .centre,
                vertical: TextVertical = .middle, background: RGB = .black) {
        self.text = text
        self.font = font
        self.colour = colour
        self.alignment = alignment
        self.vertical = vertical
        self.background = background
    }
}

public struct BlankContent: Equatable, Sendable {
    public var colour: RGB

    public init(colour: RGB = .black) {
        self.colour = colour
    }
}

