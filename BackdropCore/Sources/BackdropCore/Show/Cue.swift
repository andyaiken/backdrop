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
    /// How the stage changes to this cue.
    public var transition: Transition
    public var content: Content

    public enum Content: Equatable, Sendable {
        case title(TitleContent)
        case anagram(AnagramContent)
        case image(ImageContent)
        case text(TextContent)
        case morph(MorphContent)
        case map(MapContent)
        case video(VideoContent)
        case feed(FeedContent)
        case blank(BlankContent)
        case layered(LayeredContent)
        case keypad(KeypadContent)
        case sms(SMSContent)
        case conversation(ConversationContent)
        case cascade(CascadeContent)
    }

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case title, anagram, image, text, morph, map, video, feed, blank, layered, keypad, sms, conversation, cascade

        /// What the operator calls it, as it reads mid-sentence. The raw
        /// value is what show.json stores, and doesn't change with the name.
        public var name: String {
            switch self {
            case .title: "decryption"
            case .layered: "layered image"
            case .feed: "live feed"
            case .sms: "text message"
            case .conversation: "text conversation"
            default: rawValue
            }
        }

        /// The name as a menu item or column heading spells it.
        public var heading: String { name.capitalized }

        /// The SF Symbol that stands for this kind, in the cue list and the
        /// Add Cue menus. A name only, so the model needs no AppKit.
        public var symbol: String {
            switch self {
            // A cryptex dial coming open, which is what the letters do.
            case .title: "lock.open.rotation"
            case .anagram: "shuffle"
            case .image: "photo"
            case .text: "textformat"
            case .morph: "rectangle.2.swap"
            case .map: "map"
            case .video: "film"
            case .feed: "video"
            case .blank: "rectangle.slash"
            case .layered: "square.3.layers.3d"
            case .keypad: "circle.grid.3x3"
            case .sms: "message"
            case .conversation: "bubble.left.and.bubble.right"
            // Streaks falling, which is what the glyphs do.
            case .cascade: "chevron.down.dotted.2"
            }
        }

        /// One line on what the cue does, for the Add Cue popover.
        public var blurb: String {
            switch self {
            case .title: "Letters scramble and resolve into a line of text."
            case .anagram: "Shows a phrase, then rearranges its letters into another."
            case .image: "Shows a picture, fitted to the projection area."
            case .text: "Shows words in a font and colour you choose."
            case .morph: "Dissolves one image or text into another."
            case .map: "Draws a route across a map."
            case .video: "Plays a video file."
            case .feed: "Shows a live camera picture."
            case .blank: "Clears the screen to a solid colour."
            case .layered: "Stacks several images into one composed picture."
            case .keypad: "Keys numbers into boxes on a numpad, a stage on each GO, then flashes green or red."
            case .sms: "Pops a text message bubble onto the screen, with a from line."
            case .conversation: "A whole text exchange, with typing dots, each message released on GO."
            case .cascade: "Glyphs rain down the screen in streaks, then clear to leave a message."
            }
        }

        /// Other words the Add Cue sheet finds this kind by, which its name
        /// and blurb don't say: what the effect is called elsewhere, or what
        /// it's used to show.
        public var keywords: [String] {
            switch self {
            case .title: ["cipher", "code", "cryptex", "decode", "decipher", "hacker", "password", "reveal", "unlock"]
            case .anagram: ["jumble", "puzzle", "scramble", "shuffle", "unscramble", "word"]
            case .image: ["backdrop", "background", "graphic", "jpeg", "jpg", "photograph", "png", "scenery", "slide", "still"]
            case .text: ["caption", "color", "lettering", "signage", "subtitle", "surtitle", "title", "typeface", "typography"]
            case .morph: ["blend", "crossfade", "fade", "mix", "transform"]
            case .map: ["directions", "flight", "gps", "journey", "location", "path", "travel", "trip"]
            case .video: ["animation", "clip", "film", "footage", "movie", "mp4", "playback"]
            case .feed: ["capture", "relay", "stream", "video", "webcam"]
            case .blank: ["black", "blackout", "color", "empty", "nothing", "off"]
            case .layered: ["collage", "composite", "montage", "overlay"]
            case .keypad: ["access", "code", "combination", "door", "entry", "keycode", "lock", "passcode", "password", "pin", "safe", "security"]
            case .sms: ["cellphone", "chat", "mobile", "notification", "phone", "sms", "smartphone"]
            case .conversation: ["cellphone", "chat", "dialogue", "message", "mobile", "phone", "sms", "smartphone", "thread"]
            case .cascade: ["code", "computer", "digital", "falling", "hacker", "matrix", "terminal"]
            }
        }

        /// The kinds a show uses most, which the Add Cue menus list first.
        public static let common: [Kind] = [.image, .text, .video]
        /// The rest, after a separator, by the name they show.
        public static let others: [Kind] = [.anagram, .blank, .cascade, .title, .keypad, .layered, .feed, .map, .morph, .conversation, .sms]

        /// The kinds the Add Cue sheet lists for a search, best first. Every
        /// word searched for must begin a word of the kind's name, keywords or
        /// blurb, and a plural finds the singular. A kind the search names
        /// comes before one it only describes; otherwise the menus' order holds.
        public static func matching(_ query: String) -> [Kind] {
            let all = common + others
            let terms = words(in: query).map { $0.count > 3 && $0.hasSuffix("s") ? String($0.dropLast()) : $0 }
            guard !terms.isEmpty else { return all }
            let ranked = all.enumerated().compactMap { index, kind -> (rank: Int, index: Int, kind: Kind)? in
                // Best first: what it's called (here or in show.json), then its keywords, then its blurb.
                let tiers = [words(in: kind.name + " " + kind.rawValue), kind.keywords.flatMap(words(in:)), words(in: kind.blurb)]
                var rank = 0
                for term in terms {
                    guard let tier = tiers.firstIndex(where: { $0.contains { $0.hasPrefix(term) } }) else { return nil }
                    rank += tier
                }
                return (rank, index, kind)
            }
            return ranked.sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }.map(\.kind)
        }

        private static func words(in text: String) -> [String] {
            text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }
    }

    public init(id: UUID = UUID(), number: String = "", line: String = "", continueMode: ContinueMode = .whenCued,
                transition: Transition = .standard, content: Content) {
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
        case .text: .text
        case .morph: .morph
        case .map: .map
        case .video: .video
        case .feed: .feed
        case .blank: .blank
        case .layered: .layered
        case .keypad: .keypad
        case .sms: .sms
        case .conversation: .conversation
        case .cascade: .cascade
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
            case .text(let c): c.text
            case .morph(let c): c.text
            case .map(let c): c.text
            case .video(let c): c.text
            case .feed(let c): c.text
            case .blank: ""
            case .layered(let c): c.text
            case .keypad(let c): c.text
            case .sms(let c): c.text
            case .conversation(let c): c.text
            case .cascade(let c): c.text
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
            case .text(var c): c.text = newValue; content = .text(c)
            case .morph(var c): c.text = newValue; content = .morph(c)
            case .map(var c): c.text = newValue; content = .map(c)
            case .video(var c): c.text = newValue; content = .video(c)
            case .feed(var c): c.text = newValue; content = .feed(c)
            case .blank: break
            case .layered(var c): c.text = newValue; content = .layered(c)
            case .keypad(var c): c.text = newValue; content = .keypad(c)
            case .sms(var c): c.text = newValue; content = .sms(c)
            case .conversation(var c): c.text = newValue; content = .conversation(c)
            case .cascade(var c): c.text = newValue; content = .cascade(c)
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
            case .image, .text, .morph, .map, .layered, .keypad, .cascade: ""
            case .video(let c): c.sub
            case .feed(let c): c.sub
            case .sms(let c): c.sub
            case .conversation(let c): c.sub
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
            case .image, .text, .morph, .map, .layered, .keypad, .cascade: break
            case .video(var c): c.sub = newValue; content = .video(c)
            case .feed(var c): c.sub = newValue; content = .feed(c)
            case .sms(var c): c.sub = newValue; content = .sms(c)
            case .conversation(var c): c.sub = newValue; content = .conversation(c)
            case .blank: break
            }
        }
    }

    /// Instant cues have nothing to resolve, so they skip the hold.
    public var isInstant: Bool { kind == .blank || kind == .text }
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
        case id, num, kind, line, continueMode = "continue", transition, text, sub, key, answer, anagrams, script, src, into, pairs, pictures, route, reference, colour, atEnd, font, align, valign, background, goLine
        case settings, layers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        number = try Self.decodeNumber(c)
        line = try c.decodeIfPresent(String.self, forKey: .line) ?? ""
        continueMode = try c.decodeIfPresent(ContinueMode.self, forKey: .continueMode) ?? .whenCued
        transition = try c.value(.transition, Transition.standard)

        let text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        let sub = try c.decodeIfPresent(String.self, forKey: .sub) ?? ""
        let src = try c.decodeIfPresent(String.self, forKey: .src) ?? ""

        switch try c.decode(Kind.self, forKey: .kind) {
        case .title:
            content = .title(TitleContent(
                text: text,
                sub: sub,
                key: try c.decodeIfPresent(String.self, forKey: .key) ?? "",
                settings: try c.value(.settings, TitleSettings())
            ))
        case .anagram:
            var anagrams = try c.decodeIfPresent([Anagram].self, forKey: .anagrams)
            if anagrams == nil {
                let answer = try c.decodeIfPresent(String.self, forKey: .answer) ?? ""
                anagrams = text.isEmpty && answer.isEmpty ? [] : [Anagram(text: text, answer: answer)]
            }
            content = .anagram(AnagramContent(
                anagrams: anagrams ?? [],
                settings: try c.value(.settings, AnagramSettings())
            ))
        case .image:
            content = .image(ImageContent(
                text: text,
                src: src,
                settings: try c.value(.settings, ImageSettings())
            ))
        case .text:
            content = .text(TextContent(
                text: text,
                font: try c.decodeIfPresent(String.self, forKey: .font) ?? "",
                colour: try c.decodeIfPresent(RGB.self, forKey: .colour) ?? RGB(255, 255, 255),
                alignment: try c.decodeIfPresent(TextAlign.self, forKey: .align) ?? .centre,
                vertical: try c.decodeIfPresent(TextVertical.self, forKey: .valign) ?? .middle,
                background: try c.decodeIfPresent(RGB.self, forKey: .background) ?? .black
            ))
        case .morph:
            let settings = try c.value(.settings, MorphSettings())
            if var pictures = try c.decodeIfPresent([MorphPicture].self, forKey: .pictures) {
                if !pictures.isEmpty { pictures[0].pairs = []; pictures[0].morphMs = nil }
                content = .morph(MorphContent(text: text, pictures: pictures, settings: settings))
            } else {
                content = .morph(MorphContent(
                    text: text,
                    src: src,
                    into: try c.decodeIfPresent(String.self, forKey: .into) ?? "",
                    pairs: try c.decodeIfPresent([MorphPair].self, forKey: .pairs) ?? [],
                    settings: settings
                ))
            }
        case .map:
            content = .map(MapContent(
                text: text,
                src: src,
                route: try c.decodeIfPresent([RoutePoint].self, forKey: .route) ?? [],
                reference: try c.decodeIfPresent(MapReference.self, forKey: .reference),
                settings: try c.value(.settings, MapSettings())
            ))
        case .video:
            content = .video(VideoContent(
                text: text,
                sub: sub,
                src: src,
                atEnd: try c.decodeIfPresent(VideoEnd.self, forKey: .atEnd) ?? .hold
            ))
        case .feed:
            content = .feed(FeedContent(
                text: text,
                sub: sub,
                settings: try c.value(.settings, FeedSettings())
            ))
        case .layered:
            content = .layered(LayeredContent(
                text: text,
                base: src,
                layers: try c.decodeIfPresent([ImageLayer].self, forKey: .layers) ?? [],
                settings: try c.value(.settings, LayeredSettings())
            ))
        case .keypad:
            content = .keypad(KeypadContent(
                text: text,
                script: try c.decodeIfPresent(String.self, forKey: .script) ?? "",
                settings: try c.value(.settings, KeypadSettings())
            ))
        case .sms:
            content = .sms(SMSContent(
                text: text,
                sub: sub,
                settings: try c.value(.settings, SMSSettings())
            ))
        case .conversation:
            content = .conversation(ConversationContent(
                text: text,
                sub: sub,
                script: try c.decodeIfPresent(String.self, forKey: .script) ?? "",
                settings: try c.value(.settings, ConversationSettings())
            ))
        case .cascade:
            content = .cascade(CascadeContent(
                text: text,
                colour: try c.decodeIfPresent(RGB.self, forKey: .colour) ?? CascadeContent.green,
                goLine: try c.decodeIfPresent(String.self, forKey: .goLine) ?? "",
                settings: try c.value(.settings, CascadeSettings())
            ))
        case .blank:
            content = .blank(BlankContent(
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
        try c.encode(transition, forKey: .transition)
        if case .anagram(let a) = content, !a.isPlain {
            try c.encode(a.anagrams, forKey: .anagrams)
        } else if kind != .blank {
            try c.encode(text, forKey: .text)
        }
        switch content {
        case .title(let t):
            try c.encode(t.sub, forKey: .sub)
            try c.encode(t.key, forKey: .key)
            try c.encode(t.settings, forKey: .settings)
        case .anagram(let a):
            if a.isPlain { try c.encode(a.anagrams.first?.answer ?? "", forKey: .answer) }
            try c.encode(a.settings, forKey: .settings)
        case .image(let i):
            try c.encode(i.src, forKey: .src)
            try c.encode(i.settings, forKey: .settings)
        case .text(let t):
            try c.encode(t.font, forKey: .font)
            try c.encode(t.colour, forKey: .colour)
            try c.encode(t.alignment, forKey: .align)
            try c.encode(t.vertical, forKey: .valign)
            try c.encode(t.background, forKey: .background)
        case .morph(let m):
            if m.isPlain {
                try c.encode(m.pictures.first?.src ?? "", forKey: .src)
                try c.encode(m.pictures.count > 1 ? m.pictures[1].src : "", forKey: .into)
                try c.encode(m.pictures.count > 1 ? m.pictures[1].pairs : [], forKey: .pairs)
            } else {
                try c.encode(m.pictures, forKey: .pictures)
            }
            try c.encode(m.settings, forKey: .settings)
        case .map(let m):
            try c.encode(m.src, forKey: .src)
            try c.encode(m.route, forKey: .route)
            try c.encodeIfPresent(m.reference, forKey: .reference)
            try c.encode(m.settings, forKey: .settings)
        case .video(let v):
            try c.encode(v.sub, forKey: .sub)
            try c.encode(v.src, forKey: .src)
            try c.encode(v.atEnd, forKey: .atEnd)
        case .feed(let f):
            try c.encode(f.sub, forKey: .sub)
            try c.encode(f.settings, forKey: .settings)
        case .layered(let l):
            try c.encode(l.base, forKey: .src)
            try c.encode(l.layers, forKey: .layers)
            try c.encode(l.settings, forKey: .settings)
        case .keypad(let k):
            try c.encode(k.script, forKey: .script)
            try c.encode(k.settings, forKey: .settings)
        case .sms(let m):
            try c.encode(m.sub, forKey: .sub)
            try c.encode(m.settings, forKey: .settings)
        case .conversation(let m):
            try c.encode(m.sub, forKey: .sub)
            try c.encode(m.script, forKey: .script)
            try c.encode(m.settings, forKey: .settings)
        case .cascade(let m):
            try c.encode(m.colour, forKey: .colour)
            if !m.goLine.isEmpty { try c.encode(m.goLine, forKey: .goLine) }
            try c.encode(m.settings, forKey: .settings)
        case .blank(let b):
            try c.encode(b.colour, forKey: .colour)
        }
    }
}
