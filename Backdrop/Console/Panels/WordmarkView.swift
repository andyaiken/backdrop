import AppKit
import BackdropCore
import BackdropStage
import QuartzCore

/// The BACKDROP wordmark: a title cue of its own, painted by the stage's own
/// title renderer on a surface of its own, so it decrypts exactly as a title
/// does on stage. Edit mode shows it on a screen in the preview's place when
/// no cue is selected.
///
/// Each reveal picks one of the ways a title's letters can find their way
/// home, at random from all of them, so a new way shows here as soon as the
/// stage can do it.
@MainActor
final class WordmarkView: NSView {
    static let name = "BACKDROP"

    private let surface = SurfaceLayer(role: .preview)
    private let runner = StageRunner(renderers: [.title: TitleRenderer()])
    private var link: CADisplayLink?

    init() {
        super.init(frame: .zero)
        // Layer-hosting: the view's layer is the surface itself.
        layer = surface
        wantsLayer = true
        // It sits 1pt inside its frame's border, so its corners are rounded
        // 1pt less to run alongside it.
        surface.cornerRadius = Desk.previewRadius - 1
        surface.cornerCurve = .continuous
        runner.attach(surface)
        // Home already: what shows until a reveal, and instead of one under
        // reduced motion.
        runner.load(Self.cue(), show: ShowSettings(), presentation: .settled, at: CACurrentMediaTime())
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(Self.name)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Not flipped, unlike the console's other views: AppKit flips a hosted
    // layer to match its view, and the stage lays itself out top-down on an
    // unflipped layer, so a flipped one draws every letter upside down.

    override func layout() {
        super.layout()
        surface.frame = bounds
        runner.relayout(surface)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        surface.contentsScale = window?.backingScaleFactor ?? 2
        runner.relayout(surface)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { stopTicking() }
    }

    /// The name as a title cue: no scene line or histogram, a moment of
    /// ciphertext, then the letters home a frame every 50ms, by one way at
    /// random unless told which.
    private static func cue(letters: TitleLetters? = nil) -> Cue {
        let letters = letters ?? TitleLetters.allCases.randomElement() ?? .cycle
        let settings = TitleSettings(clockMs: 50, waveTicks: 3, holdTicks: 20, histogram: false, sceneLine: false,
                                     letters: letters)
        // The key never shows, on stage or here. Its shifts, 5, 8, 1, 13, 13,
        // 0, 2, 2, 8, are mostly Fibonacci numbers, for anyone who looks.
        return Cue(content: .title(TitleContent(text: name, key: "FIBONACCI", settings: settings)))
    }

    /// Decrypts the wordmark the way a title cue decrypts on stage. Not at
    /// all under reduced motion.
    func decryptWordmark() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        runner.load(Self.cue(), show: ShowSettings(), presentation: .run, at: CACurrentMediaTime())
        startTicking()
    }

    // MARK: Clock

    /// A display link of its own, following whichever screen the view is on,
    /// stopped once the name is home.
    private func startTicking() {
        guard link == nil else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopTicking() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        _ = runner.tick(at: link.targetTimestamp)
        if !runner.needsTicks { stopTicking() }
    }

    #if DEBUG
    /// The wordmark held on one frame of a fresh reveal, for snapshots.
    /// Frames up to 0 are the ciphertext.
    func holdWordmark(atFrame frame: Int, letters: TitleLetters? = nil) {
        stopTicking()
        let cue = Self.cue(letters: letters)
        runner.load(cue, show: ShowSettings(), presentation: .run, at: 0)
        _ = runner.tick(at: Double((cue.timing.holdTicks + frame) * cue.timing.clockMs) / 1000)
    }
    #endif
}
