import Foundation

/// One anagram on an anagram cue: the phrase that appears, any working, and
/// the answer its letters rearrange into.
public struct Anagram: Equatable, Sendable {
    /// The phrase as it first appears.
    public var text: String
    /// Steps on the way to the answer, as someone working it out might try
    /// them: partial, or wrong. Only the phrase and the answer have to be an
    /// anagram of each other.
    public var working: [String]
    /// The phrase its letters rearrange into.
    public var answer: String
    /// Left as it stands, its phrase jumbled, and skipped when the cue
    /// solves its anagrams.
    public var ignored: Bool
    /// The cue point of each GO it waits for, by the step that GO moves to:
    /// so a GO keeps its cue point whether the cue waits before each step or
    /// only before each anagram, which waits before its first move.
    public var cuePoints: [String: String]

    public init(text: String = "", working: [String] = [], answer: String = "", ignored: Bool = false, cuePoints: [String: String] = [:]) {
        self.text = text
        self.working = working
        self.answer = answer
        self.ignored = ignored
        self.cuePoints = cuePoints
    }

    /// What it shows, in order: the phrase, the working, then the answer.
    /// Blank ones are left out.
    public var steps: [String] {
        ([text] + working + [answer]).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// One line and nothing to move to: solved already, and shown solved.
    public var isSolvedAlready: Bool { steps.count == 1 }

    /// Whether the cue solves it on stage. One that is ignored, or solved
    /// already, stands still from the start and takes no turn.
    public var isSolvedOnStage: Bool { !ignored && steps.count > 1 }

    // MARK: The Cue tab's text box

    /// What starts the first line of an ignored anagram's paragraph.
    public static let ignoreMark: Character = "~"

    /// The anagrams as the Cue tab writes them: a paragraph each, the phrase
    /// on its first line, the answer on its last and any working between,
    /// with a blank line before the next. An ignored one starts with `~`.
    public static func paragraphs(_ anagrams: [Anagram]) -> String {
        anagrams.map { a in
            let lines = [a.text] + a.working + (a.answer.isEmpty ? [] : [a.answer])
            return (a.ignored ? "\(ignoreMark) " : "") + lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    /// The text box read back. A paragraph of one line is an anagram solved
    /// already.
    public static func anagrams(fromParagraphs text: String) -> [Anagram] {
        var anagrams: [Anagram] = [], lines: [String] = []
        func finish() {
            guard var first = lines.first else { return }
            let ignored = first.first == ignoreMark
            if ignored { first = first.dropFirst().trimmingCharacters(in: .whitespaces) }
            anagrams.append(Anagram(text: first, working: Array(lines.dropFirst().dropLast()), answer: lines.count > 1 ? lines[lines.count - 1] : "",
                                    ignored: ignored))
            lines = []
        }
        // A Character's newline test takes \r\n as one break, not two.
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { finish() } else { lines.append(trimmed) }
        }
        finish()
        return anagrams
    }

    /// Anagrams read back from the text box, keeping the cue points the old
    /// ones had for steps still there: first the same anagram's, then any.
    public static func carryingCuePoints(from old: [Anagram], into new: [Anagram]) -> [Anagram] {
        let any = old.reduce(into: [String: String]()) { all, a in all.merge(a.cuePoints) { first, _ in first } }
        return new.enumerated().map { i, anagram in
            var anagram = anagram
            let own = old.indices.contains(i) ? old[i].cuePoints : [:]
            for step in anagram.steps.dropFirst() {
                if let line = own[step] ?? any[step] { anagram.cuePoints[step] = line }
            }
            return anagram
        }
    }
}

/// In show.json, each anagram is `{"text": …, "working": […], "answer": …}`,
/// with no working key when there is none, and `"ignored": true` only on one
/// that is.
extension Anagram: Codable {
    private enum CodingKeys: String, CodingKey {
        case text, working, answer, ignored, cuePoints
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        working = try c.decodeIfPresent([String].self, forKey: .working) ?? []
        answer = try c.decodeIfPresent(String.self, forKey: .answer) ?? ""
        ignored = try c.decodeIfPresent(Bool.self, forKey: .ignored) ?? false
        cuePoints = try c.decodeIfPresent([String: String].self, forKey: .cuePoints) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        if !working.isEmpty { try c.encode(working, forKey: .working) }
        try c.encode(answer, forKey: .answer)
        if ignored { try c.encode(true, forKey: .ignored) }
        if !cuePoints.isEmpty { try c.encode(cuePoints, forKey: .cuePoints) }
    }
}

/// How an anagram cue moves on from each step to the next.
public enum AnagramAdvance: String, Codable, Sendable, CaseIterable {
    /// Each step follows a pause after the one before lands, and each
    /// anagram a pause after the one before is solved.
    case byItself = "itself"
    /// Each anagram waits for GO, the first included; its working then runs
    /// on by itself.
    case eachAnagram = "anagram"
    /// Every step waits for GO, the first included.
    case eachStep = "step"
}

extension AnagramContent {
    /// Where the cue waits for GO, in order. None when it moves on by itself.
    /// An anagram the cue doesn't solve has no turn to wait for.
    public func goPoints(_ advance: AnagramAdvance) -> [GoPoint] {
        let solved = anagrams.filter(\.isSolvedOnStage)
        return switch advance {
        case .byItself: []
        case .eachAnagram: solved.map { GoPoint(unit: .anagram, text: $0.steps[0], cuePoint: $0.cuePoints[$0.steps[1]] ?? "") }
        case .eachStep: solved.flatMap { a in a.steps.dropFirst().map { GoPoint(unit: .step, text: $0, cuePoint: a.cuePoints[$0] ?? "") } }
        }
    }
}
