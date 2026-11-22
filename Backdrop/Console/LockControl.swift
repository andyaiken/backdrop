import SwiftUI

/// Locking and unlocking the cue sheet, which is moving between the rooms.
///
/// In the Studio, one click on Lock for show goes to the Booth. In the Booth
/// the pill must be held for a second, with a ring filling as it is held, so
/// nothing in a performance unlocks the sheet by accident; letting go early
/// does nothing. VoiceOver can unlock at once, because a long press isn't
/// practical with it, which is no more than Show › Enter Edit Mode allows.
/// Neither face ever takes the keyboard.
struct LockControl: View {
    enum Face { case studio, booth }

    let face: Face
    var onLock: () -> Void = {}
    var onUnlock: () -> Void = {}

    @State private var pressing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let hold: Double = 1.0

    var body: some View {
        switch face {
        case .studio:
            Button("Lock for show", action: onLock)
                .buttonStyle(.borderedProminent)
                .focusable(false)
                .help("Locks the cue sheet and goes to the Booth, ready for the show")
        case .booth:
            pill
        }
    }

    private var pill: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().strokeBorder(Color(nsColor: Booth.line), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: pressing ? 1 : 0)
                    .stroke(Color(nsColor: Booth.brass), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1)
                    .animation(pressing ? .linear(duration: Self.hold) : .easeOut(duration: reduceMotion ? 0 : 0.15), value: pressing)
                Image(systemName: "lock.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(nsColor: Booth.ink))
            }
            .frame(width: 20, height: 20)
            Text("Locked for show")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: Booth.ink))
            Text("hold to edit")
                .font(.system(size: 12.5))
                .foregroundStyle(Color(nsColor: Booth.dim))
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(nsColor: Booth.panel)))
        .overlay(Capsule().strokeBorder(Color(nsColor: Booth.line)))
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: Self.hold, maximumDistance: 12, perform: onUnlock,
                            onPressingChanged: { pressing = $0 })
        .focusable(false)
        .help("Press and hold for a second to unlock the cue sheet for editing")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Locked for show")
        .accessibilityHint("Hold to unlock for editing")
        .accessibilityAction(named: "Unlock for editing", onUnlock)
    }
}
