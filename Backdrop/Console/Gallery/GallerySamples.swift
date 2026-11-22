import Foundation
import BackdropCore
import BackdropStage

/// The cue gallery's examples: a short cue of each kind, from the demo
/// show where it can be, timed quicker than a show would run so each loop
/// takes about four seconds. The pictures are bundled, in GallerySamples/.
enum GallerySamples {
    /// The sample of a kind. Video and live feed have no sample: the
    /// gallery shows them as pictures, so nothing opens a file or a camera.
    static func cue(for kind: Cue.Kind) -> Cue {
        func at(_ x: Double, _ y: Double) -> PicturePoint { PicturePoint(x: x, y: y) }
        var cue: Cue = switch kind {
        case .title: Cue(content: .title(TitleContent(text: "THE LAST LIGHT", key: "LANTERN")))
        case .keypad: Cue(content: .keypad(KeypadContent(text: "Safe", script: "4417\nGOOD")))
        case .anagram: Cue(content: .anagram(AnagramContent(text: "LISTEN", answer: "SILENT")))
        case .cascade: Cue(content: .cascade(CascadeContent(text: "COME HOME")))
        case .sms: Cue(content: .sms(SMSContent(text: "Where are you?", sub: "MARA")))
        case .conversation: Cue(content: .conversation(ConversationContent(sub: "MARA", script: "> Is it done?\n< Not yet.")))
        case .text: Cue(content: .text(TextContent(text: "Six weeks later")))
        case .image: Cue(content: .image(ImageContent(src: "dusk.jpg")))
        case .morph:
            // The lamp, the rock and the horizon, matched from dusk into night.
            Cue(content: .morph(MorphContent(pictures: [
                MorphPicture(src: "dusk.jpg"),
                MorphPicture(src: "night.jpg", pairs: [
                    MorphPair(from: at(0.69, 0.14), to: at(0.69, 0.16)),
                    MorphPair(from: at(0.68, 0.62), to: at(0.68, 0.62)),
                    MorphPair(from: at(0.20, 0.61), to: at(0.20, 0.61)),
                ]),
            ])))
        case .layered:
            Cue(content: .layered(LayeredContent(base: "night.jpg", layers: [
                ImageLayer(src: "storm.jpg", name: "Storm"),
                ImageLayer(src: "dusk.jpg", name: "Dusk"),
            ])))
        case .map:
            Cue(content: .map(MapContent(text: "LIVE TRACK", src: "streets.png", route: [
                RoutePoint(at: at(0.2, 0.3), stop: MapStop(status: "PARKED", place: "THE HARBOUR")),
                RoutePoint(at: at(0.5, 0.3)),
                RoutePoint(at: at(0.5, 0.6), stop: MapStop(travelMs: 1600, place: "THE LIGHTHOUSE")),
                RoutePoint(at: at(0.8, 0.75), stop: MapStop(travelMs: 1400, place: "THE COTTAGE")),
            ])))
        case .blank: Cue(content: .blank(BlankContent()))
        case .video: Cue(content: .video(VideoContent(text: "Storm")))
        case .feed: Cue(content: .feed(FeedContent()))
        }
        // Quicker than a show: a clock of 30 ms and a hold of 20.
        for (key, value) in [(SettingKey.clock, 30), (.hold, 20)] where key.applies(to: kind) {
            key.set(.number(value), in: &cue)
        }
        return cue
    }

    /// A bundled picture, by the name a sample uses.
    static func media(_ path: String) -> URL? {
        let name = (path as NSString).deletingPathExtension, ext = (path as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "GallerySamples")
    }

    /// A renderer for a kind, finding its pictures among the samples. None
    /// for video and live feed.
    @MainActor
    static func renderer(for kind: Cue.Kind) -> (any CueRenderer)? {
        switch kind {
        case .title: TitleRenderer()
        case .anagram: AnagramRenderer()
        case .image: ImageRenderer(media: media)
        case .morph: MorphRenderer(media: media)
        case .map: MapRenderer(media: media)
        case .layered: LayeredRenderer(media: media)
        case .keypad: KeypadRenderer()
        case .sms: SMSRenderer()
        case .conversation: ConversationRenderer()
        case .cascade: CascadeRenderer()
        case .text: TextRenderer()
        case .blank: BlankRenderer()
        case .video, .feed: nil
        }
    }
}
