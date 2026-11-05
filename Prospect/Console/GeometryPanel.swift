import AppKit
import ProspectCore

/// Edit mode's geometry controls: width, height and offsets as percentages
/// of the projector output, alignment guides, and a reset.
final class GeometryPanel: PanelView {
    private let heading = Desk.label("Projection area", font: Desk.sans(12.5, .semibold), colour: Desk.text)
    private var rows: [(label: NSTextField, slider: NSSlider, value: NSTextField)] = []
    let guides = NSButton(checkboxWithTitle: "Alignment guides", target: nil, action: nil)
    let fill = NSButton(title: "Fill the Output", target: nil, action: nil)
    private let note = Desk.label(
        "Percentages of the projector output, so they hold if the resolution changes. Guides switch themselves off in show mode.",
        font: Desk.sans(12), colour: Desk.dim, wraps: true)

    var onChange: (Geometry) -> Void = { _ in }
    private var geometry = Geometry()

    init() {
        super.init(border: Desk.line, radius: 4)
        addSubview(heading)
        let specs: [(String, ClosedRange<Int>)] = [
            ("Width", SettingRange.geometrySize), ("Height", SettingRange.geometrySize),
            ("Across", SettingRange.geometryOffset), ("Down", SettingRange.geometryOffset),
        ]
        for (name, range) in specs {
            let label = Desk.label(name, font: Desk.sans(12.5), colour: Desk.dim)
            let slider = NSSlider(value: 0, minValue: Double(range.lowerBound), maxValue: Double(range.upperBound),
                                  target: self, action: #selector(sliderMoved(_:)))
            // Sliders never take the keyboard, or the arrow keys would move
            // them instead of the standby cue.
            slider.refusesFirstResponder = true
            slider.isContinuous = true
            let value = Desk.label("", font: Desk.mono(12), colour: Desk.dim)
            value.alignment = .right
            for view in [label, slider, value] as [NSView] { addSubview(view) }
            rows.append((label, slider, value))
        }
        guides.refusesFirstResponder = true
        fill.refusesFirstResponder = true
        fill.bezelStyle = .rounded
        fill.target = self
        fill.action = #selector(fillOutput)
        for view in [guides, fill, note] as [NSView] { addSubview(view) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(geometry: Geometry, guidesOn: Bool) {
        self.geometry = geometry
        let values = [geometry.width, geometry.height, geometry.across, geometry.down]
        for (i, row) in rows.enumerated() {
            row.slider.integerValue = values[i]
            row.value.stringValue = i < 2 ? "\(values[i])%" : String(format: "%+d%%", values[i]).replacingOccurrences(of: "+0", with: "0")
        }
        guides.state = guidesOn ? .on : .off
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        guard let i = rows.firstIndex(where: { $0.slider === sender }) else { return }
        var g = geometry
        switch i {
        case 0: g.width = sender.integerValue
        case 1: g.height = sender.integerValue
        case 2: g.across = sender.integerValue
        default: g.down = sender.integerValue
        }
        onChange(g)
    }

    @objc private func fillOutput() {
        onChange(Geometry())
    }

    var preferredHeight: CGFloat {
        15 + 18 + 11 + CGFloat(rows.count) * 31 + 6 + 28 + 10 + 34 + 15
    }

    override func layout() {
        super.layout()
        let x: CGFloat = 16, inner = bounds.width - 32
        var y: CGFloat = 15
        heading.frame = NSRect(x: x, y: y, width: inner, height: 18); y += 29
        for row in rows {
            row.label.frame = NSRect(x: x, y: y + 3, width: 84, height: 18)
            row.slider.frame = NSRect(x: x + 92, y: y, width: inner - 92 - 64, height: 24)
            row.value.frame = NSRect(x: x + inner - 56, y: y + 3, width: 56, height: 18)
            y += 31
        }
        y += 6
        guides.frame = NSRect(x: x, y: y + 4, width: guides.fittingSize.width, height: 20)
        let fillWidth = fill.fittingSize.width
        fill.frame = NSRect(x: guides.frame.maxX + 16, y: y, width: fillWidth, height: 28)
        y += 38
        note.frame = NSRect(x: x, y: y, width: inner, height: Desk.height(of: note, width: inner))
    }
}
