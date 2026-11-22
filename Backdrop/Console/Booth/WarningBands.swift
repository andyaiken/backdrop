import AppKit
import BackdropStage
import SwiftUI

/// Stops: a red band across the console for each, under the header, most
/// urgent first. They stay until the condition clears.
@MainActor
final class StopBands: PanelHost<StopBandsView> {
    var stops: [BoothWarning] = [] {
        didSet {
            guard stops != oldValue else { return }
            rootView = StopBandsView(stops: stops)
        }
    }

    /// Given exactly the height it measures, so the wrapped text never
    /// spills over what is below.
    init() {
        super.init(rootView: StopBandsView(stops: []), fills: true)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct StopBandsView: View {
    let stops: [BoothWarning]

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(stops.enumerated()), id: \.offset) { _, stop in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("STOP")
                        .font(.system(size: 13, weight: .black).width(.compressed))
                        .kerning(1)
                        .foregroundStyle(Color(nsColor: Booth.tally))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(.white))
                    Text(stop.message)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(nsColor: Booth.tally))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// The caution line under the header: one caution's message, the one
/// whose lamp was clicked or else the most urgent, in a single amber line.
@MainActor
final class CautionLine: NSView {
    private let label = NSTextField(labelWithString: "")

    static let height: CGFloat = 30

    var caution: BoothWarning? {
        didSet {
            label.stringValue = caution?.message ?? ""
            label.toolTip = caution?.message
            isHidden = caution == nil
            needsDisplay = true
        }
    }

    init() {
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = Booth.amber
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let h = label.intrinsicContentSize.height
        label.frame = NSRect(x: 44, y: (bounds.height - h) / 2, width: max(0, bounds.width - 64), height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        Booth.amber.withAlphaComponent(0.12).setFill()
        bounds.fill()
        Booth.amber.withAlphaComponent(0.5).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        // A small warning mark at the start of the line.
        if let mark = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold).applying(.init(paletteColors: [Booth.amber]))) {
            let s = mark.size
            mark.draw(in: NSRect(x: 20, y: (bounds.height - s.height) / 2, width: s.width, height: s.height),
                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}
