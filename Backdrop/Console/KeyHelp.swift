import AppKit
import SwiftUI

/// Every show key, over the console: ? shows it, and ?, Escape or any click
/// puts it away. It never takes the keyboard, so the show keys still work
/// while it shows, Space included.
@MainActor
final class KeyHelp: NSView {
    private let host = NSHostingView(rootView: KeyHelpView())

    init() {
        super.init(frame: .zero)
        addSubview(host)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    /// Room around the card for its shadow.
    private static let margin: CGFloat = 32

    /// The size it takes, its shadow included.
    var contentSize: NSSize {
        let card = host.fittingSize
        return NSSize(width: card.width + 2 * Self.margin, height: card.height + 2 * Self.margin)
    }

    override func layout() {
        super.layout()
        host.frame = bounds.insetBy(dx: Self.margin, dy: Self.margin)
    }

    /// Clicks pass through to the monitor that closes it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct KeyHelpView: View {
    private static let keys: [(keys: [String], meaning: String)] = [
        (["Space"], "Fire the next cue. Also while Go To is open"),
        (["\u{2192}", "\u{2193}", "Page Down"], "Stand by the next row"),
        (["\u{2190}", "\u{2191}", "Page Up"], "Stand by the previous row"),
        (["G"], "Go to a cue"),
        (["R"], "Run again"),
        (["B"], "Blackout"),
        (["?"], "All keys"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("KEYS")
                .font(.system(size: 11, weight: .semibold))
                .kerning(2)
                .foregroundStyle(Color(nsColor: Booth.brass))
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                ForEach(Self.keys, id: \.meaning) { row in
                    GridRow {
                        HStack(spacing: 5) {
                            ForEach(row.keys, id: \.self) { Keycap($0) }
                        }
                        Text(row.meaning)
                    }
                }
            }
            .foregroundStyle(Color(nsColor: Booth.ink))
            Text("Number keys do nothing on their own. Esc or ? closes this.")
                .foregroundStyle(Color(nsColor: Booth.dim))
        }
        .font(.system(size: 13))
        .padding(24)
        .fixedSize()
        .background(Color(nsColor: Booth.raised), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(nsColor: Booth.line)))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 6)
        .environment(\.colorScheme, .dark)
    }
}
