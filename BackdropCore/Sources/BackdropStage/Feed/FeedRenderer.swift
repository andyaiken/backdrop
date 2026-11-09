import BackdropCore
import CoreGraphics
import Foundation
import QuartzCore

/// Live feed cues: a camera's picture, shown as it arrives. Like a video
/// cue it plays on its own clock and never settles; unlike one it can fail
/// at any moment, because a wireless camera drops, so it watches for the
/// picture to stop and does what the cue says: black, or the last frame.
///
/// The live surface and the console preview both show the picture, from the
/// one camera. The preview adds a readout of the feed's state.
///
/// Turning, mirroring and fitting are done here, once, whatever the source.
/// A camera is started when the cue is armed, not on GO, because a capture
/// session takes a second or more to give its first frame.
@MainActor
public final class FeedRenderer: CueRenderer, ReportsProblems, ArmsCues, Snapshots {
    public let isInstant = true
    public var onProblem: ((String) -> Void)?
    public var onArmStateChange: (() -> Void)?

    /// Cameras kept running: the one on stage and the one standing by. A
    /// camera running is a camera's light on, and an iPhone's battery.
    static let keep = 2
    /// How long without a picture before the feed counts as lost.
    static let staleAfter = 1.5
    /// How long a camera may take to give its first picture.
    static let noPictureAfter = 10.0

    private let camera: FeedCamera
    private var clips: [UUID: Clip] = [:]
    private(set) var current: Clip?
    private var trees: [ObjectIdentifier: Tree] = [:]
    private var watchdog: Timer?

    /// Held to keep hearing of cameras coming and going.
    private var observation: AnyObject?

    /// - Parameter camera: Where pictures come from. The default is shared by
    ///   every renderer, so the console's previews and the stage show one
    ///   camera and not several opened separately.
    public init(camera: FeedCamera = CaptureCamera.shared) {
        self.camera = camera
        observation = camera.observeDevices { [weak self] in self?.devicesChanged() }
    }

    /// The cameras that can be chosen now, for the editor.
    public var devices: [FeedDevice] { camera.devices() }

    /// Asks for permission to use cameras, if it hasn't been asked.
    public func requestAccess() { camera.requestAccess() }

    final class Clip {
        let cue: Cue
        var content: FeedContent
        var session: FeedSession
        var state = ArmState.arming
        var openedAt = CACurrentMediaTime()
        var lastUsed = Date()
        /// Preloaded for a cue that may fire next, and not yet on stage.
        var preloaded = false
        /// The last picture before the feed was lost, to hold if the cue says.
        var held: CGImage?

        init(cue: Cue, content: FeedContent, session: FeedSession) {
            self.cue = cue
            self.content = content
            self.session = session
        }

        var settings: FeedSettings { content.settings }

        /// What the camera is called, for the operator.
        var label: String {
            settings.deviceName.isEmpty ? (settings.device.isEmpty ? "the camera" : settings.device) : settings.deviceName
        }

        func matches(_ other: FeedContent) -> Bool {
            other.settings.device == settings.device && other.settings.deviceName == settings.deviceName
        }
    }

    /// One clip's layers on one surface: the picture, turned and mirrored,
    /// with the frozen last frame over it for when the feed is lost.
    final class Entry {
        let holder = StillLayer()
        let rotor = StillLayer()
        let frozen = StillLayer()
        var picture: CALayer
        var fit: FeedFit

        init(picture: CALayer, fit: FeedFit) {
            self.picture = picture
            self.fit = fit
            holder.addSublayer(rotor)
            rotor.addSublayer(picture)
            rotor.addSublayer(frozen)
            frozen.isHidden = true
            holder.opacity = 0
        }
    }

    final class Tree {
        let surface: SurfaceLayer
        let root = StillLayer()
        var entries: [UUID: Entry] = [:]
        let strip = StillLayer()
        let readout = TextLayer()

        init(surface: SurfaceLayer) {
            self.surface = surface
            root.isHidden = true
            root.backgroundColor = CGColor(gray: 0, alpha: 1)
            if surface.role == .preview {
                strip.backgroundColor = CGColor(gray: 0, alpha: 0.6)
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
        for clip in clips.values { addLayers(for: clip, to: tree) }
        fit(surface)
        show(current, on: tree)
    }

    public func unmount(from surface: SurfaceLayer) {
        trees.removeValue(forKey: ObjectIdentifier(surface))?.root.removeFromSuperlayer()
    }

    public func setVisible(_ visible: Bool, on surface: SurfaceLayer) {
        tree(for: surface)?.root.isHidden = !visible
    }

    /// Takes the feed off stage. The camera keeps running if it is wanted
    /// again, as when an edit redraws the cue; otherwise it is let go.
    public func clear(_ surface: SurfaceLayer) {
        current = nil
        for tree in trees.values { show(nil, on: tree) }
        // Whether another feed cue follows is known only once the stage has
        // finished loading, so what isn't wanted goes after.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.releaseUnwanted() }
        }
    }

