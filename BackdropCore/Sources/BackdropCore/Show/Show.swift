import Foundation

/// A show: the cue sheet and everything that travels with it. Encoded as
/// show.json inside the `.backdrop` package.
public struct Show: Equatable, Sendable {
    /// The newest shape of show.json this reads. Bumped when show.json
    /// changes shape, so an old file can be migrated rather than misread.
    /// 2 lists an anagram cue's anagrams and working, which a version 1
    /// reader would take for an empty cue; 3 put group headings in the
    /// running list, a feature since removed; 4 lists a morph cue's
    /// pictures, for a morph of more than two; 5 has map cues; 6 gives the
    /// GOs a cue waits for cue points of their own; 7 has layered image cues. Older files read as they
    /// are.
    public static let formatVersion = 7

    /// For the window and the printed cue sheet header.
    public var title: String
    /// In running order. GO, standby and numbering go by these alone.
    public var cues: [Cue]
    public var settings: ShowSettings

    public init(title: String = "", cues: [Cue] = [], settings: ShowSettings = .init()) {
        self.title = title
        self.cues = cues
        self.settings = settings
    }

    /// The version this show is written as: the oldest that can hold it, so
    /// a show with no morph of more than two pictures stays readable by a
    /// version 2 Backdrop.
    public var version: Int {
        if cues.contains(where: { $0.kind == .keypad }) { return 8 }
        if cues.contains(where: { $0.kind == .layered }) { return 7 }
        if cues.contains(where: \.hasGoCuePoints) { return 6 }
        if cues.contains(where: { $0.kind == .map }) { return 5 }
        let staged = cues.contains { if case .morph(let m) = $0.content { !m.isPlain } else { false } }
        return staged ? 4 : 2
    }

    public func index(of id: UUID) -> Int? {
        cues.firstIndex { $0.id == id }
    }

    public subscript(id: UUID) -> Cue? {
        index(of: id).map { cues[$0] }
    }
}

public enum ShowFormatError: Error, Equatable {
    /// Written by a later version of the app. Refused rather than misread.
    case newerVersion(Int)
}

extension Show: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, title, cues, settings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Every show Backdrop writes carries its version, so a file without
        // one predates versioning altogether.
        let version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard version <= Self.formatVersion else { throw ShowFormatError.newerVersion(version) }
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        cues = try c.decodeIfPresent([Cue].self, forKey: .cues) ?? []
        settings = try c.decodeIfPresent(ShowSettings.self, forKey: .settings) ?? .init()
        // Only shows from before version 3 carry `follows`.
        if version < 3 { try migrateFollows(from: c) }
    }

    /// Shows saved before Continue marked the cue that fired by itself, with
    /// `follows`. That becomes Continue on the cue before it: when finished,
    /// or at once after a blank, which has nothing to finish. A looping clip
    /// keeps "when finished", which never comes, as a follow never did.
    private mutating func migrateFollows(from c: KeyedDecodingContainer<CodingKeys>) throws {
        struct Legacy: Decodable { let follows: Bool? }
        let legacy = try c.decodeIfPresent([Legacy].self, forKey: .cues) ?? []
        for (i, flag) in legacy.enumerated() where i > 0 && i < cues.count && flag.follows == true {
            guard cues[i - 1].continueMode == .whenCued else { continue }
            cues[i - 1].continueMode = cues[i - 1].kind == .blank ? .after(ms: 0) : .whenFinished
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(title, forKey: .title)
        try c.encode(cues, forKey: .cues)
        try c.encode(settings, forKey: .settings)
    }

    /// show.json as written to disk: pretty-printed with sorted keys, so a
    /// change diffs as a change.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public init(jsonData: Data) throws {
        self = try JSONDecoder().decode(Show.self, from: jsonData)
    }
}
