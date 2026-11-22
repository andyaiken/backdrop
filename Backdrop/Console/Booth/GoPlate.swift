import SwiftUI

/// GO: a full-width brass plate, saying what GO will do. Clicking it fires
/// GO, as Space does. It never takes the keyboard, or Space would press it
/// as well as fire, and fire twice.
struct GoPlate: View {
    /// What GO will do, in the console's words: "Fire cue 5".
    var tip: String
    /// What follows: the steps it waits for, or what one GO runs.
    var then: String?
    /// MSC or OSC is on, so another machine can fire it too.
    var remote = false
    var enabled = true
    var onGo: () -> Void = {}

    var body: some View {
        Button(action: onGo) {
            HStack(spacing: 28) {
                Text("GO")
                    .font(.system(size: 64, weight: .black).width(.compressed))
                Text("SPACE")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .kerning(2)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tip).font(.system(size: 18, weight: .semibold))
                    if let then {
                        Text(then).font(.system(size: 15)).opacity(0.8)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 12)
                if remote {
                    Text("MSC AND OSC\nFIRE THIS TOO")
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(1.8)
                        .multilineTextAlignment(.trailing)
                        .opacity(0.7)
                }
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlateStyle())
        .disabled(!enabled)
        .focusable(false)
        .accessibilityLabel("GO: \(tip)")
    }
}

/// Brass, a shade darker while pressed, and dim at the end of the sheet.
private struct PlateStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(nsColor: Booth.background))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: Booth.brass))
                    .brightness(configuration.isPressed ? -0.12 : 0)
            )
            .opacity(isEnabled ? 1 : 0.35)
    }
}