    public func prepare(_ cue: Cue, show _: ShowSettings) {
        guard case .feed(let content) = cue.content else { return }
        let clip = arm(cue, content)
        clip.lastUsed = Date()
        clip.preloaded = false
        current = clip
        for tree in trees.values { show(clip, on: tree) }
        releaseUnwanted()
        if case .failed(let message) = clip.state { onProblem?(problem(clip, message)) }
    }

    /// A feed never settles: it is on until something else is.
    public func frame(_ f: Int) -> Bool {
        current == nil
    }

    public func fit(_ surface: SurfaceLayer) {
        guard let tree = tree(for: surface) else { return }
        let bounds = surface.inset.bounds
        tree.root.frame = bounds
        for (id, entry) in tree.entries { layout(entry, in: bounds, clip: clips[id]) }
        guard !tree.isLive else { return }
        let size = max(9, min(bounds.height * 0.07, 15))
        let height = (size * 1.9).rounded()
        tree.strip.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        tree.readout.frame = tree.strip.bounds.insetBy(dx: size * 0.8, dy: 0)
        tree.readout.contentsScale = surface.contentsScale
        tree.readout.baseline = (height - size) / 2 + size * 0.2
        if let clip = current { updateReadout(tree, clip) }
    }

    /// Arming: the camera of a cue that may fire next is started before GO.
    public func preload(_ cue: Cue, show: ShowSettings) {
        guard case .feed(let content) = cue.content else { return }
        let clip = arm(cue, content)
        clip.lastUsed = Date()
        if clip !== current { clip.preloaded = true }
    }

    /// The picture on stage, for a crossfade out of the feed.
    public func snapshot(size: CGSize) -> CGImage? {
        guard let clip = current, let image = picture(of: clip) else { return nil }
        return FeedPicture.render(image, size: size, settings: clip.settings)
    }

    /// What the stage shows of the clip now, as an image: the newest picture,
    /// the last one if the feed is lost and the cue holds it, or nothing.
    private func picture(of clip: Clip) -> CGImage? {
        if case .failed = clip.state { return clip.settings.onLoss == .hold ? clip.held : nil }
        return clip.session.frame
    }

    // MARK: Arming

    @discardableResult
    private func arm(_ cue: Cue, _ content: FeedContent) -> Clip {
        if let clip = clips[cue.id] {
            if clip.matches(content) {
                // Turned, mirrored or fitted differently: the same camera.
                if clip.content != content {
                    let refit = clip.settings.fit != content.settings.fit
                    clip.content = content
                    for tree in trees.values {
                        if refit { removeLayers(for: clip, from: tree); addLayers(for: clip, to: tree) }
                        if let entry = tree.entries[cue.id] { layout(entry, in: tree.root.bounds, clip: clip) }
                    }
                    refresh()
                    for tree in trees.values { show(current, on: tree) }
                }
                return clip
            }
            discard(clip)
        }
        let clip = Clip(cue: cue, content: content, session: camera.open(content.settings))
        clips[cue.id] = clip
        for tree in trees.values { addLayers(for: clip, to: tree) }
        clip.state = evaluate(clip)
        evictBeyondLimit()
        startWatching()
        onArmStateChange?()
        return clip
    }

    /// Starts the camera again, as when a cable is plugged back in or a
    /// wireless camera comes back into range.
    private func reopen(_ clip: Clip) {
        clip.session.stop()
        clip.session = camera.open(clip.settings)
        clip.openedAt = CACurrentMediaTime()
        clip.state = evaluate(clip)
        for tree in trees.values {
            removeLayers(for: clip, from: tree)
            addLayers(for: clip, to: tree)
        }
    }

    private func devicesChanged() {
        var changed = false
        for clip in clips.values {
            guard case .failed = clip.state else { continue }
            reopen(clip)
            changed = true
        }
        guard changed else { return }
        refresh()
        for tree in trees.values { show(current, on: tree) }
        onArmStateChange?()
    }

    // MARK: Watching

