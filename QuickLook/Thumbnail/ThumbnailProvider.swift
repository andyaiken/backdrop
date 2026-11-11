import AppKit
import BackdropCore
import BackdropStage
import QuickLookThumbnailing

/// What Finder shows for a show's file: its first cue that puts anything on
/// stage, finished, as the projector would show it.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, (any Error)?) -> Void) {
        let url = request.fileURL, maximum = request.maximumSize, scale = request.scale
        let reply = Reply(handler)
        // The stage draws on the main thread, as it does in the app.
        Task { @MainActor in
            reply.send(await Self.thumbnail(of: url, within: maximum, scale: scale))
        }
    }

    /// The stage's shape, as large as fits; nil for a show that can't be
    /// read, or has nothing to show, which leaves Finder its usual icon.
    @MainActor
    private static func thumbnail(of url: URL, within maximum: CGSize, scale: CGFloat) async -> QLThumbnailReply? {
        guard let package = try? FileWrapper(url: url, options: []),
              let show = try? ShowPackage.read(package) else { return nil }
        let size = maximum.width * 9 / 16 <= maximum.height
            ? CGSize(width: maximum.width, height: (maximum.width * 9 / 16).rounded())
            : CGSize(width: (maximum.height * 16 / 9).rounded(), height: maximum.height)
        let width = Int((size.width * scale).rounded())
        guard let image = await ShowThumbnail.image(of: show, width: width, media: { url.appendingPathComponent($0) }) else {
            return nil
        }
        // Quick Look draws on a thread of its own. Left to inference, this
        // would be taken as the main actor's, like the code around it, and
        // trap when called anywhere else; it only draws a finished image.
        return QLThumbnailReply(contextSize: size) { @Sendable context in
            // The whole of the context, however Quick Look has scaled it:
            // it comes in pixels, not the points `size` is in.
            context.draw(image, in: context.boundingBoxOfClipPath)
            return true
        }
    }
}

/// Quick Look's completion handler, carried to the main actor and back.
private final class Reply: @unchecked Sendable {
    private let handler: (QLThumbnailReply?, (any Error)?) -> Void

    init(_ handler: @escaping (QLThumbnailReply?, (any Error)?) -> Void) {
        self.handler = handler
    }

    func send(_ reply: QLThumbnailReply?) {
        handler(reply, reply == nil ? CocoaError(.fileReadCorruptFile) : nil)
    }
}
