import Foundation

/// One cue in the sheet. The payload is an enum per kind, so a combination
/// that makes no sense, such as a key on an image cue, can't be represented.
public struct Cue: Identifiable, Equatable, Sendable {
    /// Never shown. Identity for undo, the playhead and the crash record,
    /// since numbers may be duplicated.
    public var id: UUID
    /// The number the DSM writes in the book: an identifier, not a position.
    /// `9.5` and `P12` are both valid.
    public var number: String
    /// The cue point: the spoken line or action the operator waits for.
    public var line: String
    /// What happens after this cue: GO, a timed wait, or this cue finishing.
    public var continueMode: ContinueMode
    /// The cue's own transition in, where it differs from the show's.
    public var transition: TransitionOverrides
    public var content: Content

    public enum Content: Equatable, Sendable {
        case title(TitleContent)
        case anagram(AnagramContent)
        case image(ImageContent)
        case morph(MorphContent)
        case video(VideoContent)
        case blank(BlankContent)
    }

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case title, anagram, image, morph, video, blank

        /// What the operator calls it, as it reads mid-sentence. The raw
        /// value is what show.json stores, and doesn't change with the name.
        public var name: String {
            switch self {
            case .title: "decryption"
            default: rawValue
            }
        }

        /// The name as a menu item or column heading spells it.
        public var heading: String { name.capitalized }
    }

    public init(id: UUID = UUID(), number: String = "", line: String = "", continueMode: ContinueMode = .whenCued,
                transition: TransitionOverrides = .init(), content: Content) {
        self.id = id
        self.number = number
        self.line = line
        self.continueMode = continueMode
        self.transition = transition
        self.content = content
    }

    public var kind: Kind {
        switch content {
        case .title: .title
        case .anagram: .anagram
        case .image: .image
        case .morph: .morph
        case .video: .video
        case .blank: .blank
        }
    }

    /// The text on a decryption cue, the first anagram's phrase; the label
    /// on the others.
    public var text: String {
        get {
            switch content {
            case .title(let c): c.text
            case .anagram(let c): c.anagrams.first?.text ?? ""
            case .image(let c): c.text
            case .morph(let c): c.text
            case .video(let c): c.text
            case .blank(let c): c.text
            }
        }
        set {
            switch content {
            case .title(var c): c.text = newValue; content = .title(c)
            case .anagram(var c):
                if c.anagrams.isEmpty { c.anagrams = [Anagram()] }
                c.anagrams[0].text = newValue
                content = .anagram(c)
            case .image(var c): c.text = newValue; content = .image(c)
            case .morph(var c): c.text = newValue; content = .morph(c)
            case .video(var c): c.text = newValue; content = .video(c)
            case .blank(var c): c.text = newValue; content = .blank(c)
            }
        }
    }

    /// The subtext on a decryption cue, the answer the first anagram
    /// rearranges into, the caption on a video cue. Image and blank cues have
    /// none.
    public var sub: String {
        get {
            switch content {
            case .title(let c): c.sub
            case .anagram(let c): c.anagrams.first?.answer ?? ""
            case .image, .morph: ""
            case .video(let c): c.sub
            case .blank: ""
            }
        }
        set {
            switch content {
            case .title(var c): c.sub = newValue; content = .title(c)
            case .anagram(var c):
                if c.anagrams.isEmpty { c.anagrams = [Anagram()] }
                c.anagrams[0].answer = newValue
                content = .anagram(c)
            case .image, .morph: break
            case .video(var c): c.sub = newValue; content = .video(c)
            case .blank: break
            }
        }
    }

    /// Instant cues have nothing to resolve, so they skip the hold.
    public var isInstant: Bool { kind == .blank }
}

// MARK: - Coding

