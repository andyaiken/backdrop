import AppKit

/// A warning that stays until it no longer applies: brass-edged, on the
/// right, above the preview.
final class WarningBox: PanelView {
    private let bar = PanelView(fill: Desk.brass)
    let text = Desk.label("", font: Desk.sans(12.5), colour: Desk.text, wraps: true)

    init() {
        super.init(fill: Desk.raised)
        addSubview(bar)
        addSubview(text)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func height(width: CGFloat) -> CGFloat {
        Desk.height(of: text, width: width - 24) + 20
    }

    override func layout() {
        super.layout()
        bar.frame = NSRect(x: 0, y: 0, width: 2, height: bounds.height)
        text.frame = NSRect(x: 12, y: 10, width: bounds.width - 24, height: bounds.height - 20)
    }
}
