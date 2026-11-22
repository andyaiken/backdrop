import SwiftUI

/// The keys, in one line under the GO plate. ? shows them all.
struct KeyRow: View {
    var body: some View {
        HStack(spacing: 26) {
            HStack(spacing: 6) {
                Keycap("\u{2190}")
                Keycap("\u{2192}")
                Text("stand by previous or next")
            }
            item("G", "go to a cue")
            item("B", "blackout")
            item("?", "all keys")
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .foregroundStyle(Color(nsColor: Booth.dim))
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func item(_ key: String, _ meaning: String) -> some View {
        HStack(spacing: 6) {
            Keycap(key)
            Text(meaning)
        }
    }
}
