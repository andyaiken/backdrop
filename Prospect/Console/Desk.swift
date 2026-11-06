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
/// light appearance's colour after the Mac turned dark.
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
