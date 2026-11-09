import AppKit
import BackdropCore
import BackdropStage
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
        didSet {
            morphPictures.thumbnails.mediaURL = mediaURL
            layeredStrip.thumbnails.mediaURL = mediaURL
        }
    }
    /// Return or Escape in a field gives the keyboard back to the show keys.
    var finishedEditing: () -> Void = {}

    /// Set on the kind's tab: a change to one of the cue's settings.
    var onSetting: (SettingKey, SettingValue, Bool) -> Void = { _, _, _ in }
    private let scope: CueField.Scope

    private(set) var cue: Cue?
    private let morphPictures = MorphPicturesState()
    private let layeredStrip = LayeredStripState()

    init(scope: CueField.Scope) {
        self.scope = scope
        super.init(rootView: CueEditorView(scope: scope, cue: nil, goPoint: nil,
                                           morphPictures: MorphPicturesState(), layeredStrip: LayeredStripState(), edit: { _, _ in }, typing: { _, _ in },
                                           onFinished: {},
                                           onChooseMedia: {}, onRemoveMedia: {}, onDropMedia: { _ in }, onEditRoute: {},
                                           onSetting: { _, _, _ in }))
        wireMorphPictures()
        wireLayeredStrip()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(cue: Cue?, goPoint: ShowController.StandingByGoPoint? = nil) {
        self.cue = cue
        let point = cue != nil && goPoint?.cue.id == cue?.id ? goPoint : nil
        if case .morph(let c) = cue?.content {
            if morphPictures.pictures != c.pictures { morphPictures.pictures = c.pictures }
            let morphMs = c.settings.morphMs
            if morphPictures.cueMorphMs != morphMs { morphPictures.cueMorphMs = morphMs }
        }
        if case .layered(let c) = cue?.content {
            if layeredStrip.layers != c.layers { layeredStrip.layers = c.layers }
            let layerMs = c.settings.layerMs
            if layeredStrip.cueLayerMs != layerMs { layeredStrip.cueLayerMs = layerMs }
        }
        rootView = CueEditorView(
            scope: scope,
            cue: cue,
            goPoint: point,
            morphPictures: morphPictures,
            layeredStrip: layeredStrip,
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
            },
            onSetting: { [weak self] key, value, continuous in self?.onSetting(key, value, continuous) }
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
            case .layered(var c): c.base = ""; cue.content = .layered(c)
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

    // MARK: A layered cue's layers

    private func wireLayeredStrip() {
        layeredStrip.onAdd = { [weak self] urls in
            guard let self, let id = cue?.id else { return }
            for url in urls { importMedia(url, id, .add) }
        }
        layeredStrip.onChoose = { [weak self] index in
            guard let self, let id = cue?.id else { return }
            chooseMedia(id, index.map(ShowDocument.MediaSlot.picture) ?? .add)
        }
        layeredStrip.onRemove = { [weak self] index in self?.changeLayered("Remove Layer") { $0.removeLayer(at: index) } }
        layeredStrip.onMove = { [weak self] from, to in self?.changeLayered("Move Layer") { $0.moveLayer(from: from, to: to) } }
        layeredStrip.onChange = { [weak self] index, name, change in
            self?.changeLayered(name) { c in
                guard c.layers.indices.contains(index) else { return }
                change(&c.layers[index])
                // A first layer cannot arrive with one before it.
                if index == 0 { c.layers[0].withPrevious = false }
            }
        }
    }

    private func changeLayered(_ name: String, _ body: @escaping (inout LayeredContent) -> Void) {
        guard let id = cue?.id else { return }
        controller?.updateCue(id, name) { cue in
            if case .layered(var c) = cue.content { body(&c); cue.content = .layered(c) }
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
        return CueField.order(for: cue.kind, continues: cue.continueMode.continues, scope: scope).map(\.rawValue)
    }
    #endif
}
