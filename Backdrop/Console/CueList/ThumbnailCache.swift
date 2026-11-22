import AVFoundation
import AppKit
import BackdropCore
import BackdropStage
import os

/// Each cue's finished frame, small, for the rail and the storyboard. Drawn
/// one at a time, in the order asked, by the cue's own renderer; a clip's
/// is its first frame. A thumbnail is kept until its cue, the show's
/// settings or one of its files changes.
@MainActor
final class ThumbnailCache {
    private struct Entry {
        var cue: Cue
        var settings: ShowSettings
        var dates: [String: Date]
        var image: CGImage?
    }

    /// How wide each is drawn, in pixels: 112 for the rail's 56 × 32 points
    /// at 2×, 320 for the storyboard.
    let width: Int

    init(width: Int = 112) {
        self.width = width
    }

    /// Where a file in the show is on disk.
    var media: (String) -> URL? = { _ in nil }
    /// A thumbnail is ready, for the row showing that cue.
    var onReady: (UUID) -> Void = { _ in }

    private var entries: [UUID: Entry] = [:]
    /// Waiting to be drawn, first first.
    private var queue: [(cue: Cue, settings: ShowSettings)] = []
    private var drawing = false

    /// The thumbnail for the cue as it stands, if one has been drawn.
    func image(for cue: Cue, settings: ShowSettings) -> CGImage? {
        guard let entry = entries[cue.id], entry.cue == cue, entry.settings == settings else { return nil }
        return entry.image
    }

    /// Asks for the cues' thumbnails, those on screen first. Only what is
    /// missing or out of date is drawn again: the cue or the settings
    /// changed, or one of its files has a new modification date.
    func request(_ cues: [Cue], settings: ShowSettings, onScreen: Set<UUID>) {
        let ordered = cues.filter { onScreen.contains($0.id) } + cues.filter { !onScreen.contains($0.id) }
        let wanted = Set(cues.map(\.id))
        entries = entries.filter { wanted.contains($0.key) }
        queue = ordered.compactMap { cue in
            guard Self.draws(cue) else { return nil }
            if let entry = entries[cue.id], entry.cue == cue, entry.settings == settings, entry.dates == dates(of: cue) {
                return nil
            }
            return (cue, settings)
        }
        drawNext()
    }

    /// A feed has no picture until its camera is open; the row draws a
    /// camera instead.
    static func draws(_ cue: Cue) -> Bool { cue.kind != .feed }

    private func dates(of cue: Cue) -> [String: Date] {
        var dates: [String: Date] = [:]
        for path in cue.mediaPaths {
            guard let url = media(path),
                  let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
            dates[path] = date
        }
        return dates
    }

    private func drawNext() {
        guard !drawing, !queue.isEmpty else { return }
        drawing = true
        let (cue, settings) = queue.removeFirst()
        let dates = dates(of: cue)
        let media = self.media, width = self.width
        Task { @MainActor in
            let image: CGImage? = if case .video(let video) = cue.content {
                await Self.firstFrame(of: video.src.isEmpty ? nil : media(video.src), width: width)
            } else {
                await ShowThumbnail.image(of: cue, settings: settings, width: width, media: media)
            }
            entries[cue.id] = Entry(cue: cue, settings: settings, dates: dates, image: image)
            drawing = false
            onReady(cue.id)
            drawNext()
        }
    }

    /// Half a second into a clip, off the main actor.
    private nonisolated static func firstFrame(of url: URL?, width: Int) async -> CGImage? {
        guard let url else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: width * 2, height: width * 2)
        return try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
    }
}
