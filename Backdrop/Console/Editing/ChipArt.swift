import AppKit
import BackdropCore
import BackdropStage
import QuartzCore

/// The pictures on the Inspector's look chips: each option drawn by the
/// kind's own renderer, on the gallery's sample cue with only that option
/// changed, caught at a frame that shows the difference. Drawn once per
/// launch, in the background, and kept.
@MainActor
final class ChipArt: ObservableObject {
    static let shared = ChipArt()
    static let size = CGSize(width: 156, height: 52)

    @Published private(set) var images: [String: CGImage] = [:]
    private var asked: Set<String> = []

    static func name(_ key: SettingKey, _ kind: Cue.Kind, _ option: Int) -> String {
        "\(kind.rawValue).\(key.rawValue).\(option)"
    }

    /// The picture for an option, if drawn; asking starts the drawing.
    func image(_ key: SettingKey, kind: Cue.Kind, option: Int, value: SettingValue) -> CGImage? {
        let name = Self.name(key, kind, option)
        if let image = images[name] { return image }
        guard !asked.contains(name) else { return nil }
        asked.insert(name)
        Task { @MainActor in
            if let image = await Self.draw(key, kind: kind, value: value) { images[name] = image }
        }
        return nil
    }

    /// The sample with the option set, at its telling moment.
    private static func draw(_ key: SettingKey, kind: Cue.Kind, value: SettingValue) async -> CGImage? {
        var cue = sample(for: key, kind: kind)
        key.set(value, in: &cue)
        guard let renderer = GallerySamples.renderer(for: cue.kind) else { return nil }
        let runner = StageRunner(renderers: [cue.kind: renderer])
        let surface = SurfaceLayer(role: .preview)
        surface.contentsScale = 1
        surface.frame = CGRect(origin: .zero, size: size)
        surface.updateInset()
        runner.attach(surface)
        // Pictures decode in the background: wait for them, a little.
        if ShowThumbnail.loadsPictures(renderer) {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                var finished = false
                func finish() { if !finished { finished = true; done.resume() } }
                ShowThumbnail.setOnReady(renderer) { finish() }
                runner.load(cue, show: ShowSettings(), presentation: .run, at: 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MainActor.assumeIsolated { finish() } }
            }
            ShowThumbnail.setOnReady(renderer, nil)
        }
        runner.load(cue, show: ShowSettings(), presentation: .run, at: 0)
        _ = runner.tick(at: moment(for: key, cue: cue))
        return ShowThumbnail.render(surface)
    }

    /// Which sample shows the option best: a single letter for the letters,
    /// the dusk picture for order and reveal, the street map for the camera,
    /// the layered picture for its context, entrance and frame.
    private static func sample(for key: SettingKey, kind: Cue.Kind) -> Cue {
        switch key {
        case .letters: Cue(content: .title(TitleContent(text: "G")))
        default: GallerySamples.cue(for: kind)
        }
    }

    /// When to catch it, in seconds from GO: a letter mid-travel, a picture
    /// 40% revealed, a layered picture at its second step, a map finished.
    private static func moment(for key: SettingKey, cue: Cue) -> Double {
        let hold = Double(cue.timing.holdTicks * cue.timing.clockMs) / 1000
        switch key {
        case .letters: return hold + 0.25
        case .order, .reveal: return hold + 0.8
        case .context, .entrance, .push: return hold + 1.6
        default: return 60
        }
    }
}
