import AppKit
import ProspectCore
import ProspectStage

/// What GO fires next, large; what is on screen, small.
final class StandbyPanel: PanelView {
    private let standingBy = Desk.label("Standing by", font: Desk.sans(11.5), colour: Desk.dim)
    private let number = Desk.label("\u{2014}", font: Desk.mono(30), colour: Desk.brass)
    private let name = Desk.label("\u{2014}", font: Desk.mono(13), colour: Desk.text)
    private let arm = Desk.label("", font: Desk.sans(11.5, .medium), colour: Desk.dim)
    private let cuePointBox = PanelView(fill: Desk.raised)
    private let cuePointBar = PanelView(fill: Desk.brass)
    private let cuePoint = Desk.label("", font: Desk.sans(13), colour: Desk.text, wraps: true)
    private let divider = PanelView(fill: Desk.line)
    private let onScreen = Desk.label("On screen", font: Desk.sans(11.5), colour: Desk.dim)
    private let liveNumber = Desk.label("\u{2014}", font: Desk.mono(17), colour: Desk.dim)
    private let liveName = Desk.label("\u{2014}", font: Desk.mono(12), colour: Desk.dim)

    init() {
        super.init(fill: Desk.sunk)
        name.alignment = .right
        liveName.alignment = .right
        cuePointBox.addSubview(cuePointBar)
        cuePointBox.addSubview(cuePoint)
        arm.alignment = .right
        for view in [standingBy, number, name, arm, cuePointBox, divider, onScreen, liveNumber, liveName] as [NSView] { addSubview(view) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// For a video cue standing by: whether it is armed, said plainly. While
    /// the live cue waits partway, its GO point stands by in the cue's place.
    func update(standby: Cue?, live: Cue?, goPoint: ShowController.StandingByGoPoint?, entry: String, arm armState: ArmState?) {
        switch armState {
        case .armed:
            arm.stringValue = "Video armed"
            arm.textColor = Desk.live
        case .arming:
            arm.stringValue = "Video loading \u{2014} not armed yet"
            arm.textColor = Desk.brass
        case .failed:
            arm.stringValue = "No clip \u{2014} this cue goes to black"
            arm.textColor = Desk.brass
        case nil:
            arm.stringValue = ""
        }
        if !entry.isEmpty {
            standingBy.stringValue = "Go to \u{2014} Return stands it by, Escape clears"
            number.stringValue = entry + "\u{2581}"
            name.stringValue = ""
        } else if let goPoint {
            standingBy.stringValue = "Standing by \u{2014} \(goPoint.point.unit.rawValue) \(goPoint.number) of \(goPoint.count)"
            number.stringValue = goPoint.cue.number
            name.stringValue = goPoint.point.text
        } else {
            standingBy.stringValue = "Standing by"
            number.stringValue = standby?.number ?? "\u{2014}"
            name.stringValue = standby.map { $0.text.isEmpty ? "\u{2014}" : $0.text } ?? "end of sheet"
        }
        let line = goPoint == nil ? standby?.line.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" : ""
        if let goPoint {
            // No cue point of its own: what GO does here, and how to skip it.
            let after = standby.map { "cue \($0.number)" } ?? "the end of the sheet"
            cuePoint.stringValue = "GO carries cue \(goPoint.cue.number) on. \u{2192} skips to \(after)."
        } else {
            cuePoint.stringValue = !line.isEmpty ? line : (standby == nil ? "Nothing to stand by for" : "No cue point set")
        }
        cuePoint.textColor = line.isEmpty ? Desk.dim : Desk.text
        cuePoint.font = line.isEmpty ? NSFontManager.shared.convert(Desk.sans(13), toHaveTrait: .italicFontMask) : Desk.sans(13)
        cuePointBar.layer?.backgroundColor = (line.isEmpty ? Desk.line : Desk.brass).cgColor
        liveNumber.stringValue = live?.number ?? "\u{2014}"
        liveName.stringValue = live?.text ?? "\u{2014}"
        needsLayout = true
    }

    /// The height the panel needs at a width.
    func height(width: CGFloat) -> CGFloat {
        let inner = width - 32
        return 15 + 16 + 2 + 36 + 10 + (arm.stringValue.isEmpty ? 0 : 18)
            + (Desk.height(of: cuePoint, width: inner - 22) + 18) + 12 + 1 + 12 + 16 + 2 + 22 + 15
    }

    override func layout() {
        super.layout()
        let x: CGFloat = 16, inner = bounds.width - 32
        var y: CGFloat = 15
        standingBy.frame = NSRect(x: x, y: y, width: inner, height: 16); y += 18
        number.frame = NSRect(x: x, y: y, width: inner * 0.5, height: 36)
        name.frame = NSRect(x: x + inner * 0.35, y: y + 14, width: inner * 0.65, height: 18); y += 46
        arm.isHidden = arm.stringValue.isEmpty
        if !arm.isHidden {
            arm.frame = NSRect(x: x, y: y - 6, width: inner, height: 16)
            y += 18
        }
        let textHeight = Desk.height(of: cuePoint, width: inner - 22)
        cuePointBox.frame = NSRect(x: x, y: y, width: inner, height: textHeight + 18)
        cuePointBar.frame = NSRect(x: 0, y: 0, width: 2, height: textHeight + 18)
        cuePoint.frame = NSRect(x: 11, y: 9, width: inner - 22, height: textHeight); y += textHeight + 18 + 12
        divider.frame = NSRect(x: x, y: y, width: inner, height: 1); y += 13
        onScreen.frame = NSRect(x: x, y: y, width: inner, height: 16); y += 18
        liveNumber.frame = NSRect(x: x, y: y, width: inner * 0.4, height: 22)
        liveName.frame = NSRect(x: x + inner * 0.3, y: y + 4, width: inner * 0.7, height: 16)
    }
}
