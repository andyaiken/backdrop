import AppKit
import BackdropCore
import QuartzCore

/// Text cues: some words in a chosen font and colour on a background, wrapped
/// to the picture, placed top, middle or bottom of it and aligned left,
/// centre or right across it. Instant, so
/// it skips the hold.
///
/// The size isn't the cue's to set: it follows the picture's height and the
/// show's text size, as decryption and anagram text does.
@MainActor
public final class TextRenderer: CueRenderer, ReportsProblems {
    public let isInstant = true
    public var onProblem: ((String) -> Void)?

    private var content: TextContent?
    private var textScale = 100
    private var layers: [ObjectIdentifier: QuietTextLayer] = [:]
    private var fills: [ObjectIdentifier: StillLayer] = [:]

    /// How tall a line is against the picture, before the show's text size.
    static let heightFraction: CGFloat = 0.09
    /// The space left at each side, against the picture's width.
    static let marginFraction: CGFloat = 0.08

    public init() {}

    final class QuietTextLayer: CATextLayer {
        override func action(forKey event: String) -> (any CAAction)? { nil }
    }

    // MARK: CueRenderer

    public func mount(on surface: SurfaceLayer) {
        let fill = StillLayer()
        fill.isHidden = true
        fills[ObjectIdentifier(surface)] = fill
        surface.inset.addSublayer(fill)
        let layer = QuietTextLayer()
        layer.isHidden = true
        layer.isWrapped = true
        layer.truncationMode = .none
        layer.contentsScale = max(surface.contentsScale, 1)
        layers[ObjectIdentifier(surface)] = layer
        surface.inset.addSublayer(layer)
        apply(to: layer)
        fit(surface)
    }

    public func unmount(from surface: SurfaceLayer) {
        surfaces.removeValue(forKey: ObjectIdentifier(surface))
        fills.removeValue(forKey: ObjectIdentifier(surface))?.removeFromSuperlayer()
        layers.removeValue(forKey: ObjectIdentifier(surface))?.removeFromSuperlayer()
    }

    public func setVisible(_ visible: Bool, on surface: SurfaceLayer) {
        layers[ObjectIdentifier(surface)]?.isHidden = !visible
        fills[ObjectIdentifier(surface)]?.isHidden = !visible
    }

    public func clear(_ surface: SurfaceLayer) {
        content = nil
        layers[ObjectIdentifier(surface)]?.string = nil
        fills[ObjectIdentifier(surface)]?.backgroundColor = RGB.black.cgColor
    }

    public func prepare(_ cue: Cue, show: ShowSettings) {
        guard case .text(let content) = cue.content else { return }
        self.content = content
        textScale = show.textScale
        if !content.font.isEmpty, !StageFont.has(family: content.font) {
            let name = cue.number.isEmpty ? "This text" : "Cue \(cue.number)"
            onProblem?("\(name)\u{2019}s font, \(content.font), isn\u{2019}t on this Mac, so it shows in \(SettingKey.stageFont) instead.")
        }
        for (id, layer) in layers {
            fills[id]?.backgroundColor = content.background.cgColor
            apply(to: layer)
            if let surface = surfaces[id] { fit(surface) }
        }
    }

    public func settingsChanged(_ show: ShowSettings) {
        guard show.textScale != textScale else { return }
        textScale = show.textScale
        for surface in surfaces.values { fit(surface) }
    }

    public func frame(_ f: Int) -> Bool { true }

    public func fit(_ surface: SurfaceLayer) {
        guard let layer = layers[ObjectIdentifier(surface)] else { return }
        surfaces[ObjectIdentifier(surface)] = surface
        let bounds = surface.inset.bounds
        fills[ObjectIdentifier(surface)]?.frame = bounds
        guard let content, bounds.width > 0, bounds.height > 0 else { return }
        let size = max(8, bounds.height * Self.heightFraction * CGFloat(textScale) / 100)
        let font = StageFont.anagram(family: content.font, size: size)
        layer.font = font
        layer.fontSize = size
        let width = bounds.width * (1 - 2 * Self.marginFraction)
        let measured = NSAttributedString(string: content.text, attributes: [.font: font as NSFont])
            .boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading])
        let height = min(ceil(measured.height), bounds.height)
        // Layers count up from the bottom.
        let margin = bounds.width * Self.marginFraction
        let y: CGFloat = switch content.vertical {
        case .top: bounds.height - height - margin
        case .middle: (bounds.height - height) / 2
        case .bottom: margin
        }
        layer.frame = CGRect(x: bounds.width * Self.marginFraction, y: max(0, y).rounded(), width: width, height: height)
        layer.contentsScale = max(surface.contentsScale, 1)
    }

    // MARK: Painting

    /// Surfaces by layer, so a cue arriving can refit each one.
    private var surfaces: [ObjectIdentifier: SurfaceLayer] = [:]

    private func apply(to layer: QuietTextLayer) {
        guard let content else { return }
        layer.string = content.text
        layer.foregroundColor = content.colour.cgColor
        layer.alignmentMode = switch content.alignment {
        case .left: .left
        case .centre: .center
        case .right: .right
        }
    }
}
