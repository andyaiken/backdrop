import Foundation

/// A show: the cue sheet and everything that travels with it. Encoded as
/// show.json inside the `.prospect` package.
public struct Show: Equatable, Sendable {
    /// Bumped when show.json changes shape, so an old file can be migrated
    /// rather than misread. 2 lists an anagram cue's anagrams and working,
    /// which a version 1 reader would take for an empty cue; version 1 files
    /// read as they are.
    public static let formatVersion = 2

    /// For the window and the printed cue sheet header.
    public var title: String
    public var cues: [Cue]
    public var settings: ShowSettings

    public init(title: String = "", cues: [Cue] = [], settings: ShowSettings = .init()) {
        self.title = title
        self.cues = cues
        self.settings = settings
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
        let version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.formatVersion
        guard version <= Self.formatVersion else { throw ShowFormatError.newerVersion(version) }
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        cues = try c.decodeIfPresent([Cue].self, forKey: .cues) ?? []
        settings = try c.decodeIfPresent(ShowSettings.self, forKey: .settings) ?? .init()
        try migrateFollows(from: c)
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
        try c.encode(Self.formatVersion, forKey: .version)
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
