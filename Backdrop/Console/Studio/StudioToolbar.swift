import BackdropCore
import SwiftUI

/// One issue in the cue sheet, as the sheet health popover lists it.
struct SheetHealthIssue: Identifiable, Equatable {
    let id: Int
    let cue: UUID?
    let message: String
}

/// The Studio's toolbar: Lock for show, Add cue, Stage setup and, when the
/// sheet has any, its issues; then any cautions and the projector, with a
/// small live picture of what it shows. The show's name and whether it is
/// edited are in the title bar above.
///
/// Nothing here takes the keyboard, so the show keys still reach the show.
struct StudioToolbar: View {
    @ObservedObject var state: HeaderState
    @State private var showingIssues = false

    var body: some View {
        HStack(spacing: 10) {
            LockControl(face: .studio, onLock: state.onLock)

            Button { state.onShowAddCue() } label: {
                HStack(spacing: 6) {
                    Text("+ Add cue")
                }
            }
            .sheet(isPresented: $state.showingAddCue, onDismiss: { state.onGalleryClosed() }) {
                CueGallery(place: state.galleryPlace) { kind in
                    state.showingAddCue = false
                    if let kind { state.onAddCue(kind) }
                }
            }
            .fixedSize()
            .focusable(false)
            .help("Adds a cue after the one marked Next")

            Toggle("Stage setup", isOn: Binding(get: { state.stageSetupOn }, set: { state.onStageSetup($0) }))
                .toggleStyle(.button)
                .fixedSize()
                .focusable(false)
                .help("The show's title, text size and projection area, set on the stage")

            if !state.issues.isEmpty { health }

            Spacer(minLength: 16)

            CautionLamps(cautions: state.cautions, selected: state.selectedCaution, room: .studio,
                         onSelect: state.onSelectCaution)
            HeaderBar(state: state).projector
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: Desk.bar))
        .overlay(alignment: .bottom) { Divider() }
        .coordinateSpace(name: HeaderBar.space)
    }

    /// How many issues the sheet has, in amber; it opens a list of every
    /// issue, each with a button that stands its cue by.
    private var health: some View {
        Button { showingIssues.toggle() } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(nsColor: .systemOrange))
                    .frame(width: 7, height: 7)
                Text("\(state.issues.count) issue\(state.issues.count == 1 ? "" : "s")")
            }
        }
        .fixedSize()
        .focusable(false)
        .help("What needs fixing in the cue sheet")
        .popover(isPresented: $showingIssues, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(state.issues) { issue in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Circle().fill(Color(nsColor: .systemOrange)).frame(width: 6, height: 6)
                        Text(issue.message)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let cue = issue.cue {
                            Button("Stand by") {
                                showingIssues = false
                                state.onStandBy(cue)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            .font(.system(size: 12.5))
            .padding(16)
            .frame(width: 420)
        }
    }
}
