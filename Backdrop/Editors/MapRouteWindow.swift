import AppKit
import BackdropCore
import BackdropStage
import SwiftUI

/// Where a map cue's route is laid: the map, with the route drawn over it.
/// Click the map to add a stop at the end of the route; drag any point to
/// move it; select one to set what it is and what the screen says there.
/// Two places whose latitude and longitude are known give the coordinates.
/// The slider beneath runs the dot along the whole route.
///
/// One window, for one map cue at a time, in edit mode only, so it may take
/// the keyboard. Every change is one step of undo, as in the console.
final class MapRouteWindowController: NSWindowController, NSWindowDelegate {
    let cueID: UUID
    private weak var controller: ShowController?
    private let model: RouteModel
    /// The document's, so Undo here undoes what was done here.
    var undoManagerSource: () -> UndoManager? = { nil }

    init(controller: ShowController, cueID: UUID, mediaURL: @escaping (String) -> URL?) {
        self.controller = controller
        self.cueID = cueID
        model = RouteModel(mediaURL: mediaURL)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 900, height: 600)
        window.backgroundColor = Desk.colour
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: RouteView(model: model))
        window.setContentSize(NSSize(width: 1240, height: 820))
        super.init(window: window)
        window.delegate = self
        window.center()
        model.commit = { [weak self] name, change in
            guard let self else { return }
            self.controller?.updateCue(self.cueID, name) { cue in
                if case .map(var c) = cue.content {
                    change(&c)
                    cue.content = .map(c)
                }
            }
        }
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        undoManagerSource()
    }

    /// Brings the window up to date with the show, after any edit, an undo
    /// included. Closes it if the cue has gone, stopped being a map, or the
    /// show has gone into show mode.
    func refresh() {
        guard let controller, controller.mode == .edit, let cue = controller.show[cueID], case .map(let content) = cue.content else {
            close()
            return
        }
        window?.title = "Map Route \u{2014} Cue \(cue.number.isEmpty ? "(no number)" : cue.number)"
        model.update(content, settings: content.settings)
    }
}
