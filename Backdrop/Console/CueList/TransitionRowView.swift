import AppKit
import BackdropCore

/// A cue's transition in, as a row above the cue it belongs to: "\u{2193} crossfade 0.5 s".
/// Edit mode shows one above every cue but the first. It is derived from the
/// cue, never stored, so it has no number and standing by never lands on it.
/// A click selects it, and the Inspector shows its settings; the right-click
/// menu puts a changed transition back to the standard fade. Console only: the
/// printed sheet has its own settings lines and never shows this.
final class TransitionRowView: NSView {
    let cue: UUID
    let note: String
    /// Whether it differs from the standard fade, and so can be cleared.
    let isChanged: Bool
    var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true } } }
    private var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    var onClick: (UUID) -> Void = { _ in }
    var onClear: (UUID) -> Void = { _ in }

    static let height: CGFloat = 18

    /// What the cue list says about a cue's transition in.
    static func note(for cue: Cue) -> String {
        let transition = cue.transition
        let length = SettingKey.fade.format(.number(transition.fadeMs))
        return switch transition.style {
        case .snap: "snap"
        case .fade: "fade " + length
        case .crossfade: "crossfade " + length
        case .wipe: "wipe from " + SettingKey.wipeFrom.format(.edge(transition.wipeFrom)) + " " + length
        }
    }

    init(cue: UUID, note: String, isChanged: Bool) {
        self.cue = cue
        self.note = note
        self.isChanged = isChanged
        super.init(frame: .zero)
        toolTip = "How the stage changes to this cue." + (isChanged ? " Right-click to put it back to the standard fade." : "")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected || isHovered {
            (isSelected ? Desk.selected : Desk.hover).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).fill()
        }
        // Selected as a standby cue is: the brass bar at the left, brass text.
        if isSelected {
            Desk.brass.setFill()
            NSRect(x: 0, y: 2, width: 2, height: bounds.height - 4).fill()
        }
        let colour = isChanged || isSelected ? Desk.brass : Desk.dim
        NSAttributedString(string: "\u{2193} " + note, attributes: [.font: Desk.sans(10.5), .foregroundColor: colour])
            .draw(in: NSRect(x: 78, y: 2, width: max(0, bounds.width - 88), height: 14))
    }

    override func mouseDown(with event: NSEvent) {
        onClick(cue)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard isChanged else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(title: "Clear Transition", action: #selector(clearPicked(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func clearPicked(_ item: NSMenuItem) {
        onClear(cue)
    }
}
