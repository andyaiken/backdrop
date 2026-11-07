import Foundation

/// Which display link drives the cue clock: the projector's while it is on
/// screen, so frames land on its refresh, and the console preview's while it
/// isn't, so cues keep running through a knocked cable. The console view that
/// drives it is one that is always on screen: a hidden view's link doesn't fire.
@MainActor
final class ClockSource {
    private let projector: SurfaceView
    private let preview: SurfaceView

    var ticking = false { didSet { update() } }
    var projectorVisible = false { didSet { update() } }

    init(projector: SurfaceView, preview: SurfaceView) {
        self.projector = projector
        self.preview = preview
    }

    private func update() {
        projector.setTicking(ticking && projectorVisible)
        preview.setTicking(ticking && !projectorVisible)
    }
}
