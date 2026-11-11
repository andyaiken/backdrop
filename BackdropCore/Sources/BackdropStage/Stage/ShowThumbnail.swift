import BackdropCore
import CoreGraphics
import Foundation
import QuartzCore

/// A show as Finder shows its file: the first cue that puts anything on
/// stage, finished, as the projector would show it.
@MainActor
public enum ShowThumbnail {
    /// The cues a thumbnail can show. A blank shows nothing, a video would
    /// need playing, and a feed a camera.
    static let kinds: Set<Cue.Kind> = [.title, .anagram, .image, .morph, .map, .layered, .keypad, .sms, .conversation, .text]

    /// The cue a show's thumbnail shows, if it has one.
    public static func cue(of show: Show) -> Cue? {
        show.cues.first { kinds.contains($0.kind) }
    }

    /// Draws the thumbnail, `width` pixels across, at the stage's shape.
    /// A picture is decoded in the background first, and waited for a few
    /// seconds at most. Nil for a show with no cue to show.
    ///
    /// - Parameter media: Where a cue's media path is on disk.
    public static func image(of show: Show, width: Int, media: @escaping (String) -> URL?) async -> CGImage? {
        guard let cue = cue(of: show) else { return nil }
        let renderers: [Cue.Kind: any CueRenderer] = [
            .title: TitleRenderer(), .anagram: AnagramRenderer(), .image: ImageRenderer(media: media),
            .morph: MorphRenderer(media: media), .map: MapRenderer(media: media), .layered: LayeredRenderer(media: media),
            .keypad: KeypadRenderer(), .sms: SMSRenderer(), .conversation: ConversationRenderer(), .text: TextRenderer(),
        ]
        let runner = StageRunner(renderers: renderers)
        runner.geometry = show.settings.geometry
        let surface = SurfaceLayer(role: .live)
        surface.contentsScale = 1
        surface.frame = CGRect(x: 0, y: 0, width: width, height: max(1, width * 9 / 16))
        surface.geometry = show.settings.geometry
        runner.attach(surface)

        if let renderer = renderers[cue.kind], loadsPictures(renderer) {
            let waiting = Waiting()
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                waiting.done = done
                setOnReady(renderer) { waiting.finish() }
                runner.redraw(cue, show: show.settings, at: 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { MainActor.assumeIsolated { waiting.finish() } }
            }
            setOnReady(renderer, nil)
        }
        // Once more, now any picture is in hand: it comes from the cache at
        // once, and the cue is drawn finished with it.
        runner.redraw(cue, show: show.settings, at: 0)
        return render(surface)
    }

    /// The whole stage on black, as the projector shows it, outside the
    /// projection area too. A new surface shows no guides.
    private static func render(_ surface: SurfaceLayer) -> CGImage? {
        let w = Int(surface.bounds.width), h = Int(surface.bounds.height)
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        func display(_ layer: CALayer) {
            layer.displayIfNeeded()
            layer.sublayers?.forEach(display)
        }
        display(surface)
        surface.renderStacked(surface, in: context)
        return context.makeImage()
    }

    /// Resumes once, whichever comes first: the picture, or the time limit.
    private final class Waiting {
        var done: CheckedContinuation<Void, Never>?

        func finish() {
            done?.resume()
            done = nil
        }
    }

    private static func loadsPictures(_ renderer: any CueRenderer) -> Bool {
        renderer is ImageRenderer || renderer is MorphRenderer || renderer is MapRenderer || renderer is LayeredRenderer
    }

    private static func setOnReady(_ renderer: any CueRenderer, _ ready: (() -> Void)?) {
        switch renderer {
        case let r as ImageRenderer: r.onReady = ready
        case let r as MorphRenderer: r.onReady = ready
        case let r as MapRenderer: r.onReady = ready
        case let r as LayeredRenderer: r.onReady = ready
        default: break
        }
    }
}
