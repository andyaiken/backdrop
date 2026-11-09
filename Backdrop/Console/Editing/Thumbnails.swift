import AppKit
import ImageIO

/// Small pictures for the strip, made off the main thread once a path is
/// first shown, and kept.
@MainActor
final class Thumbnails: ObservableObject {
    @Published private var images: [String: NSImage] = [:]
    private var asked: Set<String> = []
    var mediaURL: (String) -> URL? = { _ in nil }

    func image(_ path: String) -> NSImage? {
        if let image = images[path] { return image }
        guard !path.isEmpty, !asked.contains(path), let url = mediaURL(path) else { return nil }
        asked.insert(path)
        Task.detached(priority: .utility) {
            let made = Self.make(url)
            await MainActor.run { [weak self] in
                if let made { self?.images[path] = NSImage(cgImage: made, size: .zero) }
            }
        }
        return nil
    }

    nonisolated private static func make(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 240,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
