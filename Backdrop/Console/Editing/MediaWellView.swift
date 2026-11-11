import BackdropCore
import SwiftUI

/// The picture, clip or map a cue plays, as a well a file can be dropped on:
/// the file's name when it has one, and what to do when it has not.
struct MediaWellView: View {
    let path: String
    let kind: Cue.Kind
    let empty: String
    let onDrop: (URL) -> Void
    @State private var targeted = false

    private var hasFile: Bool { !path.isEmpty }
    private var text: String { hasFile ? (path as NSString).lastPathComponent : empty }

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(nsColor: targeted ? Desk.raised : Desk.sunk))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color(nsColor: targeted ? Desk.brass : Desk.lineBright), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            )
            .overlay(alignment: .leading) {
                Text(text)
                    .font(hasFile ? .system(size: 12, design: .monospaced) : .system(size: 12))
                    .foregroundStyle(Color(nsColor: hasFile ? Desk.text : Desk.dim))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
            }
            .contentShape(Rectangle())
            // The first file this kind of cue can use; others are ignored.
            .mediaDrop(isTargeted: $targeted, accepting: { [kind] in ShowDocument.accepts($0, for: kind) }) { urls in
                onDrop(urls[0])
            }
    }
}
