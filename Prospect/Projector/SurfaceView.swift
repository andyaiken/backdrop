import AppKit
import ProspectStage
import QuartzCore

/// Hosts a stage surface: the projector's, or the console's preview. Runs a
/// display link that follows whichever screen the view is on, and takes the
/// show keys when its window is key.
@MainActor
final class SurfaceView: NSView {
    let surface: SurfaceLayer
    weak var controller: ShowController?
    /// The runner this surface belongs to, if not the controller's main one.
    weak var runner: StageRunner?
    private var link: CADisplayLink?

    /// Hide the cursor over this view. The projector never shows one.
    var hidesCursor = false {
        didSet { if !hidesCursor { showCursor() } }
    }

    private var cursorHidden = false

    init(role: SurfaceLayer.Role) {
        surface = SurfaceLayer(role: role)
        super.init(frame: .zero)
        // Layer-hosting: the view's layer is the surface itself.
        layer = surface
        wantsLayer = true
        // Layered image cues desaturate and blend with Core Image filters,
        // which a layer-hosting view only draws when it is told to.
        layerUsesCoreImageFilters = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        surface.frame = bounds
        (runner ?? controller?.runner)?.relayout(surface)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        surface.contentsScale = window?.backingScaleFactor ?? 2
        (runner ?? controller?.runner)?.relayout(surface)
    }

    // MARK: Clock

    /// Runs or pauses this view's display link.
    func setTicking(_ on: Bool) {
        if link == nil, on {
            let link = displayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        link?.isPaused = !on
    }

    @objc private func step(_ link: CADisplayLink) {
        controller?.tick(at: link.targetTimestamp)
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        guard let controller, ShowKeys.handle(event, controller: controller) else {
            super.keyDown(with: event)
            return
        }
    }

    // MARK: Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        guard hidesCursor, !cursorHidden else { return }
        NSCursor.hide()
        cursorHidden = true
    }

    override func mouseExited(with event: NSEvent) {
        showCursor()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        showCursor()
    }

    private func showCursor() {
        guard cursorHidden else { return }
        NSCursor.unhide()
        cursorHidden = false
    }
}
