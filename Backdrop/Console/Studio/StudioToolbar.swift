import BackdropCore
import SwiftUI

/// One issue in the cue sheet, as the sheet health popover lists it.
struct SheetHealthIssue: Identifiable, Equatable {
    let id: Int
    let cue: UUID?
    let message: String
}

/// The Studio's toolbar: the show's title and whether it is edited, Lock for
/// show, Add cue, Stage setup and the sheet's health; then any cautions and
/// the projector, with a small live picture of what it shows.
///
/// Nothing here takes the keyboard, so the show keys still reach the show.
struct StudioToolbar: View {
    @ObservedObject var state: HeaderState
    @State private var showingIssues = false

    var body: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(state.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if state.isEdited {
                    Text("Edited").foregroundStyle(.secondary)
                }
            }
            .padding(.trailing, 6)

            LockControl(face: .studio, onLock: state.onLock)

            Button { state.onShowAddCue() } label: {
                HStack(spacing: 6) {
                    Text("+ Add cue")
                    Text("\u{21E7}\u{2318}N").foregroundStyle(.secondary)
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

            health

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

    /// "Sheet OK" in green, or how many issues in amber; either opens a list
    /// of every issue, each with a button that stands its cue by.
    private var health: some View {
        Button { showingIssues.toggle() } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(state.issues.isEmpty ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
                    .frame(width: 7, height: 7)
                Text(state.issues.isEmpty ? "Sheet OK" : "\(state.issues.count) issue\(state.issues.count == 1 ? "" : "s")")
            }
        }
        .fixedSize()
        .focusable(false)
        .help(state.issues.isEmpty ? "The cue sheet has no issues" : "What needs fixing in the cue sheet")
        .popover(isPresented: $showingIssues, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                if state.issues.isEmpty {
                    Text("The cue sheet has no issues.").foregroundStyle(.secondary)
                }
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
