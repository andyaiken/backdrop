import SwiftUI

/// Above the stage in the Studio: which cue it is, "Cue 1 · Decryption", and
/// Run again, with its key.
struct StageHeader: View {
    var number: String
    var kind: String
    var onRunAgain: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Cue \(number)").font(.system(size: 14, weight: .semibold, design: .monospaced))
            Text(kind).font(.system(size: 14)).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Button(action: onRunAgain) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Run again")
                    Keycap("R")
                }
            }
            .controlSize(.small)
            .focusable(false)
            .help("Runs the cue on the stage again from its start")
        }
        .frame(height: 24)
        // The rest of the header's height is a gap above the stage.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
