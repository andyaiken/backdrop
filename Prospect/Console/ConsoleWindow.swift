import AppKit
import ProspectCore
import ProspectStage

/// The operator's window: the cue list, the standby panel, GO, a live
/// preview of the projector drawn by the same renderers into a second
/// surface, and the keyboard reference. In edit mode it adds the projection
/// area controls.
///
/// Nothing in it takes keyboard focus except the Go-to field, so the show
/// keys always reach the show: a focused button would be pressed by Space,
/// and a focused slider would eat the arrows.
@MainActor
final class ConsoleWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    let controller: ShowController
    let preview = SurfaceView(role: .preview)

    private let root = ConsoleRootView()
    private let header = HeaderView()
    private let standby = StandbyPanel()
    private let cuesHeading = Desk.label("Cues", font: Desk.sans(12.5, .semibold), colour: Desk.text)
    let cueList = CueListView()
    private let gotoLabel = Desk.label("Go to cue", font: Desk.sans(12.5), colour: Desk.dim)
    private let gotoField = NSTextField(string: "")
    private let status = Desk.label("", font: Desk.sans(12.5), colour: Desk.dim, wraps: true)
    private let divider = PanelView(fill: Desk.line)
    private let warning = WarningBox()
    private let previewHeading = Desk.label("What the audience sees", font: Desk.sans(12.5), colour: Desk.dim)
    private let previewFrame = PanelView(fill: .black, border: Desk.lineBright, radius: 2)
    private let geometry = GeometryPanel()
    private(set) var editor = CueEditorPanel()
    private let cueSettings = CueSettingsPanel()
    private let showDefaults = ShowDefaultsPanel()
    /// Edit mode's panels, one at a time beneath the preview.
    private let tabs = NSSegmentedControl(labels: ["Cue", "Cue Settings", "Show", "Projection Area"],
                                          trackingMode: .selectOne, target: nil, action: nil)
    private var editPanels: [NSView] { [editor, cueSettings, showDefaults, geometry] }
    private let keybar = KeyBar()

    /// Copies a dropped or chosen file into the show for a cue.
    var importMedia: (URL, UUID, ShowDocument.MediaSlot?) -> Void = { _, _, _ in }
    /// Offers an open panel for a cue's picture or clip.
    var chooseMedia: (UUID, ShowDocument.MediaSlot?) -> Void = { _, _ in }
    /// Where a file in the show is on disk.
    var mediaURL: (String) -> URL? = { _ in nil } {
        didSet { editor.mediaURL = mediaURL }
    }
    /// The morph points window, while one is open.
    private var points: MorphPointsWindowController?
    /// The map route window, while one is open.
    private var route: MapRouteWindowController?

    /// Open Projector, from the header button.
    var openProjector: () -> Void = {}
    /// The header's Show / Edit switch: true for edit mode. The document
    /// does the switching, as it does for the Show menu.
    var setMode: (_ editing: Bool) -> Void = { _ in }
    /// The console moved to another display, which can change where the
    /// projector may go.
    var screenChanged: () -> Void = {}

    init(controller: ShowController) {
        self.controller = controller
        let window = ConsoleWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Desk.colour
        window.contentMinSize = NSSize(width: 900, height: 600)
        window.contentView = root
        window.initialFirstResponder = root
        // Prospect reopens the last show itself; restored windows would
        // open it twice.
        window.isRestorable = false
        super.init(window: window)
        // The console comes back where it was left, not offset from it.
        shouldCascadeWindows = false
        window.delegate = self
        window.setFrameAutosaveName("Console")
        if !window.setFrameUsingName("Console") { window.center() }

        root.controller = controller
        root.onLayout = { [weak self] in self?.layoutContent() }
        root.wantsLayer = true
        root.layer?.backgroundColor = Desk.colour.cgColor
        preview.controller = controller
        controller.runner.attach(preview.surface)
        previewFrame.addSubview(preview)

        gotoField.font = Desk.mono(12.5)
        gotoField.placeholderString = "e.g. P12"
        gotoField.delegate = self
        gotoField.bezelStyle = .roundedBezel

        header.go.target = self
        header.go.action = #selector(goPressed)
        header.openProjector.target = self
        header.openProjector.action = #selector(openProjectorPressed)
        header.mode.target = self
        header.mode.action = #selector(modeChosen)
        header.addCue.target = self
        header.addCue.action = #selector(addCueChosen)
        // An edit still open is finished first, so it lands on the cue it was
        // made for rather than the one the click stands by.
        cueList.onClick = { [weak self] id in
            guard let self else { return }
            self.window?.makeFirstResponder(self.root)
            self.controller.standBy(id)
        }
        cueList.onStepClick = { [weak self] id, step in
            guard let self else { return }
            self.window?.makeFirstResponder(self.root)
            self.controller.standBy(id, step: step)
        }
        cueList.onDrop = { [weak self] url, id in self?.importMedia(url, id, nil) }
        cueList.onDelete = { [weak controller] id in controller?.deleteCue(id) }
        cueList.onMoveCue = { [weak controller] id, row in controller?.moveCue(id, before: row) }
        cueList.onMoveGroup = { [weak controller] id, row in controller?.moveGroup(id, before: row) }
        cueList.onGroupLevel = { [weak controller] id, delta in controller?.moveGroupLevel(id, by: delta) }
        cueList.onDeleteGroup = { [weak controller] id in controller?.deleteGroup(id) }
        cueList.onRenumber = { [weak self] id in
            if let id { self?.confirmRenumber(group: id) } else { self?.confirmRenumber() }
        }
        // A rename hands the keyboard back to the show keys.
        cueList.onRenameGroup = { [weak self] id, name in
            guard let self else { return }
            self.controller.renameGroup(id, to: name)
            self.window?.makeFirstResponder(self.root)
        }
        editor.controller = controller
        editor.importMedia = { [weak self] url, id, slot in self?.importMedia(url, id, slot) }
        editor.chooseMedia = { [weak self] id, slot in self?.chooseMedia(id, slot) }
        editor.editPoints = { [weak self] id, stage in self?.showPoints(for: id, stage: stage) }
        editor.editRoute = { [weak self] id in self?.showRoute(for: id) }
        editor.finishedEditing = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.root)
        }
        // Slider drags are one undo step each.
        geometry.onChange = { [weak controller] g in controller?.setGeometry(g, coalescing: true) }
        showDefaults.onChange = { [weak controller] key, value, continuous in
            controller?.setDefault(key, to: value, coalescing: continuous)
        }
        showDefaults.onTitleChange = { [weak controller] title in controller?.setTitle(title) }
        showDefaults.finishedEditing = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.root)
        }
        cueSettings.onChange = { [weak controller] key, value, continuous in
            guard let controller, let id = controller.standingByCue?.id else { return }
            controller.setOverride(key, to: value, for: id, coalescing: continuous)
        }
        tabs.selectedSegment = 0
        tabs.refusesFirstResponder = true
        tabs.target = self
        tabs.action = #selector(tabChosen)
        geometry.guides.target = self
        geometry.guides.action = #selector(guidesToggled)

        for view in [header, standby, cuesHeading, cueList, gotoLabel, gotoField, status, divider,
                     warning, previewHeading, previewFrame, geometry, editor, cueSettings, showDefaults, tabs, keybar] as [NSView] {
            root.addSubview(view)
        }
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Refresh

    private var refreshPending = false

    /// The show changed. The console catches up on the next turn of the run
    /// loop, once for everything that changed meanwhile, and never in the
    /// middle of a frame: a continue fires from the display link's tick, and
    /// refreshing updates the window title, which mustn't change while Core
    /// Animation is committing.
    func setNeedsRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self, refreshPending else { return }
            refreshPending = false
            refresh()
        }
    }

    /// The first time the console comes up, its wordmark decrypts.
    private var hasShown = false

    override func showWindow(_ sender: Any?) {
        if !hasShown {
            hasShown = true
            header.decryptWordmark()
        }
        super.showWindow(sender)
    }

    #if DEBUG
    func holdWordmark(atFrame frame: Int) {
        header.holdWordmark(atFrame: frame)
    }
    #endif

    /// Opens a morph's points on one of its stages, in its own window.
    func showPoints(for id: UUID, stage: Int = 0) {
        guard controller.mode == .edit, let cue = controller.show[id], cue.kind == .morph else { return }
        if points?.cueID != id {
            points?.close()
            let window = MorphPointsWindowController(controller: controller, cueID: id, mediaURL: mediaURL)
            window.undoManagerSource = { [weak self] in self?.document?.undoManager }
            points = window
        }
        points?.show(stage: stage)
        points?.showWindow(nil)
    }

    /// Opens a map's route, in its own window.
    func showRoute(for id: UUID) {
        guard controller.mode == .edit, let cue = controller.show[id], cue.kind == .map else { return }
        if route?.cueID != id {
            route?.close()
            let window = MapRouteWindowController(controller: controller, cueID: id, mediaURL: mediaURL)
            window.undoManagerSource = { [weak self] in self?.document?.undoManager }
            route = window
        }
        route?.showWindow(nil)
    }

    func refresh() {
        refreshPending = false
        points?.refresh()
        if points?.window?.isVisible == false { points = nil }
        route?.refresh()
        if route?.window?.isVisible == false { route = nil }
        let show = controller.show, playhead = controller.playhead, projector = controller.projector
        let live = playhead.live.flatMap { show[$0] }
        let next = playhead.standby.flatMap { show[$0] }
        // A step of a cue may stand by rather than the cue itself: GO carries
        // the live cue on or back to it, or fires another cue straight at it.
        let goPoint = controller.standingByGoPoint
        synchronizeWindowTitleWithDocumentName()

        let isLive = projector.display != nil
        header.update(
            mode: controller.mode == .edit,
            lamp: playhead.blackout ? "Blacked out \u{2014} press B" : projector.lamp,
            live: isLive && !playhead.blackout,
            warn: playhead.blackout || projector.warning != nil,
            projectorOpen: projector.isOpen,
            goEnabled: next != nil,
            goTip: goPoint.map { $0.cue.id == playhead.live ? "Carry cue \($0.cue.number) on" : "Fire cue \($0.cue.number) at GO \($0.number)" }
                ?? next.map { "Fire cue \($0.number)" } ?? "End of the cue sheet"
        )
        // The groups GO goes to, and those of what is on screen, to see
        // whether GO crosses from one group into another.
        let nextID = goPoint?.cue.id ?? next?.id
        standby.update(standby: next, live: live, goPoint: goPoint, entry: playhead.entry, arm: controller.standbyArmState,
                       groups: nextID.map { show.groups(around: $0) } ?? [], liveGroups: live.map { show.groups(around: $0.id) } ?? [])
        cueList.update(show: show, standby: playhead.standby, standbyStep: playhead.standbyStep, live: playhead.live,
                       taken: playhead.goPointsTaken, issues: Set(show.issues.flatMap(\.cues)), editing: controller.mode == .edit)
        let editing = controller.mode == .edit ? controller.standingByCue : nil
        editor.update(cue: editing, goPoint: controller.standingByGoPoint)
        cueSettings.update(cue: editing, defaults: show.settings)
        showDefaults.update(title: show.title, fallback: document?.displayName ?? "Untitled", settings: show.settings)
        status.stringValue = controller.message ?? ""
        warning.text.stringValue = projector.warning ?? ""
        geometry.update(geometry: show.settings.geometry, guidesOn: controller.showsGuides)
        root.needsLayout = true
    }

    // MARK: Layout

    private var previewAspect: CGFloat {
        if let display = controller.projector.display, display.frame.height > 0 {
            return display.frame.width / display.frame.height
        }
        return 16 / 9
    }

    private func layoutContent() {
        let b = root.bounds
        let headerHeight: CGFloat = 54, keybarHeight: CGFloat = 40, leftWidth: CGFloat = 340
        header.frame = NSRect(x: 0, y: 0, width: b.width, height: headerHeight)
        keybar.frame = NSRect(x: 0, y: b.height - keybarHeight, width: b.width, height: keybarHeight)
        let top = headerHeight + 1, bottom = b.height - keybarHeight

        // Left: standby, the cue list, Go to, and the status line.
        let standbyHeight = standby.height(width: leftWidth)
        standby.frame = NSRect(x: 0, y: top, width: leftWidth, height: standbyHeight)
        cuesHeading.frame = NSRect(x: 16, y: standby.frame.maxY + 15, width: leftWidth - 32, height: 18)
        let statusHeight = Desk.height(of: status, width: leftWidth - 32)
        status.frame = NSRect(x: 16, y: bottom - 12 - statusHeight, width: leftWidth - 32, height: statusHeight)
        let gotoY = status.frame.minY - (statusHeight > 0 ? 10 : 0) - 26
        gotoLabel.frame = NSRect(x: 16, y: gotoY + 4, width: 84, height: 18)
        gotoField.frame = NSRect(x: 104, y: gotoY, width: leftWidth - 120, height: 24)
        let listTop = cuesHeading.frame.maxY + 9
        cueList.frame = NSRect(x: 6, y: listTop, width: leftWidth - 12, height: max(0, gotoY - 12 - listTop))
        divider.frame = NSRect(x: leftWidth, y: top - 1, width: 1, height: bottom - top + 1)

        // Right: warnings, the preview, and in edit mode the projection area.
        let x = leftWidth + 1 + 16, width = b.width - x - 16
        var y = top + 16
        warning.isHidden = warning.text.stringValue.isEmpty
        if !warning.isHidden {
            let h = warning.height(width: width)
            warning.frame = NSRect(x: x, y: y, width: width, height: h)
            y += h + 14
        }
        let headingHeight: CGFloat = 27
        // Edit mode: one panel at a time beneath the preview, chosen by the
        // tabs. Every panel gets the same height, so the preview doesn't jump
        // as the tabs change.
        let editing = controller.mode == .edit
        tabs.isHidden = !editing
        for (i, panel) in editPanels.enumerated() { panel.isHidden = !editing || i != tabs.selectedSegment }
        var available = bottom - 16 - y - headingHeight
        if editing {
            let h = [geometry.preferredHeight, editor.preferredHeight, showDefaults.preferredHeight(width: width), cueSettings.preferredHeight].max() ?? 0
            let panelFrame = NSRect(x: x, y: bottom - 16 - h, width: width, height: h)
            for panel in editPanels { panel.frame = panelFrame }
            let tabsSize = tabs.fittingSize
            tabs.frame = NSRect(x: x, y: panelFrame.minY - 10 - tabsSize.height, width: tabsSize.width, height: tabsSize.height)
            available -= h + 16 + tabsSize.height + 10
        }
        var w = width, h = (width / previewAspect).rounded()
        if h > available {
            h = max(available, 0)
            w = (h * previewAspect).rounded()
        }
        // Centred in the space left, its heading just above its corner.
        let left = x + ((width - w) / 2).rounded(), blockTop = y + ((available - h) / 2).rounded()
        previewHeading.frame = NSRect(x: left, y: blockTop, width: w, height: 18)
        previewFrame.frame = NSRect(x: left, y: blockTop + headingHeight, width: w, height: h)
        preview.frame = previewFrame.bounds.insetBy(dx: 1, dy: 1)
    }

    // MARK: Actions

    @objc private func goPressed() {
        controller.go()
        window?.makeFirstResponder(root)
    }

    @objc private func openProjectorPressed() {
        openProjector()
        window?.makeFirstResponder(root)
    }

    /// A new cue stands by, and the Cue tab opens on it to be filled in.
    @objc private func addCueChosen() {
        let index = header.addCue.indexOfSelectedItem - 1
        if index == Cue.Kind.allCases.count { return addGroup() }
        guard Cue.Kind.allCases.indices.contains(index), controller.addCue(Cue.Kind.allCases[index]) != nil else { return }
        showEditTab(0)
        window?.makeFirstResponder(root)
    }

    @objc private func modeChosen() {
        setMode(header.mode.isEditing)
        window?.makeFirstResponder(root)
        refresh()
    }

    @objc private func tabChosen() {
        root.needsLayout = true
        window?.makeFirstResponder(root)
    }

    /// Add Group, from the header or the Edit menu: a heading above the cue
    /// standing by, its name ready to type.
    func addGroup() {
        guard let id = controller.addGroup() else { return }
        refresh()
        cueList.beginRename(id)
    }

    /// For the snapshot tool: shows one of edit mode's tabs.
    func showEditTab(_ index: Int) {
        tabs.selectedSegment = index
        root.needsLayout = true
    }

    @objc private func guidesToggled() {
        controller.showsGuides = geometry.guides.state == .on
    }

    /// The Go-to field: Return stands the cue by, Escape gives up. Either way
    /// the keyboard goes back to the show.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            controller.standBy(number: gotoField.stringValue)
        case #selector(NSResponder.cancelOperation(_:)):
            break
        default:
            return false
        }
        gotoField.stringValue = ""
        window?.makeFirstResponder(root)
        return true
    }

    /// Edit › Renumber All Cues. Renumbering rewrites every cue number the
    /// DSM has in the book, so it asks first, with Cancel as the default.
    func confirmRenumber() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Renumber every cue 1, 2, 3\u{2026}?"
        alert.informativeText = "Cue numbers are what the DSM writes in the book, so the book will need rewriting to match. Do this once, before tech, and never after."
        alert.addButton(withTitle: "Cancel")
        let renumber = alert.addButton(withTitle: "Renumber")
        renumber.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertSecondButtonReturn else { return }
            MainActor.assumeIsolated { self?.controller.renumberAll() }
        }
    }

    /// A group's cues numbered from a start the operator chooses, the next
    /// whole number after the cues before it unless changed: so Act Two can
    /// start at 100. It asks first, and again if any new number is already
    /// used outside the group.
    func confirmRenumber(group id: UUID) {
        let show = controller.show
        guard let window, let group = show.groups.first(where: { $0.id == id }) else { return }
        let count = show.cues(inGroup: id).count
        guard count > 0 else { return }
        let alert = NSAlert()
        alert.messageText = "Renumber the \(count) cue\(count == 1 ? "" : "s") in \u{201C}\(group.name)\u{201D}?"
        alert.informativeText = "They are numbered in running order from the number below, one apart, groups inside it included. Cue numbers are what the DSM writes in the book, so the book will need rewriting to match."
        let start = NSTextField(string: String(show.renumberStart(forGroup: id)))
        start.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
        start.font = Desk.mono(13)
        start.placeholderString = "100"
        alert.accessoryView = start
        alert.addButton(withTitle: "Cancel")
        let renumber = alert.addButton(withTitle: "Renumber")
        renumber.hasDestructiveAction = true
        alert.window.initialFirstResponder = start
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertSecondButtonReturn else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let from = Int(start.stringValue.trimmingCharacters(in: .whitespaces)), from >= 0 else {
                    self.controller.say("\u{201C}\(start.stringValue)\u{201D} isn\u{2019}t a whole number to start from, so nothing was renumbered.")
                    return
                }
                let clashes = self.controller.show.renumberClashes(group: id, from: from)
                guard !clashes.isEmpty else { return self.controller.renumber(group: id, from: from) }
                let again = NSAlert()
                let listed = clashes.prefix(6).joined(separator: ", ") + (clashes.count > 6 ? " and \(clashes.count - 6) more" : "")
                again.messageText = "Cues outside \u{201C}\(group.name)\u{201D} already use \(listed)."
                again.informativeText = "Renumbering anyway leaves those numbers on two cues each, flagged on the sheet until one of each is changed."
                again.addButton(withTitle: "Cancel")
                let anyway = again.addButton(withTitle: "Renumber Anyway")
                anyway.hasDestructiveAction = true
                again.beginSheetModal(for: window) { [weak self] response in
                    guard response == .alertSecondButtonReturn else { return }
                    MainActor.assumeIsolated { self?.controller.renumber(group: id, from: from) }
                }
            }
        }
    }

    // MARK: Window

    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        let live = controller.playhead.live.flatMap { controller.show[$0] }
        return live.map { "\(displayName) \u{2014} Cue \($0.number)" } ?? displayName
    }

    /// No undo in show mode: the sheet is locked.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        controller.mode == .edit ? document?.undoManager : nil
    }


    /// Moving the projector waits for the next turn of the run loop: AppKit
    /// can say the screen changed while it is still rearranging displays.
    func windowDidChangeScreen(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.screenChanged()
            self?.setNeedsRefresh()
        }
    }
}

/// Closing the console is quitting, and goes through the same check: the
/// close button and File › Close go straight to Quit.
///
/// They must not get as far as closing the window. The show owns the
/// console, so AppKit would first ask the show whether it can close, and
/// quitting from inside that request asks the show again and waits for the
/// first request to finish, which never happens.
final class ConsoleWindow: NSWindow {
    /// What the close button and File › Close do instead of closing.
    var onPerformClose: () -> Void = { NSApp.terminate(nil) }

    override func performClose(_ sender: Any?) {
        onPerformClose()
    }
}

/// The console's content. It takes the show keys whenever nothing else has
/// the keyboard, and lays out its children through the window controller.
final class ConsoleRootView: NSView {
    weak var controller: ShowController?
    var onLayout: () -> Void = {}

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        onLayout()
    }

    override func keyDown(with event: NSEvent) {
        guard let controller, ShowKeys.handle(event, controller: controller) else {
            super.keyDown(with: event)
            return
        }
    }

    /// A click on empty space takes the keyboard back from the Go-to field.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }
}
