import AppKit
import ProspectCore
import ProspectStage
import SwiftUI

/// Edit mode's cue editor. It edits the cue standing by: click a cue in the
/// list to edit it. Every change goes through the show controller as one
/// undoable edit.
///
/// AppKit on the outside so the console's layout places it like any other
/// panel; SwiftUI within, in the Mac's own controls.
@MainActor
final class CueEditorPanel: PanelHost<CueEditorView> {
    weak var controller: ShowController?
    var importMedia: (URL, UUID, ShowDocument.MediaSlot?) -> Void = { _, _, _ in }
    var chooseMedia: (UUID, ShowDocument.MediaSlot?) -> Void = { _, _ in }
    /// Opens a morph's points, on one of its stages.
    var editPoints: (UUID, Int) -> Void = { _, _ in }
    /// Opens a map's route.
    var editRoute: (UUID) -> Void = { _ in }
    /// Where a file in the show is on disk, for the morph's thumbnails.
    var mediaURL: (String) -> URL? = { _ in nil } {
        didSet { morphPictures.thumbnails.mediaURL = mediaURL }
    }
    /// Return or Escape in a field gives the keyboard back to the show keys.
    var finishedEditing: () -> Void = {}

    private(set) var cue: Cue?
    private let morphPictures = MorphPicturesState()

    init() {
        super.init(rootView: CueEditorView(cue: nil, goPoint: nil, defaults: ShowSettings(),
                                           morphPictures: MorphPicturesState(), edit: { _, _ in }, typing: { _, _ in },
                                           onFinished: {},
                                           onChooseMedia: {}, onRemoveMedia: {}, onDropMedia: { _ in }, onEditRoute: {}))
        wireMorphPictures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(cue: Cue?, goPoint: ShowController.StandingByGoPoint? = nil) {
        self.cue = cue
        let point = cue != nil && goPoint?.cue.id == cue?.id ? goPoint : nil
        let settings = controller?.show.settings ?? ShowSettings()
        if case .morph(let c) = cue?.content {
            if morphPictures.pictures != c.pictures { morphPictures.pictures = c.pictures }
            let morphMs = settings.resolved(c.overrides).morphMs
            if morphPictures.cueMorphMs != morphMs { morphPictures.cueMorphMs = morphMs }
        }
        rootView = CueEditorView(
            cue: cue,
            goPoint: point,
            defaults: settings,
            morphPictures: morphPictures,
            edit: { [weak self] name, body in
                guard let self, let id = self.cue?.id else { return }
                controller?.updateCue(id, name, body)
            },
            typing: { [weak self] name, body in
                guard let self, let id = self.cue?.id else { return }
                controller?.updateCue(id, name, coalescing: true, body)
            },
            onFinished: { [weak self] in self?.finishedEditing() },
            onChooseMedia: { [weak self] in
                guard let self, let id = self.cue?.id else { return }
                chooseMedia(id, nil)
            },
            onRemoveMedia: { [weak self] in self?.removeMedia() },
            onDropMedia: { [weak self] url in
                guard let self, let id = self.cue?.id else { return }
                importMedia(url, id, nil)
            },
            onEditRoute: { [weak self] in
                guard let self, let id = self.cue?.id else { return }
                editRoute(id)
            }
        )
    }

    /// Leaves the file in the show, where an undo expects it.
    private func removeMedia() {
        guard let cue else { return }
        controller?.updateCue(cue.id, cue.kind == .video ? "Remove Clip" : "Remove Picture") { cue in
            switch cue.content {
            case .image(var c): c.src = ""; cue.content = .image(c)
            case .map(var c): c.src = ""; cue.content = .map(c)
            case .video(var c): c.src = ""; cue.content = .video(c)
            default: break
            }
        }
    }

    // MARK: A morph's pictures

    /// Every change to the list is one undoable edit, to the cue the strip
    /// shows.
    private func wireMorphPictures() {
        morphPictures.onAdd = { [weak self] urls in
            guard let self, let id = cue?.id else { return }
            for url in urls { importMedia(url, id, .add) }
        }
        morphPictures.onChoose = { [weak self] index in
            guard let self, let id = cue?.id else { return }
            chooseMedia(id, index.map(ShowDocument.MediaSlot.picture) ?? .add)
        }
        morphPictures.onRemove = { [weak self] index in self?.changeMorph("Remove Picture") { $0.removePicture(at: index) } }
        morphPictures.onMove = { [weak self] from, to in self?.changeMorph("Move Picture") { $0.movePicture(from: from, to: to) } }
        morphPictures.onTime = { [weak self] index, ms in
            self?.changeMorph("Change Stage Time") { c in
                guard c.pictures.indices.contains(index) else { return }
                c.pictures[index].morphMs = ms.map { min(max($0, SettingRange.morphMs.lowerBound), SettingRange.morphMs.upperBound) }
            }
        }
        morphPictures.onPoints = { [weak self] stage in
            guard let self, let id = cue?.id else { return }
            editPoints(id, stage)
        }
    }

    private func changeMorph(_ name: String, _ body: @escaping (inout MorphContent) -> Void) {
        guard let id = cue?.id else { return }
        controller?.updateCue(id, name) { cue in
            if case .morph(var c) = cue.content { body(&c); cue.content = .morph(c) }
        }
    }

    #if DEBUG
    /// The fields this cue shows, in order, for checking that each kind
    /// offers what it should. SwiftUI owns the key view loop, so this is the
    /// form's own order rather than a walk of it.
    var tabStops: [String] {
        guard let cue else { return [] }
        return CueField.order(for: cue.kind, continues: cue.continueMode.continues).map(\.rawValue)
    }
    #endif
}
