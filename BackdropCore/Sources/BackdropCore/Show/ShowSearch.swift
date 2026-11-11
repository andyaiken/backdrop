import Foundation

extension Cue {
    /// How a cue is named away from the console, in Shortcuts and
    /// Spotlight: "Cue 12: THE LOUVRE". A cue with no words is named for its
    /// kind, and one with no number goes without.
    public var title: String {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = words.isEmpty ? "\(kind.heading) cue" : words
        let number = self.number.trimmingCharacters(in: .whitespacesAndNewlines)
        return number.isEmpty ? name : "Cue \(number): \(name)"
    }
}

extension Show {
    /// The words Spotlight finds a show by, besides its title: every cue's
    /// words, subtext and cue point, in sheet order, each once.
    public var searchableText: String {
        var seen = Set<String>()
        var words: [String] = []
        for cue in cues {
            for part in [cue.text, cue.sub, cue.line] {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
                words.append(trimmed)
            }
        }
        return words.joined(separator: "\n")
    }
}
