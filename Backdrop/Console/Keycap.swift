import AppKit
import SwiftUI

/// A key, drawn as the console names keys everywhere: a rounded outline in
/// the current ink, with the key's name in small monospaced type.
struct Keycap: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    static let fontSize: CGFloat = 11.5
    static let radius: CGFloat = 5

    var body: some View {
        Text(key)
            .font(.system(size: Self.fontSize, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .frame(minWidth: 20)
            .overlay(RoundedRectangle(cornerRadius: Self.radius).strokeBorder(.foreground, lineWidth: 1))
    }
}

extension Keycap {
    /// The font a drawn keycap uses.
    static var font: NSFont { .monospacedSystemFont(ofSize: fontSize, weight: .regular) }

    /// The size a drawn keycap takes.
    static func size(of key: String) -> NSSize {
        let text = (key as NSString).size(withAttributes: [.font: font])
        return NSSize(width: max(20, ceil(text.width) + 12), height: ceil(text.height) + 3)
    }

    /// Draws a keycap into the current AppKit context, centred in `rect`,
    /// in `ink`.
    @MainActor
    static func draw(_ key: String, in rect: NSRect, ink: NSColor) {
        let size = size(of: key)
        let box = NSRect(x: (rect.midX - size.width / 2).rounded(), y: (rect.midY - size.height / 2).rounded(),
                         width: size.width, height: size.height)
        ink.setStroke()
        let outline = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        outline.lineWidth = 1
        outline.stroke()
        let text = NSAttributedString(string: key, attributes: [.font: font, .foregroundColor: ink])
        let textSize = text.size()
        text.draw(at: NSPoint(x: box.midX - textSize.width / 2, y: box.midY - textSize.height / 2))
    }
}