// show.json keeps cues flat, with `kind` saying which fields apply, so it
// reads and repairs by hand. Decoding is lenient about anything missing.
//
// The one exception is an anagram cue with more than one anagram, or any
// working: it lists them under `anagrams`, each with its own text, working
// and answer, in place of the cue's own text and answer.
extension Cue: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, num, kind, line, continueMode = "continue", transition, text, sub, key, answer, anagrams, src, into, pairs, colour, atEnd
        case overrides
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        number = try Self.decodeNumber(c)
        line = try c.decodeIfPresent(String.self, forKey: .line) ?? ""
        continueMode = try c.decodeIfPresent(ContinueMode.self, forKey: .continueMode) ?? .whenCued
        transition = (try c.decodeIfPresent(TransitionOverrides.self, forKey: .transition) ?? .init()).clamped()

        let text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        let sub = try c.decodeIfPresent(String.self, forKey: .sub) ?? ""
        let src = try c.decodeIfPresent(String.self, forKey: .src) ?? ""

        switch try c.decode(Kind.self, forKey: .kind) {
        case .title:
            content = .title(TitleContent(
                text: text,
                sub: sub,
                key: try c.decodeIfPresent(String.self, forKey: .key) ?? "",
                overrides: (try c.decodeIfPresent(TitleOverrides.self, forKey: .overrides) ?? .init()).clamped()
            ))
        case .anagram:
            var anagrams = try c.decodeIfPresent([Anagram].self, forKey: .anagrams)
            if anagrams == nil {
                let answer = try c.decodeIfPresent(String.self, forKey: .answer) ?? ""
                anagrams = text.isEmpty && answer.isEmpty ? [] : [Anagram(text: text, answer: answer)]
            }
            content = .anagram(AnagramContent(
                anagrams: anagrams ?? [],
                overrides: (try c.decodeIfPresent(AnagramOverrides.self, forKey: .overrides) ?? .init()).clamped()
            ))
        case .image:
            content = .image(ImageContent(
                text: text,
                src: src,
                overrides: (try c.decodeIfPresent(ImageOverrides.self, forKey: .overrides) ?? .init()).clamped()
            ))
        case .morph:
            content = .morph(MorphContent(
                text: text,
                src: src,
                into: try c.decodeIfPresent(String.self, forKey: .into) ?? "",
                pairs: try c.decodeIfPresent([MorphPair].self, forKey: .pairs) ?? [],
                overrides: (try c.decodeIfPresent(MorphOverrides.self, forKey: .overrides) ?? .init()).clamped()
            ))
        case .video:
            content = .video(VideoContent(
                text: text,
                sub: sub,
                src: src,
                atEnd: try c.decodeIfPresent(VideoEnd.self, forKey: .atEnd) ?? .hold
            ))
        case .blank:
            content = .blank(BlankContent(
                text: text,
                colour: try c.decodeIfPresent(RGB.self, forKey: .colour) ?? .black
            ))
        }
    }

    /// A number typed by hand as `4` rather than `"4"` is still a number.
    private static func decodeNumber(_ c: KeyedDecodingContainer<CodingKeys>) throws -> String {
        if let s = try? c.decodeIfPresent(String.self, forKey: .num) { return s }
        if let i = try? c.decodeIfPresent(Int.self, forKey: .num) { return String(i) }
        if let d = try? c.decodeIfPresent(Double.self, forKey: .num) { return String(d) }
        return ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(number, forKey: .num)
        try c.encode(kind, forKey: .kind)
        try c.encode(line, forKey: .line)
        if continueMode != .whenCued { try c.encode(continueMode, forKey: .continueMode) }
        if !transition.isEmpty { try c.encode(transition, forKey: .transition) }
        if case .anagram(let a) = content, !a.isPlain {
            try c.encode(a.anagrams, forKey: .anagrams)
        } else {
            try c.encode(text, forKey: .text)
        }
        switch content {
        case .title(let t):
            try c.encode(t.sub, forKey: .sub)
            try c.encode(t.key, forKey: .key)
            if !t.overrides.isEmpty { try c.encode(t.overrides, forKey: .overrides) }
        case .anagram(let a):
            if a.isPlain { try c.encode(a.anagrams.first?.answer ?? "", forKey: .answer) }
            if !a.overrides.isEmpty { try c.encode(a.overrides, forKey: .overrides) }
        case .image(let i):
            try c.encode(i.src, forKey: .src)
            if !i.overrides.isEmpty { try c.encode(i.overrides, forKey: .overrides) }
        case .morph(let m):
            try c.encode(m.src, forKey: .src)
            try c.encode(m.into, forKey: .into)
            try c.encode(m.pairs, forKey: .pairs)
            if !m.overrides.isEmpty { try c.encode(m.overrides, forKey: .overrides) }
        case .video(let v):
            try c.encode(v.sub, forKey: .sub)
            try c.encode(v.src, forKey: .src)
            try c.encode(v.atEnd, forKey: .atEnd)
        case .blank(let b):
            try c.encode(b.colour, forKey: .colour)
        }
    }
}
