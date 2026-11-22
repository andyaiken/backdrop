import SwiftUI

/// The Booth's header: the show's title, the lock, and at the right any
/// cautions and the projector's lamp. Nothing else: if it doesn't need
/// seeing, it isn't shown. There is no GO here, nor a blackout button; the
/// GO plate and B do those.
struct BoothHeaderBar: View {
    @ObservedObject var state: HeaderState

    var body: some View {
        HStack(spacing: 16) {
            Text(state.title.uppercased())
                .font(.system(size: 14, weight: .semibold))
                .kerning(2.4)
                .foregroundStyle(Color(nsColor: Booth.ink))
                .lineLimit(1)
            LockControl(face: .booth, onUnlock: state.onUnlock)
            Spacer(minLength: 16)
            CautionLamps(cautions: state.cautions, selected: state.selectedCaution, room: .booth,
                         onSelect: state.onSelectCaution)
            HeaderBar(state: state).projector
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: Booth.panel))
        .overlay(alignment: .bottom) { Rectangle().fill(Color(nsColor: Booth.line)).frame(height: 1) }
        .coordinateSpace(name: HeaderBar.space)
    }
}
