import AppKit
import BackdropCore
import BackdropStage
import QuartzCore
import SwiftUI

/// One card's moving picture: the kind's sample cue, run by its own renderer
/// from the start, left finished for a second and a half, then run again.
/// It is made when its card first comes into view and let go when the
/// gallery closes. Under Reduce Motion it shows the finished frame, once.
///
/// Video and live feed have no renderer here: a still of the storm with a
/// play mark, and a drawn camera, so nothing opens a file or a camera.
@MainActor
final class GalleryPreview: NSView {
    let kind: Cue.Kind
    private let surface = SurfaceLayer(role: .preview)
    private var runner: StageRunner?
    private let cue: Cue
    /// When the settled cue runs again.
    private var restartAt: Double?
    weak var clock: GalleryClock?

    static let rest: Double = 1.5

    #if DEBUG
    /// Snapshots take the Reduce Motion gallery whatever this Mac is set to.
    static var forceReduceMotion = false
    #endif

    static var reducesMotion: Bool {
        #if DEBUG
        if forceReduceMotion { return true }
        #endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    init(kind: Cue.Kind) {
        self.kind = kind
        cue = GallerySamples.cue(for: kind)
        super.init(frame: .zero)
        // Layer-hosting: the view's layer is the surface itself.
        layer = surface
        wantsLayer = true
        layerUsesCoreImageFilters = true
        surface.contentsScale = 2
        if let renderer = GallerySamples.renderer(for: kind) {
            let runner = StageRunner(renderers: [kind: renderer])
            runner.attach(surface)
            self.runner = runner
        } else {
            surface.backgroundColor = NSColor.black.cgColor
            surface.contents = Self.stand(in: kind)
            surface.contentsGravity = .resizeAspect
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Not flipped: as with the console's surfaces, a flipped layer-hosting
    // view would turn the stage upside down.

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        surface.contentsScale = window?.backingScaleFactor ?? 2
        runner?.relayout(surface)
    }

    override func layout() {
        super.layout()
        surface.frame = bounds
        surface.updateInset()
        if let runner { runner.relayout(surface) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, let runner else {
            clock?.remove(self)
            return
        }
        let now = CACurrentMediaTime()
        if Self.reducesMotion {
            runner.redraw(cue, show: ShowSettings(), at: now)
        } else {
            runner.load(cue, show: ShowSettings(), presentation: .run, at: now)
            clock?.add(self)
        }
    }

    /// From the gallery's display link.
    func tick(at time: Double) {
        guard let runner else { return }
        if let restartAt, time >= restartAt {
            self.restartAt = nil
            runner.change(to: cue, show: ShowSettings(), transition: Transition(style: .snap), at: time)
        }
        // Settled: rest a moment on the finished frame, then go again.
        if runner.tick(at: time) != nil { restartAt = time + Self.rest }
    }

    /// The pictures shown for the kinds that don't run here.
    private static func stand(in kind: Cue.Kind) -> CGImage? {
        let w = 640, h = 360
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let centre = CGPoint(x: w / 2, y: h / 2)
        switch kind {
        case .video:
            if let url = GallerySamples.media("storm.jpg"),
               let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let storm = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                context.draw(storm, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            // A play mark in a dark disc.
            context.setFillColor(CGColor(gray: 0, alpha: 0.55))
            context.fillEllipse(in: CGRect(x: centre.x - 44, y: centre.y - 44, width: 88, height: 88))
            context.setFillColor(CGColor(gray: 1, alpha: 0.9))
            context.move(to: CGPoint(x: centre.x - 14, y: centre.y + 22))
            context.addLine(to: CGPoint(x: centre.x + 24, y: centre.y))
            context.addLine(to: CGPoint(x: centre.x - 14, y: centre.y - 22))
            context.closePath()
            context.fillPath()
        default:
            // A camera: a body and a lens.
            context.setStrokeColor(CGColor(gray: 0.75, alpha: 1))
            context.setLineWidth(6)
            context.addPath(CGPath(roundedRect: CGRect(x: centre.x - 90, y: centre.y - 50, width: 130, height: 100),
                                   cornerWidth: 14, cornerHeight: 14, transform: nil))
            context.strokePath()
            context.move(to: CGPoint(x: centre.x + 40, y: centre.y - 18))
            context.addLine(to: CGPoint(x: centre.x + 90, y: centre.y - 44))
            context.addLine(to: CGPoint(x: centre.x + 90, y: centre.y + 44))
            context.addLine(to: CGPoint(x: centre.x + 40, y: centre.y + 18))
            context.strokePath()
            context.setFillColor(CGColor(red: 1, green: 0.31, blue: 0.25, alpha: 1))
            context.fillEllipse(in: CGRect(x: centre.x - 74, y: centre.y + 22, width: 14, height: 14))
        }
        return context.makeImage()
    }
}

/// One display link for the whole gallery, driving the previews on screen.
/// Made when the gallery opens and stopped when it closes.
@MainActor
final class GalleryClock: ObservableObject {
    private var previews: [ObjectIdentifier: WeakPreview] = [:]
    private var link: CADisplayLink?

    private struct WeakPreview { weak var view: GalleryPreview? }

    func add(_ preview: GalleryPreview) {
        previews[ObjectIdentifier(preview)] = WeakPreview(view: preview)
        guard link == nil, let screen = preview.window?.screen ?? NSScreen.main else { return }
        let link = screen.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func remove(_ preview: GalleryPreview) {
        previews[ObjectIdentifier(preview)] = nil
    }

    func stop() {
        link?.invalidate()
        link = nil
        previews = [:]
    }

    @objc private func step(_ link: CADisplayLink) {
        tickAll(at: link.targetTimestamp)
    }

    func tickAll(at time: Double) {
        for preview in previews.values.compactMap(\.view) { preview.tick(at: time) }
    }
}

/// A preview in SwiftUI, sharing the gallery's clock.
struct GalleryPreviewView: NSViewRepresentable {
    let kind: Cue.Kind
    let clock: GalleryClock

    func makeNSView(context: Context) -> GalleryPreview {
        let view = GalleryPreview(kind: kind)
        view.clock = clock
        return view
    }

    func updateNSView(_ view: GalleryPreview, context: Context) {}

    static func dismantleNSView(_ view: GalleryPreview, coordinator: ()) {
        view.clock?.remove(view)
    }
}
