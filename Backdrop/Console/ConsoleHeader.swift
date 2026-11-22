import AppKit
import BackdropCore
import BackdropStage
import SwiftUI

/// What the header shows, and what its controls do. Held apart from the view
/// so the console needn't rebuild it.
@MainActor
final class HeaderState: ObservableObject {
    @Published var editing = false
    /// The show's title, as the Booth's header names it.
    @Published var title = ""
    @Published var lamp = ""
    @Published var live = false
    @Published var warn = false
    @Published var blackout = false
    @Published var projectorOpen = false
    /// The Inspector is showing Stage setup.
    @Published var stageSetupOn = false
    /// The cue gallery is open.
    @Published var showingAddCue = false
    /// Where the gallery says a new cue will go.
    @Published var galleryPlace = GalleryPlace.atEnd
    /// The cautions, as lamps, most urgent first.
    @Published var cautions: [BoothWarning] = []
    /// The caution whose lamp was clicked, to show on the caution line.
    @Published var selectedCaution: BoothWarning.ID?

    var onLock: () -> Void = {}
    var onUnlock: () -> Void = {}
    var onAddCue: (Cue.Kind) -> Void = { _ in }
    /// Add Cue: the console opens the gallery, saying where the cue will go.
    var onShowAddCue: () -> Void = {}
    /// The gallery closed, whether a cue was added or not.
    var onGalleryClosed: () -> Void = {}
    var onStageSetup: (Bool) -> Void = { _ in }
    var onOpenProjector: () -> Void = {}
    var onCloseProjector: () -> Void = {}
    var onSelectCaution: (BoothWarning.ID) -> Void = { _ in }
    var displays: () -> (items: [DisplayMenu.Item], note: String?) = { ([], nil) }
    var onChooseDisplay: (DisplayIdentity) -> Void = { _ in }

    /// The document has changes not yet saved.
    @Published var isEdited = false
    /// The cue sheet's issues, for the Studio's sheet health.
    @Published var issues: [SheetHealthIssue] = []
    /// Stands a cue by, from the sheet health popover.
    var onStandBy: (UUID) -> Void = { _ in }
    /// Where the projector chip's live picture goes, in the header.
    var onPictureFrame: (CGRect) -> Void = { _ in }

    var room: Room { editing ? .studio : .booth }
}

/// The console's header: the Booth's in show mode, and in edit mode the
/// Studio's, with the cue sheet's own controls.
///
/// Nothing here takes the keyboard. Space fires the standby cue through the
/// show keys, and a focused button would be pressed by it.
@MainActor
final class HeaderView: PanelHost<HeaderBar> {
    let state: HeaderState

    init() {
        let state = HeaderState()
        self.state = state
        super.init(rootView: HeaderBar(state: state))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(mode editing: Bool, title: String, lamp text: String, live: Bool, warn: Bool, blackout: Bool,
                projectorOpen: Bool, stageSetupOn: Bool, cautions: [BoothWarning], selectedCaution: BoothWarning.ID?,
                isEdited: Bool = false, issues: [SheetHealthIssue] = []) {
        // Only what changed is set, so SwiftUI isn't asked to redraw for nothing.
        if state.editing != editing { state.editing = editing }
        if state.title != title { state.title = title }
        if state.lamp != text { state.lamp = text }
        if state.live != live { state.live = live }
        if state.warn != warn { state.warn = warn }
        if state.blackout != blackout { state.blackout = blackout }
        if state.projectorOpen != projectorOpen { state.projectorOpen = projectorOpen }
        if state.stageSetupOn != stageSetupOn { state.stageSetupOn = stageSetupOn }
        if state.cautions != cautions { state.cautions = cautions }
        if state.isEdited != isEdited { state.isEdited = isEdited }
        if state.issues != issues { state.issues = issues }
        if state.selectedCaution != selectedCaution { state.selectedCaution = selectedCaution }
    }
}

struct HeaderBar: View {
    @ObservedObject var state: HeaderState

    var body: some View {
        if state.editing { StudioToolbar(state: state) } else { BoothHeaderBar(state: state) }
    }

    /// The coordinate space the header's live picture is placed in.
    static let space = "header"

    var projector: some View {
        ProjectorChip(lamp: state.lamp, live: state.live, warn: state.warn, blackout: state.blackout,
                      isOpen: state.projectorOpen, room: state.room, displays: state.displays,
                      onOpen: state.onOpenProjector, onClose: state.onCloseProjector, onChoose: state.onChooseDisplay,
                      showsPicture: state.editing, onPictureFrame: state.onPictureFrame)
    }
}
