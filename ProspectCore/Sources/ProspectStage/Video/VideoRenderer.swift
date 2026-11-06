import AVFoundation
import ProspectCore
import QuartzCore
import VideoToolbox

/// Video cues: moving footage. Unlike the other cue types a video doesn't
/// resolve over a frame count, it plays, on AVPlayer's own clock; `frame`
/// only polls it, for the readouts and to say when it has ended.
///
/// It is also the one renderer that paints surfaces differently. The live
/// surface gets the picture. The console preview gets a poster frame with
/// elapsed and remaining time: at preview size a moving picture tells the
/// operator nothing, and a countdown tells them when to stand by.
///
/// Audio is always muted. Sound is another operator on another machine, and
/// a switch that let this play into the room would be the switch left on.
@MainActor
public final class VideoRenderer: CueRenderer, ReportsProblems, ArmsCues, Snapshots {
    public let isInstant = true
    public var onProblem: ((String) -> Void)?
    public var onArmStateChange: (() -> Void)?

    /// Players kept ready: what might fire next, what is on stage, and what
    /// was on stage last, so R restarts at once.
    static let keep = 4

    private let media: (String) -> URL?
    private var clips: [UUID: Clip] = [:]
    private(set) var current: Clip?
    private var started = false
    private var trees: [ObjectIdentifier: Tree] = [:]

    public init(media: @escaping (String) -> URL? = { _ in nil }) {
        self.media = media
    }

    /// One clip's player, armed or playing.
    final class Clip {
        let cue: Cue
        let content: VideoContent
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
        var item: AVPlayerItem?
        var duration = CMTime.zero
        var poster: CGImage?
        var state = ArmState.arming
        var reachedEnd = false
        var playWhenArmed = false
        var lastUsed = Date()
        var endObserver: NSObjectProtocol?

