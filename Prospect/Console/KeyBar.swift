import AppKit
import SwiftUI

/// The keyboard reference along the bottom.
@MainActor
final class KeyBar: PanelHost<KeyBarView> {
    init() {
        super.init(rootView: KeyBarView())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct KeyBarView: View {
    private static let keys: [(key: String, meaning: String)] = [
        ("Space", "Fire the standby cue"),
        ("\u{2190} \u{2192}", "Stand by previous, next"),
        ("0\u{2013}9 \u{21A9}", "Go to a cue number"),
        ("R", "Run again"),
        ("B", "Blackout"),
    ]

    var body: some View {
        HStack(spacing: 22) {
            ForEach(Self.keys, id: \.key) { key, meaning in
                HStack(spacing: 7) {
                    Text(key)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    Text(meaning)
                }
            }
        }
        .font(.system(size: 12.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
