import Foundation
import ProspectCore

/// Where the crash record lives: outside any document, in Application Support.
enum CrashRecords {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Prospect")
            .appendingPathComponent("LastCue.json")
    }

    static func write(_ record: CrashRecord) { try? record.write(to: url) }
    static func read() -> CrashRecord? { CrashRecord.read(from: url) }
    static func clear() { try? FileManager.default.removeItem(at: url) }
}