        /// A tap on the picture the projector is being given, so a crossfade
        /// can have the frame on stage without decoding the file a second
        /// time. The last frame taken is kept, because a clip that has ended
        /// is no longer being ticked and nothing more will arrive.
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable](),
        ])
        /// Whichever item the output is on. A looper plays copies of the
        /// template, not the template, and a fresh one each time round.
        weak var outputItem: AVPlayerItem?
        var lastFrame: CVPixelBuffer?
        /// How the file says its picture stands up. Frames come off the
        /// output as they were encoded; the player layer turns them, so
        /// anything drawn from them has to be turned the same way.
        var orientation = CGAffineTransform.identity

        init(cue: Cue, content: VideoContent) {
            self.cue = cue
            self.content = content
            player.isMuted = true
            player.volume = 0
            // A held clip freezes on its last frame rather than emptying.
            player.actionAtItemEnd = .pause
            // Reading frames off must not take them from the projector.
            output.suppressesPlayerRendering = false
        }

        var elapsed: CMTime { player.currentTime() }

        func matches(_ other: VideoContent) -> Bool {
            other.src == content.src && other.atEnd == content.atEnd
        }
    }

    /// One surface's layers: a player layer for each clip on the live
    /// surface, so an armed clip's first frame is already waiting there; on
    /// the preview, a poster and a readout.
    final class Tree {
        let surface: SurfaceLayer
        let root = StillLayer()
        var players: [UUID: StillPlayerLayer] = [:]
        let poster = StillLayer()
        let strip = StillLayer()
        let readout = TextLayer()

        init(surface: SurfaceLayer) {
            self.surface = surface
            root.isHidden = true
            root.backgroundColor = CGColor(gray: 0, alpha: 1)
            if surface.role == .preview {
                poster.contentsGravity = .resizeAspect
                strip.backgroundColor = CGColor(gray: 0, alpha: 0.6)
                root.addSublayer(poster)
                root.addSublayer(strip)
                strip.addSublayer(readout)
            }
        }

        var isLive: Bool { surface.role == .live }
    }

    func tree(for surface: SurfaceLayer) -> Tree? {
        trees[ObjectIdentifier(surface)]
    }

    // MARK: ArmsCues

    public func armState(for cue: UUID) -> ArmState? {
        clips[cue]?.state
    }

    // MARK: CueRenderer

    public func mount(on surface: SurfaceLayer) {
        let tree = Tree(surface: surface)
        trees[ObjectIdentifier(surface)] = tree
        surface.inset.addSublayer(tree.root)
        if tree.isLive {
            for clip in clips.values { addPlayerLayer(for: clip, to: tree) }
        }
        fit(surface)
        show(current, on: tree)
    }

    public func unmount(from surface: SurfaceLayer) {
        trees.removeValue(forKey: ObjectIdentifier(surface))?.root.removeFromSuperlayer()
    }

    public func setVisible(_ visible: Bool, on surface: SurfaceLayer) {
        tree(for: surface)?.root.isHidden = !visible
    }

    /// Stops whatever was playing. It goes back to the start and stays
    /// armed, so running it again is instant.
    public func clear(_ surface: SurfaceLayer) {
        if let clip = current {
            current = nil
            clip.player.pause()
            clip.playWhenArmed = false
            clip.reachedEnd = false
            // Back at the start, so the frame it was stopped on is not the
            // one to hand over if it is brought up again.
            clip.lastFrame = nil
            clip.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        started = false
        for tree in trees.values { show(nil, on: tree) }
    }

    public func prepare(_ cue: Cue, defaults: ShowSettings) {
        guard case .video(let content) = cue.content else { return }
        let clip = arm(cue, content)
        clip.lastUsed = Date()
        current = clip
        started = false
        for tree in trees.values { show(clip, on: tree) }
        // Said again as it fires, not only when it was armed: this is when
        // the operator needs to know the stage has gone black.
        if case .failed(let message) = clip.state { onProblem?(message) }
    }

    public func frame(_ f: Int) -> Bool {
        guard let clip = current else { return true }
        if !started {
            started = true
            if f >= StageRunner.settledFrame { putUpFinished(clip) } else { play(clip) }
        }
        keepCurrentFrame(clip)
        for tree in trees.values where !tree.isLive { updateReadout(tree, clip) }
        if case .failed = clip.state { return true }
        return clip.content.atEnd == .loop ? false : clip.reachedEnd
    }

    /// The frame on stage, for a crossfade out of a clip: an AVPlayerLayer
    /// draws into no bitmap, so the frame the projector was last given is
    /// taken off the clip's own video output and set on black in the shape
    /// the player layer shows it.
    public func snapshot(size: CGSize) -> CGImage? {
        guard let clip = current, clip.state == .armed || started,
              size.width >= 1, size.height >= 1 else { return nil }
        // Asked for again here and not only on the tick: a clip that has
        // ended stops being ticked, and its last frame arrives after that.
        keepCurrentFrame(clip)
        // Nothing comes off the output for the first instant of a clip,
        // before a frame has been handed over. The poster is that clip's own
        // first frame, decoded at arming and already the right way up, and
        // the first instant is the only time it is what the projector shows.
        let frame: CGImage, orientation: CGAffineTransform
        if let pixels = clip.lastFrame, let picture = Self.image(from: pixels) {
            (frame, orientation) = (picture, clip.orientation)
        } else if let poster = clip.poster {
            (frame, orientation) = (poster, .identity)
        } else {
            return nil
        }

        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // The shape the audience sees, which is the encoded frame turned the
        // way the file asks. The turn is pinned back to the origin first,
        // since a preferred transform carries its own offset.
        let encoded = CGRect(x: 0, y: 0, width: Double(frame.width), height: Double(frame.height))
        let turned = encoded.applying(orientation)
        guard turned.width >= 1, turned.height >= 1 else { return nil }
        let upright = orientation.concatenating(CGAffineTransform(translationX: -turned.minX, y: -turned.minY))
        let scale = min(Double(w) / turned.width, Double(h) / turned.height)
        let fw = turned.width * scale, fh = turned.height * scale

        // Worked in the film's own coordinates — origin top left, y
        // downwards — the space a preferred transform is written in.
        ctx.translateBy(x: 0, y: Double(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: (Double(w) - fw) / 2, y: (Double(h) - fh) / 2)
        ctx.scaleBy(x: scale, y: scale)
        ctx.concatenate(upright)
        // And back the right way up for the draw itself, which reads a
        // CGImage as y upwards whatever the space around it does.
        ctx.translateBy(x: 0, y: encoded.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(frame, in: encoded)
        return ctx.makeImage()
    }

    /// Keeps the output on whatever item is actually playing: a looper runs
    /// copies of the template, and a fresh copy each time round.
    private func follow(_ clip: Clip) {
        guard let item = clip.player.currentItem, clip.outputItem !== item else { return }
        clip.outputItem?.remove(clip.output)
        item.add(clip.output)
        clip.outputItem = item
    }

    /// Takes the frame being shown now, if the output has one. Held as it
    /// comes rather than drawn, because drawing every frame would cost on
    /// every tick what a crossfade costs once.
    private func keepCurrentFrame(_ clip: Clip) {
        follow(clip)
        var time = clip.output.itemTime(forHostTime: CACurrentMediaTime())
        if !time.isValid || time.seconds.isNaN { time = clip.player.currentTime() }
        guard time.isValid, !time.seconds.isNaN,
              let pixels = clip.output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        clip.lastFrame = pixels
    }

    private static func image(from pixels: CVPixelBuffer) -> CGImage? {
        var image: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(pixels, options: nil, imageOut: &image) == noErr else { return nil }
        return image
    }

    public func fit(_ surface: SurfaceLayer) {
        guard let tree = tree(for: surface) else { return }
        let bounds = surface.inset.bounds
        tree.root.frame = bounds
        for layer in tree.players.values { layer.frame = bounds }
        guard !tree.isLive else { return }
        tree.poster.frame = bounds
        let size = max(9, min(bounds.height * 0.07, 15))
        let height = (size * 1.9).rounded()
        tree.strip.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        tree.readout.frame = tree.strip.bounds.insetBy(dx: size * 0.8, dy: 0)
        tree.readout.contentsScale = surface.contentsScale
        tree.readout.baseline = (height - size) / 2 + size * 0.2
        if let clip = current { updateReadout(tree, clip) }
    }

    /// Arming: the cue that may fire next is loaded, prerolled and waiting
    /// at its first frame before GO.
    public func preload(_ cue: Cue, defaults: ShowSettings) {
        guard case .video(let content) = cue.content else { return }
        arm(cue, content).lastUsed = Date()
    }

    // MARK: Arming

    @discardableResult
    private func arm(_ cue: Cue, _ content: VideoContent) -> Clip {
        if let clip = clips[cue.id], clip.matches(content) { return clip }
        if let stale = clips[cue.id] { discard(stale) }

        let clip = Clip(cue: cue, content: content)
        clips[cue.id] = clip
        evictBeyondLimit()
        for tree in trees.values where tree.isLive { addPlayerLayer(for: clip, to: tree) }

        guard !content.src.isEmpty, let url = media(content.src), FileManager.default.isReadableFile(atPath: url.path) else {
            fail(clip, "Cue \(cue.number)\u{2019}s clip\(content.src.isEmpty ? "" : ", \(Self.name(content.src)),") is missing from the show, so it will go to black.")
            return clip
        }
        Task { await load(clip, from: url) }
        onArmStateChange?()
        return clip
    }

    private func load(_ clip: Clip, from url: URL) async {
        let asset = AVURLAsset(url: url)
        do {
            guard try await asset.load(.isPlayable) else { throw CocoaError(.fileReadCorruptFile) }
            clip.duration = try await asset.load(.duration)
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                clip.orientation = (try? await track.load(.preferredTransform)) ?? .identity
            }
            let item = AVPlayerItem(asset: asset)
            clip.item = item
            if clip.content.atEnd == .loop {
                clip.looper = AVPlayerLooper(player: clip.player, templateItem: item)
            } else {
                clip.player.insert(item, after: nil)
                // Looked up again by cue and item, since a clip can be replaced.
                let cue = clip.cue.id, itemID = ObjectIdentifier(item)
                clip.endObserver = NotificationCenter.default.addObserver(
                    forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, let clip = self.clips[cue], clip.item.map(ObjectIdentifier.init) == itemID else { return }
                        self.reachedEnd(clip)
                    }
                }
            }
            // Ready to play, then prerolled so the first frames are decoded.
            while clip.player.status == .unknown || clip.player.currentItem?.status ?? .unknown == .unknown {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard clip.player.status == .readyToPlay, clip.player.currentItem?.status == .readyToPlay else {
                throw clip.player.currentItem?.error ?? clip.player.error ?? CocoaError(.fileReadCorruptFile)
            }
            if clip.player.rate == 0 { _ = await clip.player.preroll(atRate: 1) }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 960, height: 540)
            clip.poster = try? await generator.image(at: .zero).image

            guard clips[clip.cue.id] === clip else { return }
            // On before GO, so the first frame is already waiting when a
            // quick second GO crossfades straight back out of it.
            follow(clip)
            clip.state = .armed
            for tree in trees.values where !tree.isLive && current === clip { show(clip, on: tree) }
            if clip.playWhenArmed { clip.player.play() }
            onArmStateChange?()
        } catch {
            fail(clip, "Cue \(clip.cue.number)\u{2019}s clip, \(Self.name(clip.content.src)), couldn\u{2019}t be played, so it will go to black.")
        }
    }

    private func fail(_ clip: Clip, _ message: String) {
        clip.state = .failed(message)
        clip.reachedEnd = true
        for tree in trees.values { tree.players[clip.cue.id]?.opacity = 0 }
        onProblem?(message)
        onArmStateChange?()
    }

    private static func name(_ src: String) -> String {
        (src as NSString).lastPathComponent
    }

    // MARK: Playing

    private func play(_ clip: Clip) {
        clip.reachedEnd = false
        switch clip.state {
        case .armed: clip.player.play()
        case .arming: clip.playWhenArmed = true
        case .failed: break
        }
    }

    /// As on resuming after a crash: a held clip on its last frame, a black
    /// one black, a looping one looping.
    private func putUpFinished(_ clip: Clip) {
        switch clip.content.atEnd {
        case .loop:
            play(clip)
        case .black:
            reachedEnd(clip)
        case .hold:
            clip.reachedEnd = true
            if clip.duration > .zero {
                clip.player.seek(to: clip.duration, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
    }

    private func reachedEnd(_ clip: Clip) {
        clip.reachedEnd = true
        guard clip.content.atEnd == .black, current === clip else { return }
        // Cut to black, as a blank cue would.
        for tree in trees.values { tree.players[clip.cue.id]?.opacity = 0 }
    }

    // MARK: Layers

    private func addPlayerLayer(for clip: Clip, to tree: Tree) {
        guard tree.players[clip.cue.id] == nil else { return }
        let layer = StillPlayerLayer()
        layer.player = clip.player
        layer.videoGravity = .resizeAspect
        layer.frame = tree.root.bounds
        // Transparent rather than hidden, so it stays in the render tree and
        // has its first frame ready when GO makes it visible.
        layer.opacity = 0
        tree.players[clip.cue.id] = layer
        tree.root.addSublayer(layer)
    }

    /// Shows `clip` on a surface, or nothing.
    private func show(_ clip: Clip?, on tree: Tree) {
        if tree.isLive {
            for (id, layer) in tree.players {
                let visible = id == clip?.cue.id && clip.map(isShowable) == true
                layer.opacity = visible ? 1 : 0
            }
        } else {
            tree.poster.contents = clip?.poster
            if let clip { updateReadout(tree, clip) } else { tree.readout.runs = [] }
        }
    }

    private func isShowable(_ clip: Clip) -> Bool {
        if case .failed = clip.state { return false }
        return !(clip.reachedEnd && clip.content.atEnd == .black)
    }

    /// Elapsed and remaining, for the operator, on the preview only.
    private func updateReadout(_ tree: Tree, _ clip: Clip) {
        let size = max(9, min(tree.surface.inset.bounds.height * 0.07, 15))
        let font = StageFont.text(size: size)
        let text: String
        switch clip.state {
        case .failed:
            text = "NO CLIP \u{2014} BLACK"
        case .arming:
            text = "LOADING \u{2014} NOT ARMED"
        case .armed:
            let duration = clip.duration.seconds.isFinite ? clip.duration.seconds : 0
            var elapsed = max(0, clip.elapsed.seconds.isFinite ? clip.elapsed.seconds : 0)
            if clip.content.atEnd == .loop, duration > 0 { elapsed = elapsed.truncatingRemainder(dividingBy: duration) }
            // Remaining rounds up, as a countdown should: it reads 0:00 only
            // when the picture has actually finished.
            let remaining = max(0, duration - elapsed).rounded(.up)
            switch (clip.reachedEnd && started, clip.content.atEnd) {
            case (true, .hold): text = "ENDED \u{2014} HOLDING LAST FRAME"
            case (true, .black): text = "ENDED \u{2014} BLACK"
            case (_, .loop): text = "\(Self.clock(elapsed)) of \(Self.clock(duration)) \u{2014} LOOPING"
            default: text = "\(Self.clock(elapsed))   \(Self.clock(remaining)) LEFT   THEN \(clip.content.atEnd == .black ? "BLACK" : "HOLDS")"
            }
        }
        tree.readout.runs = [TextRun(text: text, font: font, colour: Palette.bone.cgColor(alpha: 0.9), x: 0)]
    }

    /// m:ss.
    static func clock(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    // MARK: Housekeeping

    private func evictBeyondLimit() {
        let spare = clips.values.filter { $0 !== current }.sorted { $0.lastUsed < $1.lastUsed }
        for clip in spare.prefix(max(0, clips.count - Self.keep)) { discard(clip) }
    }

    private func discard(_ clip: Clip) {
        clip.player.pause()
        clip.looper?.disableLooping()
        clip.outputItem?.remove(clip.output)
        clip.outputItem = nil
        clip.lastFrame = nil
        clip.player.removeAllItems()
        if let observer = clip.endObserver { NotificationCenter.default.removeObserver(observer) }
        clips.removeValue(forKey: clip.cue.id)
        for tree in trees.values { tree.players.removeValue(forKey: clip.cue.id)?.removeFromSuperlayer() }
    }
}

/// A player layer with no implicit animations: shown and hidden on the cut.
final class StillPlayerLayer: AVPlayerLayer {
    override func action(forKey event: String) -> (any CAAction)? {
        nil
    }
}
