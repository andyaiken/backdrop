import Foundation

/// Files kept in the cloud rather than on the Mac. With Optimize Mac Storage
/// on, a file in iCloud Drive, which takes in Desktop and Documents, can be a
/// placeholder: the right name and size, with nothing on the disk. Reading
/// one waits for it to download, and fails after a while when the Mac is
/// offline, as a booth Mac often is. So such a file is asked for ahead, and
/// said to be what it is rather than unreadable.
public enum CloudFiles {
    /// Whether the file at `url` is a placeholder whose contents aren't on
    /// this Mac. A file on the Mac's own disk never is.
    public static func isNotDownloaded(_ url: URL) -> Bool {
        var url = url
        // Asked fresh: a download may have finished since the last answer.
        url.removeAllCachedResourceValues()
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true else { return false }
        return values.ubiquitousItemDownloadingStatus == .notDownloaded
    }

    /// Asks for the file to come down to this Mac, which it does whenever the
    /// Mac is next online.
    public static func requestDownload(_ url: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
}
