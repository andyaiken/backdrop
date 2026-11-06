import ProspectCore
import QuartzCore

/// Anywhere cues are painted: the projector's output, or the console's live
/// preview. Renderers never know which, except that a surface carries its
/// role for the one renderer that needs it.
///
/// A surface is a black layer filling the output, holding an inset layer
/// sized by the show's percentage geometry. Renderers mount into the inset
/// and measure it, never the output. Everything outside the inset stays
/// black, because anything else is light spilling onto the set.
public final class SurfaceLayer: StillLayer {
    public enum Role: Sendable {
        case live
        case preview
    }

    public let role: Role
    /// Where the picture lands. Renderers add their layers here.
    public let inset = StillLayer()

    public var geometry = Geometry() {
        didSet { updateInset() }
    }

    /// A focusing aid: a frame round the inset and a cross through its
    /// centre, in brass. Only ever on in edit mode.
    public var showsGuides = false {
        didSet { guides.isHidden = !showsGuides }
    }

    private let guides = GuidesLayer()

    /// Black over the picture while one cue gives way to the next: clear at
    /// 0, black at 1. Separate from blackout, which fades the inset itself.
    public var curtain = 0.0 {
        didSet { curtainLayer.opacity = Float(curtain) }
    }

    private let curtainLayer = StillLayer()

    /// The cue that was on stage, as a still picture, over the one that is
    /// there now: 1 is all of it, 0 is none. A crossfade fades it out.
    public var dissolve = 0.0 {
        didSet {
            dissolveLayer.opacity = Float(dissolve)
            if dissolve <= 0 { dissolveLayer.contents = nil }
        }
    }

    private let dissolveLayer = StillLayer()

    /// The picture the inset shows now, for a crossfade to fade out. Taken
    /// from the layers themselves, which cannot see a Metal layer; a renderer
    /// that draws on one hands over its own image instead (see `Snapshots`).
    public func snapshot(replacing own: CGImage? = nil) -> CGImage? {
        if let own { return own }
        let scale = max(contentsScale, 1)
        let w = Int((inset.bounds.width * scale).rounded()), h = Int((inset.bounds.height * scale).rounded())
        guard w > 0, h > 0, let context = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        // Guides are a focusing aid, not part of the picture.
        let guidesHidden = guides.isHidden
        guides.isHidden = true
        // Drawn layers may not have been asked for their pixels yet.
        func display(_ layer: CALayer) {
            layer.displayIfNeeded()
            layer.sublayers?.forEach(display)
        }
        display(inset)
        renderStacked(inset, in: context)
        guides.isHidden = guidesHidden
        return context.makeImage()
    }

    /// Draws a layer into a bitmap with the inset's sublayers stacked by
    /// zPosition. The screen honours it, but `render(in:)` draws in array
    /// order, which would put the curtain under the picture it covers.
    func renderStacked(_ layer: CALayer, in context: CGContext) {
        let original = inset.sublayers
        inset.sublayers = original?.enumerated().sorted { ($0.element.zPosition, $0.offset) < ($1.element.zPosition, $1.offset) }.map(\.element)
        layer.render(in: context)
        inset.sublayers = original
    }

    /// Puts a picture under the curtain at full strength, to fade out.
    public func startDissolve(from image: CGImage?) {
        dissolveLayer.contents = image
        dissolve = image == nil ? 0 : 1
    }

    /// How long blackout takes to fade.
    public static let blackoutDuration: CFTimeInterval = 0.4

    public init(role: Role) {
        self.role = role
        super.init()
        backgroundColor = CGColor(gray: 0, alpha: 1)
        masksToBounds = true
        inset.masksToBounds = true
        addSublayer(inset)
        // Above anything a renderer adds, however its layers are stacked in
        // depth, with the guides above that.
        curtainLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
        curtainLayer.opacity = 0
        curtainLayer.zPosition = 1000
        inset.addSublayer(curtainLayer)
        dissolveLayer.opacity = 0
        dissolveLayer.zPosition = 900
        dissolveLayer.contentsGravity = .resize
        inset.addSublayer(dissolveLayer)
        guides.isHidden = true
        guides.zPosition = 2000
        inset.addSublayer(guides)
    }

    override public init(layer: Any) {
        role = (layer as? SurfaceLayer)?.role ?? .preview
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Places the inset within the output by the geometry. Call after the
    /// surface's bounds change.
    public func updateInset() {
        inset.frame = geometry.insetRect(in: bounds.size).flipped(within: bounds.height)
        curtainLayer.frame = inset.bounds
        dissolveLayer.frame = inset.bounds
        guides.frame = inset.bounds
        guides.layoutLines()
    }

    /// Fades the picture out or back in. The output stays black either way.
    public func setBlackout(_ on: Bool, animated: Bool) {
        let target: Float = on ? 0 : 1
        guard inset.opacity != target else { return }
        let from = inset.presentation()?.opacity ?? inset.opacity
        inset.opacity = target
        guard animated else {
            inset.removeAnimation(forKey: "blackout")
            return
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = target
        fade.duration = Self.blackoutDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        inset.add(fade, forKey: "blackout")
    }
}

/// The alignment guides: a 1-point frame, and lines through the centre.
final class GuidesLayer: StillLayer {
    private let horizontal = StillLayer()
    private let vertical = StillLayer()

    override init() {
        super.init()
        borderColor = Palette.brass.cgColor(alpha: 0.55)
        borderWidth = 1
        for line in [horizontal, vertical] {
            line.backgroundColor = Palette.brass.cgColor(alpha: 0.3)
            addSublayer(line)
        }
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func layoutLines() {
        let line: CGFloat = 1
        vertical.frame = CGRect(x: bounds.midX - line / 2, y: 0, width: line, height: bounds.height)
        horizontal.frame = CGRect(x: 0, y: bounds.midY - line / 2, width: bounds.width, height: line)
    }
}
