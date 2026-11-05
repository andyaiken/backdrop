import AppKit

/// The desk palette, for everything around the stage.
enum Desk {
    static let colour = rgb(0x14, 0x16, 0x1B)
    static let raised = rgb(0x1B, 0x1E, 0x25)
    static let sunk = rgb(0x0C, 0x0E, 0x12)
    static let line = rgb(0x27, 0x2C, 0x35)
    static let lineBright = rgb(0x3A, 0x41, 0x4E)
    static let text = rgb(0xCF, 0xD4, 0xDE)
    static let dim = rgb(0x76, 0x7E, 0x8D)
    static let brass = rgb(0xC8, 0xA2, 0x4A)
    static let live = rgb(0x6F, 0xB5, 0x8A)

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
class PanelView: NSView {
    init(fill: NSColor? = nil, border: NSColor? = nil, radius: CGFloat = 0) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = fill?.cgColor
        layer?.borderColor = border?.cgColor
        layer?.borderWidth = border == nil ? 0 : 1
        layer?.cornerRadius = radius
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
}

extension String {
    /// Nil for an empty string, as a tooltip with nothing to say.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
