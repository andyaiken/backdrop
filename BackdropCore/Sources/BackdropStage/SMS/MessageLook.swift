import AppKit
import BackdropCore

/// How a message bubble looks, shared by the single message and the
/// conversation: the colours, the type and the outline.
@MainActor
enum MessageLook {
    struct Palette {
        var screen: RGB
        var bubble: RGB
        var text: RGB
        /// The sender's name, and the typing dots.
        var quiet: RGB
    }

    static func palette(style: SMSStyle, dark: Bool, sent: Bool) -> Palette {
        let screen = dark ? RGB.black : RGB(255, 255, 255)
        switch (style, sent) {
        case (.blueBubbles, true):
            return Palette(screen: screen, bubble: RGB(0x0B, 0x84, 0xFE), text: RGB(255, 255, 255), quiet: RGB(0x8E, 0x8E, 0x93))
        case (.greenBubbles, true):
            return Palette(screen: screen, bubble: RGB(0x34, 0xC7, 0x59), text: RGB(255, 255, 255), quiet: RGB(0x8E, 0x8E, 0x93))
        case (.blueBubbles, false), (.greenBubbles, false):
            return dark
                ? Palette(screen: screen, bubble: RGB(0x26, 0x25, 0x2A), text: RGB(255, 255, 255), quiet: RGB(0x8E, 0x8E, 0x93))
                : Palette(screen: screen, bubble: RGB(0xE9, 0xE9, 0xEB), text: RGB(0, 0, 0), quiet: RGB(0x8E, 0x8E, 0x93))
        case (.greenRectangles, true):
            return dark
                ? Palette(screen: RGB(0x0B, 0x14, 0x1A), bubble: RGB(0x00, 0x5C, 0x4B), text: RGB(0xE9, 0xED, 0xEF), quiet: RGB(0x86, 0x96, 0xA0))
                : Palette(screen: RGB(0xEF, 0xEA, 0xE2), bubble: RGB(0xD9, 0xFD, 0xD3), text: RGB(0x11, 0x1B, 0x21), quiet: RGB(0x66, 0x77, 0x81))
        case (.greenRectangles, false):
            return dark
                ? Palette(screen: RGB(0x0B, 0x14, 0x1A), bubble: RGB(0x20, 0x2C, 0x33), text: RGB(0xE9, 0xED, 0xEF), quiet: RGB(0x86, 0x96, 0xA0))
                : Palette(screen: RGB(0xEF, 0xEA, 0xE2), bubble: RGB(0xFF, 0xFF, 0xFF), text: RGB(0x11, 0x1B, 0x21), quiet: RGB(0x66, 0x77, 0x81))
        case (.generic, true):
            return Palette(screen: screen, bubble: RGB(0x4F, 0x46, 0xE5), text: RGB(255, 255, 255), quiet: RGB(0x8A, 0x8D, 0x94))
        case (.generic, false):
            return dark
                ? Palette(screen: screen, bubble: RGB(0x3A, 0x3B, 0x40), text: RGB(0xE8, 0xE9, 0xEC), quiet: RGB(0x8A, 0x8D, 0x94))
                : Palette(screen: screen, bubble: RGB(0xE4, 0xE6, 0xEB), text: RGB(0x1C, 0x1E, 0x21), quiet: RGB(0x6B, 0x6E, 0x75))
        }
    }

    static func font(_ style: SMSStyle, size: CGFloat) -> CTFont {
        switch style {
        case .blueBubbles, .greenBubbles, .greenRectangles: NSFont.systemFont(ofSize: size, weight: .regular) as CTFont
        case .generic: StageFont.text(size: size)
        }
    }

    /// The bubble's outline: a rounded rectangle, with a tail at the bottom
    /// corner nearest the sender for blue and green bubbles, when `tail` says so.
    static func bubblePath(_ rect: CGRect, style: SMSStyle, sent: Bool, fontSize f: CGFloat, tail hasTail: Bool = true) -> CGPath {
        if style == .greenRectangles { return greenRectanglePath(rect, sent: sent, fontSize: f, tail: hasTail) }
        let radius = style.isRound ? min(rect.height / 2, f * 1.05) : min(rect.height / 2, f * 0.55)
        let path = CGMutablePath()
        path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        guard style.isRound, hasTail, rect.height > f else { return path }
        // The tail, drawn for the left and mirrored about the bubble for the
        // right. A mirror turns the outline round, so it is walked backwards
        // to keep the winding the rounded rectangle's, or the two cancel.
        func mirrored(_ point: CGPoint) -> CGPoint { sent ? CGPoint(x: rect.minX + rect.maxX - point.x, y: point.y) : point }
        let x = rect.minX, y = rect.minY
        let start = CGPoint(x: x + radius * 0.55, y: y + radius * 0.9)
        let tip = CGPoint(x: x - f * 0.22, y: y)
        let end = CGPoint(x: x + radius * 0.95, y: y + f * 0.02)
        let c1 = CGPoint(x: x + radius * 0.2, y: y + f * 0.12)
        let c2 = CGPoint(x: x + f * 0.2, y: y - f * 0.02)
        let tail = CGMutablePath()
        if sent {
            tail.move(to: mirrored(end))
            tail.addQuadCurve(to: mirrored(tip), control: mirrored(c2))
            tail.addQuadCurve(to: mirrored(start), control: mirrored(c1))
        } else {
            tail.move(to: start)
            tail.addQuadCurve(to: tip, control: c1)
            tail.addQuadCurve(to: end, control: c2)
        }
        tail.closeSubpath()
        path.addPath(tail)
        return path
    }

    /// A green rectangle: small corners, and for a bubble that starts a run a
    /// square top corner on the sender's side with a small tail beside it.
    private static func greenRectanglePath(_ rect: CGRect, sent: Bool, fontSize f: CGFloat, tail hasTail: Bool) -> CGPath {
        let r = min(rect.height / 2, f * 0.45)
        let square = hasTail && rect.height > f
        // The corner at the top on the sender's side.
        let tl = square && !sent ? 0 : r
        let tr = square && sent ? 0 : r
        let path = CGMutablePath()
        // Counterclockwise from the bottom left, the layers' way up.
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - tr, y: rect.maxY), radius: tr)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - tl), radius: tl)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        path.closeSubpath()
        guard square else { return path }
        let side: CGFloat = sent ? 1 : -1
        let edge = sent ? rect.maxX : rect.minX
        let tip = CGPoint(x: edge + side * f * 0.35, y: rect.maxY)
        let top = CGPoint(x: edge, y: rect.maxY)
        let down = CGPoint(x: edge, y: rect.maxY - f * 0.45)
        let notch = CGMutablePath()
        // Walked the same way round as the rectangle, which a mirror reverses.
        notch.move(to: tip)
        if sent {
            notch.addLine(to: top)
            notch.addLine(to: down)
        } else {
            notch.addLine(to: down)
            notch.addLine(to: top)
        }
        notch.closeSubpath()
        path.addPath(notch)
        return path
    }

    /// The height of a line of this font.
    static func lineHeight(_ font: CTFont) -> CGFloat {
        CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }
}
