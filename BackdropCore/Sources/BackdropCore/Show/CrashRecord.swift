import Foundation

/// The one piece of state worth recovering after a crash: which show, and
/// which cue was last fired. Written outside the document whenever a cue
/// fires, and removed on a clean quit, so finding one at launch means the
/// app went down mid-show.
public struct CrashRecord: Codable, Equatable, Sendable {
    public var show: URL
    public var cue: UUID
    public var cueNumber: String
    public var firedAt: Date

    public init(show: URL, cue: UUID, cueNumber: String, firedAt: Date) {
        self.show = show
        self.cue = cue
        self.cueNumber = cueNumber
        self.firedAt = firedAt
    }

    public static func read(from url: URL) -> CrashRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CrashRecord.self, from: data)
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
