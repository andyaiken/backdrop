import BackdropCore
import SwiftUI

/// Under the timeline: how the stage changes into the next cue, which can
/// be clicked to edit that transition. "Into cue 2 · Dusk  fade 0.5 s".
struct JoinLine: View {
    var into: Cue?
    var selected = false
    var onClick: () -> Void = {}

    var body: some View {
        if let into {
            Button(action: onClick) {
                HStack(spacing: 10) {
                    Text("Into cue \(into.number) \u{00B7} \(CueText.name(into))")
                    Text(CueText.transitionNote(into))
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    Text("Click to change.").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            Color.clear
        }
    }
}