    private func startWatching() {
        guard watchdog == nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func stopWatching() {
        watchdog?.invalidate()
        watchdog = nil
    }

    /// Where each feed stands: waiting for its first picture, live, or lost.
    private func evaluate(_ clip: Clip) -> ArmState {
        if let failure = clip.session.failure { return .failed(failure) }
        guard let last = clip.session.lastFrameTime else {
            return CACurrentMediaTime() - clip.openedAt > Self.noPictureAfter
                ? .failed("No picture is coming from \(clip.label).") : .arming
        }
        return CACurrentMediaTime() - last > Self.staleAfter
            ? .failed("The picture from \(clip.label) has stopped.") : .armed
    }

    /// Looks at every feed, and tells the console of any that changed.
    func refresh() {
        var changed = false
        for clip in clips.values {
            let state = evaluate(clip)
            guard state != clip.state else { continue }
            clip.state = state
            changed = true
            if case .failed(let message) = state {
                // The frame to hold, if the cue holds it.
                clip.held = clip.session.frame
                if current === clip { onProblem?(problem(clip, message)) }
            } else {
                clip.held = nil
            }
        }
        guard changed else { return }
        for tree in trees.values { show(current, on: tree) }
        onArmStateChange?()
    }

    private func problem(_ clip: Clip, _ message: String) -> String {
        let outcome = clip.settings.onLoss == .black ? "the stage is black" : "the stage holds the last picture"
        return "Cue \(clip.cue.number)\u{2019}s live feed: \(message) For now \(outcome)."
    }

    // MARK: Layers

    private func addLayers(for clip: Clip, to tree: Tree) {
        guard tree.entries[clip.cue.id] == nil else { return }
        let entry = Entry(picture: clip.session.makePictureLayer(fit: clip.settings.fit), fit: clip.settings.fit)
        tree.entries[clip.cue.id] = entry
        tree.root.insertSublayer(entry.holder, at: 0)
        layout(entry, in: tree.root.bounds, clip: clip)
    }

    private func removeLayers(for clip: Clip, from tree: Tree) {
        tree.entries.removeValue(forKey: clip.cue.id)?.holder.removeFromSuperlayer()
    }

    private func layout(_ entry: Entry, in bounds: CGRect, clip: Clip?) {
        let settings = clip?.settings ?? FeedSettings()
        entry.holder.frame = CGRect(origin: .zero, size: bounds.size)
        let size = settings.rotation.isSideways ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        entry.rotor.transform = CATransform3DIdentity
        entry.rotor.bounds = CGRect(origin: .zero, size: size)
        entry.rotor.position = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        entry.rotor.transform = FeedPicture.transform(settings)
        entry.picture.frame = entry.rotor.bounds
        entry.frozen.frame = entry.rotor.bounds
        entry.frozen.contentsGravity = settings.fit == .fit ? .resizeAspect : .resizeAspectFill
    }

    /// Shows `clip` on a surface, or nothing.
    private func show(_ clip: Clip?, on tree: Tree) {
        for (id, entry) in tree.entries {
            guard let clip, clip.cue.id == id else {
                entry.holder.opacity = 0
                continue
            }
            switch clip.state {
            case .failed:
                // Lost: black, or the last picture held.
                let holds = clip.settings.onLoss == .hold && clip.held != nil
                entry.frozen.contents = holds ? clip.held : nil
                entry.frozen.isHidden = !holds
                entry.picture.isHidden = holds
                entry.holder.opacity = holds ? 1 : 0
            case .arming, .armed:
                entry.frozen.isHidden = true
                entry.picture.isHidden = false
                entry.holder.opacity = 1
            }
        }
        if !tree.isLive {
            if let clip { updateReadout(tree, clip) } else { tree.readout.runs = [] }
        }
    }

    /// The state of the feed, for the operator, on the preview only.
    private func updateReadout(_ tree: Tree, _ clip: Clip) {
        let size = max(9, min(tree.surface.inset.bounds.height * 0.07, 15))
        let text: String
        switch clip.state {
        case .arming: text = "CONNECTING \u{2014} NOT ARMED"
        case .armed: text = "LIVE \u{2014} \(clip.label.uppercased())"
        case .failed: text = "NO SIGNAL \u{2014} " + (clip.settings.onLoss == .black ? "BLACK" : "HOLDING LAST PICTURE")
        }
        tree.readout.runs = [TextRun(text: text, font: StageFont.text(size: size), colour: Palette.bone.cgColor(alpha: 0.9), x: 0)]
    }

    // MARK: Housekeeping

    /// Lets go of cameras nothing needs: not on stage, and not standing by.
    private func releaseUnwanted() {
        for clip in clips.values where clip !== current && !clip.preloaded { discard(clip) }
    }

    private func evictBeyondLimit() {
        let spare = clips.values.filter { $0 !== current }.sorted { $0.lastUsed < $1.lastUsed }
        for clip in spare.prefix(max(0, clips.count - Self.keep)) { discard(clip) }
    }

    private func discard(_ clip: Clip) {
        clip.session.stop()
        clips.removeValue(forKey: clip.cue.id)
        for tree in trees.values { removeLayers(for: clip, from: tree) }
        if current === clip { current = nil }
        if clips.isEmpty { stopWatching() }
    }
}
