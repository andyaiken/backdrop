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
/// It takes the Studio's stage, for one map cue at a time, in edit mode
/// only, until Done or Escape; it may take the keyboard meanwhile. Every
/// change is one step of undo, as in the rest of the console.
@MainActor
final class MapRouteEditor: NSView {
    let cueID: UUID
    private weak var controller: ShowController?
    private let model: RouteModel
    private let host: NSHostingView<RouteView>
    private let heading = Desk.label("", font: Desk.sans(14, .semibold), colour: Desk.text)
    private let done = NSButton(title: "Done", target: nil, action: nil)
    /// Done, Escape, or the cue gone: the stage comes back.
    var onClose: () -> Void = {}

    init(controller: ShowController, cueID: UUID, mediaURL: @escaping (String) -> URL?) {
        self.controller = controller
        self.cueID = cueID
        model = RouteModel(mediaURL: mediaURL)
        host = NSHostingView(rootView: RouteView(model: model))
        super.init(frame: .zero)
        done.bezelStyle = .rounded
        done.target = self
        done.action = #selector(donePressed)
        for view in [heading, done, host] as [NSView] { addSubview(view) }
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

    override var isFlipped: Bool { true }

    @objc private func donePressed() { onClose() }

    /// Escape, from anywhere in the editor: the stage comes back.
    override func cancelOperation(_ sender: Any?) { onClose() }

    override func layout() {
        super.layout()
        let doneSize = done.fittingSize
        done.frame = NSRect(x: bounds.width - doneSize.width, y: 0, width: doneSize.width, height: 28)
        heading.frame = NSRect(x: 0, y: 5, width: max(0, done.frame.minX - 8), height: 18)
        host.frame = NSRect(x: 0, y: 36, width: bounds.width, height: max(0, bounds.height - 36))
    }

    /// Brings the editor up to date with the show, after any edit, an undo
    /// included. Closes it if the cue has gone, stopped being a map, or the
    /// show has gone into show mode.
    func refresh() {
        guard let controller, controller.mode == .edit, let cue = controller.show[cueID], case .map(let content) = cue.content else {
            onClose()
            return
        }
        heading.stringValue = "Map route \u{00B7} Cue \(cue.number.isEmpty ? "(no number)" : cue.number)"
        model.update(content, settings: content.settings)
    }
}
