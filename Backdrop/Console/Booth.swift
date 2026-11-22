import AppKit
import SwiftUI

/// The Booth's palette: show mode, always dark, whatever the Mac's
/// appearance, so the console never lights up the booth. Each colour turns to
/// its high-contrast value while Increase Contrast is on, from the next
/// time the console refreshes.
///
/// The Studio, edit mode, keeps `Desk`'s system colours. `Desk.room(_:)`
/// gives whichever the room uses.
enum Booth {
    static let background = colour(0x090D17, contrast: 0x000000)
    static let panel = colour(0x0F1524, contrast: 0x0B0F1A)
    static let raised = colour(0x161E33, contrast: 0x1A2238)
    static let line = colour(0x232C44, contrast: 0x5A6684)
    static let ink = colour(0xECE5D6, contrast: 0xFFFFFF)
    static let dim = colour(0x7F879C, contrast: 0xB8BFCE)
    /// What stands by next, and GO.
    static let brass = colour(0xDDB46A, contrast: 0xF2CC80)
    /// What is on stage, and stops.
    static let tally = colour(0xFF5040, contrast: 0xFF6A5C)
    /// The projector lamp, and Beginners rows that are fine. Nothing else.
    static let ok = colour(0x47C98B, contrast: 0x5FE0A0)
    /// Cautions.
    static let amber = colour(0xF5A623, contrast: 0xFFBE45)

    /// Whether the Booth draws in its high-contrast palette.
    @MainActor
    static var increasesContrast: Bool {
        #if DEBUG
        if let forcedContrast { return forcedContrast }
        #endif
        return NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    #if DEBUG
    /// Snapshots take the high-contrast Booth whatever this Mac is set to.
    @MainActor static var forcedContrast: Bool?
    #endif

    /// The appearance the Booth's window takes, so its controls, menus and
    /// sheets are dark too. Taking it also settles which palette the Booth's
    /// colours draw in.
    @MainActor
    static var appearance: NSAppearance? {
        drawsHighContrast = increasesContrast
        return NSAppearance(named: drawsHighContrast ? .accessibilityHighContrastDarkAqua : .darkAqua)
    }

    /// Which palette the colours draw in. Set on the main thread as the
    /// console applies its room; AppKit may resolve a colour on another
    /// thread, which only reads it.
    nonisolated(unsafe) private static var drawsHighContrast = false

    /// The high-contrast value while the Booth draws in high contrast.
    /// AppKit doesn't always hand a dynamic colour the high-contrast
    /// appearance the window was given, so the Booth's own setting decides.
    private static func colour(_ normal: UInt32, contrast: UInt32) -> NSColor {
        let plain = rgb(normal), strong = rgb(contrast)
        return NSColor(name: nil) { _ in drawsHighContrast ? strong : plain }
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The colours a part of the console draws with that is in both rooms, such
/// as the rail: the Booth's in show mode, and the Mac's own in edit mode.
struct Room {
    var background: NSColor
    var panel: NSColor
    var raised: NSColor
    var line: NSColor
    var ink: NSColor
    var dim: NSColor
    var brass: NSColor
    var tally: NSColor
    var ok: NSColor
    var amber: NSColor

    static let booth = Room(background: Booth.background, panel: Booth.panel, raised: Booth.raised, line: Booth.line,
                            ink: Booth.ink, dim: Booth.dim, brass: Booth.brass, tally: Booth.tally, ok: Booth.ok,
                            amber: Booth.amber)
    static let studio = Room(background: Desk.colour, panel: Desk.column, raised: Desk.raised, line: Desk.line,
                             ink: Desk.text, dim: Desk.dim, brass: Desk.brass, tally: .systemRed, ok: .systemGreen,
                             amber: .systemOrange)
}

extension Room {
    /// The same colours for SwiftUI.
    struct Colours {
        let room: Room
        var background: Color { Color(nsColor: room.background) }
        var panel: Color { Color(nsColor: room.panel) }
        var raised: Color { Color(nsColor: room.raised) }
        var line: Color { Color(nsColor: room.line) }
        var ink: Color { Color(nsColor: room.ink) }
        var dim: Color { Color(nsColor: room.dim) }
        var brass: Color { Color(nsColor: room.brass) }
        var tally: Color { Color(nsColor: room.tally) }
        var ok: Color { Color(nsColor: room.ok) }
        var amber: Color { Color(nsColor: room.amber) }
    }

    var colours: Colours { Colours(room: self) }
}
