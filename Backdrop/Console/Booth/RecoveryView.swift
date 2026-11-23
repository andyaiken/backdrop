import AppKit
import SwiftUI

/// After a crash mid-show: the cue that was on stage, as it finished, and
/// the choice to put it straight back or start again. It replaces the alert
/// and does what it did: Resume reopens the projector and puts the cue back,
/// finished, with the cue after it up next.
struct RecoveryView: View {
    let number: String
    let name: String
    /// When the cue fired, as a short time in the user's locale.
    let firedAt: Date
    let picture: CGImage?
    var onResume: () -> Void = {}
    var onStartOver: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Backdrop stopped unexpectedly during the show.")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(nsColor: Booth.ink))
            ZStack {
                Color.black
                if let picture {
                    Image(decorative: picture, scale: 1).resizable().aspectRatio(contentMode: .fit)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(nsColor: Booth.tally), lineWidth: 2))
            Text("The last cue fired was \(Text("cue \(number) \u{00B7} \(name)").bold()), at \(firedAt.formatted(date: .omitted, time: .shortened)). Resuming puts it straight back on the projector, finished, with the cue after it up next.")
                .font(.system(size: 14))
                .foregroundStyle(Color(nsColor: Booth.dim))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Spacer()
                Button("Start from the Top", action: onStartOver)
                    .keyboardShortcut(.cancelAction)
                Button("Resume at Cue \(number)", action: onResume)
                    .keyboardShortcut(.defaultAction)
                    .tint(Color(nsColor: Booth.brass))
            }
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 560)
        .background(Color(nsColor: Booth.panel))
        .environment(\.colorScheme, .dark)
    }
}
