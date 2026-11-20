import AppKit

/// The desk palette: the Mac's own colours, named for what they are used
/// for. They follow the system appearance and the user's accent colour, so
/// the console looks like every other app on the machine.
///
/// The stage keeps a palette of its own, in `Palette`: that one is the
/// projected picture, not the interface, and never changes with the Mac.
enum Desk {
    static let colour = NSColor.windowBackgroundColor
    /// A row that stands out: the live cue, the one standing by.
    static let raised = NSColor.unemphasizedSelectedContentBackgroundColor
    static let sunk = NSColor.underPageBackgroundColor
    static let line = NSColor.separatorColor
    static let lineBright = NSColor.tertiaryLabelColor
    static let text = NSColor.labelColor
    static let dim = NSColor.secondaryLabelColor
    /// What the operator's eye goes to: standby, and anything live.
    static let brass = NSColor.controlAccentColor
    static let live = NSColor.systemGreen
    /// A cue list row under the pointer, and a selected one: the system's
    /// own tints, so they follow the accent colour and light or dark mode.
    static let hover = NSColor.quaternaryLabelColor
    /// Strong enough to stand out against `column`, the tint it sits on.
    static let selected = NSColor.controlAccentColor.withAlphaComponent(0.2)
    /// The header and the key bar: the window's background with a little of
    /// the accent in it, so the console's edges aren't the same white as
    /// its desk.
    static let bar = tinted(light: 0.09, dark: 0.10)
    /// Behind the cue list and the Inspector: a fainter wash of the same.
    /// The previews' column between them stays plain.
    static let column = tinted(light: 0.05, dark: 0.05)
    /// The corners of the previews.
    static let previewRadius: CGFloat = 10

    /// The window's background with some of the accent mixed in, worked out
    /// afresh for each appearance and accent colour. With Increase Contrast
    /// on, it is the plain background: a tint would only soften the edges
    /// the user asked to be sharper.
    private static func tinted(light: CGFloat, dark: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            let fraction: CGFloat = switch appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) {
            case .aqua?: light
            case .darkAqua?: dark
            default: 0
            }
            var colour = NSColor.windowBackgroundColor
            appearance.performAsCurrentDrawingAppearance {
                guard let base = NSColor.windowBackgroundColor.usingColorSpace(.sRGB),
                      let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return }
                colour = base.blended(withFraction: fraction, of: accent) ?? base
            }
            return colour
        }
    }

    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func sans(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    @MainActor
    static func label(_ text: String = "", font: NSFont = sans(12.5), colour: NSColor = Desk.text, wraps: Bool = false) -> NSTextField {
        let field = wraps ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        field.font = font
        field.textColor = colour
        field.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        return field
    }

    /// The width of the tab down a cue list row's left edge, in the room the
    /// cue number leaves.
    static let tabWidth: CGFloat = 10

    /// The tab down the left edge of a cue list row that is live or next,
    /// clipped to the row's rounded corners, with its label reading up it.
    /// On a row too short for the label, the tab alone has to say it.
    @MainActor
    static func drawTab(_ label: String?, fill: NSColor, ink: NSColor, in box: NSRect, radius: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).addClip()
        fill.setFill()
        NSRect(x: box.minX, y: box.minY, width: tabWidth, height: box.height).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let label else { return }
        let font = sans(7.5, .bold)
        let text = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: ink, .kern: 0.3])
        let length = text.size().width
        guard length <= box.height - 6 else { return }
        NSGraphicsContext.saveGraphicsState()
        // Turned a quarter anticlockwise, about the tab's middle, so it reads
        // from the bottom up. The view is flipped, so that's -90°.
        let turn = NSAffineTransform()
        turn.translateX(by: box.minX + tabWidth / 2, yBy: box.midY)
        turn.rotate(byDegrees: -90)
        turn.concat()
        // Centred on its capitals, as the cue number is.
        text.draw(at: NSPoint(x: -length / 2, y: font.capHeight / 2 - font.ascender))
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The height a label needs at a width.
    @MainActor
    static func height(of field: NSTextField, width: CGFloat) -> CGFloat {
        guard !field.stringValue.isEmpty else { return 0 }
        return ceil(field.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height)
    }
}

/// A plain view with a fill, and optionally a border.
///
/// The colours are kept, not their `CGColor`s: a `CGColor` is the colour as
/// it stood when it was taken, so a view that cached one would keep the
/// light appearance's colour after the Mac turned dark, or the old accent
/// after the user picked another.
class PanelView: NSView {
    private let fill: NSColor?
    private let border: NSColor?

    init(fill: NSColor? = nil, border: NSColor? = nil, radius: CGFloat = 0) {
        self.fill = fill
        self.border = border
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderWidth = border == nil ? 0 : 1
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        applyColours()
        NotificationCenter.default.addObserver(self, selector: #selector(systemColoursChanged),
                                               name: NSColor.systemColorsDidChangeNotification, object: nil)
    }

    @objc private func systemColoursChanged() {
        applyColours()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColours()
        needsDisplay = true
    }

    private func applyColours() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fill?.cgColor
            layer?.borderColor = border?.cgColor
        }
    }
}

extension String {
    /// Nil for an empty string, as a tooltip with nothing to say.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
