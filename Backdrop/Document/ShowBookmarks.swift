import Foundation

/// Where shows are, kept so Backdrop can open them again by itself: the last
/// show at launch, the show that was running when Backdrop stopped, and a
/// show chosen in Spotlight.
///
/// Sandboxed, Backdrop may only open a file the operator chose. A
/// security-scoped bookmark, made while the show is open, is how it keeps
/// that permission for next time. It follows the show if it is moved or
/// renamed, and fails to resolve once the show is gone.
@MainActor
enum ShowBookmarks {
    /// The bookmarks, most recent first, each with the path it was made for.
    private static let key = "ShowBookmarks"
    /// Enough for every show a production might touch.
    private static let most = 40

    private static var stored: [[String: Any]] {
        get { UserDefaults.standard.array(forKey: key) as? [[String: Any]] ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Shows opened since launch, whose permission is in use: started once,
    /// and kept for as long as Backdrop runs.
    private static var opened: [String: URL] = [:]

    /// Remembers a show the operator has open, first in line. Call while it
    /// is open, when Backdrop has permission to it.
    static func remember(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return
        }
        var entries = stored.filter { ($0["path"] as? String) != path }
        entries.insert(["path": path, "bookmark": bookmark], at: 0)
        stored = Array(entries.prefix(most))
    }

    /// The shows remembered, most recent first: those still there, where
    /// they are now.
    static func known() -> [URL] {
        var seen = Set<String>()
        return stored.compactMap { entry in
            guard let bookmark = entry["bookmark"] as? Data, let url = resolve(bookmark) else { return nil }
            return seen.insert(url.standardizedFileURL.path).inserted ? url : nil
        }
    }

    /// Opens the way to a remembered show, by where it was or where it is
    /// now, and says where it is. Nil when it isn't remembered or has gone.
    static func access(_ url: URL) -> URL? {
        let path = url.standardizedFileURL.path
        if let open = opened[path] { return open }
        for entry in stored {
            guard let bookmark = entry["bookmark"] as? Data, let found = resolve(bookmark) else { continue }
            guard entry["path"] as? String == path || found.standardizedFileURL.path == path else { continue }
            _ = found.startAccessingSecurityScopedResource()
            opened[path] = found
            opened[found.standardizedFileURL.path] = found
            return found
        }
        return nil
    }

    private static func resolve(_ bookmark: Data) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
    }
}
