import AppKit
import BackdropCore
import BackdropStage

/// The operator's window: the cue list, the standby panel, GO, a live
/// preview of the projector drawn by the same renderers into a second
/// surface, and the keyboard reference. In edit mode it adds the Inspector,
/// which edits the cue standing by, its transition, or the Show Settings.
///
/// Nothing in it takes keyboard focus except the Go-to field, so the show
/// keys always reach the show: a focused button would be pressed by Space,
/// and a focused slider would eat the arrows.
@MainActor
final class ConsoleWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    let controller: ShowController
    let preview = SurfaceView(role: .preview)
    /// The cue standing by, finished, smaller than the live preview.
    let nextPreview = SurfaceView(role: .preview)

    private let root = ConsoleRootView()
    private let header = HeaderView()
    /// Edit mode, nothing selected: the wordmark fills the preview's place.
    private let wordmark = WordmarkView()
    private let standby = StandbyPanel()
    private let cuesHeading = Desk.label("Cues", font: Desk.sans(12.5, .semibold), colour: Desk.text)
    let cueList = CueListView()
    private let gotoLabel = Desk.label("Go to cue", font: Desk.sans(12.5), colour: Desk.dim)
    private let gotoField = NSTextField(string: "")
    private let status = Desk.label("", font: Desk.sans(12.5), colour: Desk.dim, wraps: true)
    private let divider = PanelView(fill: Desk.line)
    private let warning = WarningBox()
    private let previewHeading = Desk.label("On screen", font: Desk.sans(12.5), colour: Desk.dim)
    private let previewFrame = PanelView(fill: .black, border: Desk.lineBright, radius: 2)
    /// The Inspector's outline, around its tabs and forms, so it reads as a
    /// place even with nothing in it. It has no fill: the desk shows through.
    private let inspectorFrame = PanelView(fill: Desk.line)
    /// Edit mode: runs the selected cue on the stage again.
    private let runAgainButton: NSButton = {
        let b = NSButton(title: "Run again", target: nil, action: nil)
        b.bezelStyle = .rounded
        b.controlSize = .large
        return b
    }()
    private let nextHeading = Desk.label("Up next", font: Desk.sans(12.5), colour: Desk.dim)
    private let nextFrame = PanelView(fill: .black, border: Desk.line, radius: 2)
    private(set) var editor = CueEditorPanel(scope: .common)
    private(set) var kindEditor = CueEditorPanel(scope: .kind)
    private let cueTransitions = CueSettingsPanel(scope: .transitions)
    private let showSettingsPanel = ShowSettingsPanel()
    /// The Inspector shows the Show Settings rather than a cue. Choosing a cue
    /// or a transition in the list switches it off.
    private var showingShowSettings = false
    /// The Inspector's tabs: everything a cue has in common, then what this
    /// kind of cue runs with, named for the kind.
    private let tabs = NSSegmentedControl(labels: ["Cue", "Settings"],
                                          trackingMode: .selectOne, target: nil, action: nil)
    private var inspectorPanels: [NSView] { [editor, kindEditor] }
    /// The cue whose transition in is selected in the cue list, if one is.
    /// The Inspector then shows that transition alone, without the tabs.
    private var selectedTransition: UUID?
    /// The cue that stood by at the last refresh: a different one deselects the transition.
    private var lastStandby: UUID?
    /// What the Inspector says with no cue standing by. It takes the tabs'
    /// place rather than sitting under them: with nothing to inspect, tabs
    /// onto empty forms are only noise.
    private let inspectorEmpty: NSTextField = {
        let label = Desk.label("No cue selected.",
                               font: Desk.sans(12.5), colour: Desk.dim, wraps: true)
        label.alignment = .center
        return label
    }()
    private let keybar = KeyBar()
    /// What the cue list column says when the show has no cues, in place of
    /// everything else in it.
    private let cueListEmpty: NSTextField = {
        let label = Desk.label("", font: Desk.sans(12.5), colour: Desk.dim, wraps: true)
        label.alignment = .center
        return label
    }()

    // The columns: the cue list, the previews, and in edit mode the Inspector.
    // The list and the Inspector are as wide as the operator drags them; the
    // previews take what is left.
    private let listDivider = ColumnDivider()
    private let inspectorDivider = ColumnDivider()
    private var listWidth: CGFloat = ConsoleWindowController.savedWidth("ConsoleListWidth", default: 340)
    private var inspectorWidth: CGFloat = ConsoleWindowController.savedWidth("ConsoleInspectorWidth", default: 350)
    private static let listRange: ClosedRange<CGFloat> = 260...520
    private static let inspectorRange: ClosedRange<CGFloat> = 300...640
    /// The least the previews are left, whatever the columns beside them ask.
    private static let previewMinWidth: CGFloat = 260

    private static func savedWidth(_ key: String, default value: CGFloat) -> CGFloat {
        let saved = UserDefaults.standard.double(forKey: key)
        return saved > 0 ? CGFloat(saved) : value
    }

    /// Copies a dropped or chosen file into the show for a cue.
    var importMedia: (URL, UUID, ShowDocument.MediaSlot?) -> Void = { _, _, _ in }
    /// Offers an open panel for a cue's picture or clip.
    var chooseMedia: (UUID, ShowDocument.MediaSlot?) -> Void = { _, _ in }
    /// Makes new cues from files dropped between cues, to stand at this
    /// place in the sheet.
    var addMediaCues: ([URL], Int) -> Void = { _, _ in }
    /// Where a file in the show is on disk.
    var mediaURL: (String) -> URL? = { _ in nil } {
        didSet { editor.mediaURL = mediaURL; kindEditor.mediaURL = mediaURL }
    }
    /// The morph points window, while one is open.
    private var points: MorphPointsWindowController?
    /// The map route window, while one is open.
    private var route: MapRouteWindowController?

    /// Open Projector, from the header button.
    var openProjector: () -> Void = {}
    /// Close Projector, from the header button.
    var closeProjector: () -> Void = {}
    /// The header's Show / Edit switch: true for edit mode. The document
    /// does the switching, as it does for the Show menu.
    var setMode: (_ editing: Bool) -> Void = { _ in }
    /// The console moved to another display, which can change where the
    /// projector may go.
    var screenChanged: () -> Void = {}
    /// What the Mac is doing that the console should warn of.
    var booth: () -> BoothConditions = { BoothConditions() }

    init(controller: ShowController) {
        self.controller = controller
        let window = ConsoleWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.backgroundColor = Desk.colour
        window.contentMinSize = NSSize(width: 900, height: 600)
        window.contentView = root
        window.initialFirstResponder = root
        // Backdrop reopens the last show itself; restored windows would
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
        root.paintDesk()
        preview.controller = controller
        controller.runner.attach(preview.surface)
        previewFrame.addSubview(preview)
        nextPreview.controller = controller
        nextPreview.runner = controller.nextRunner
        controller.nextRunner.attach(nextPreview.surface)
        nextFrame.addSubview(nextPreview)

        runAgainButton.target = self
        runAgainButton.action = #selector(runAgainPressed)
        gotoField.font = Desk.mono(12.5)
        gotoField.placeholderString = "e.g. P12"
        gotoField.delegate = self
        gotoField.bezelStyle = .roundedBezel

        header.state.onGo = { [weak self] in self?.goPressed() }
        header.state.onOpenProjector = { [weak self] in self?.openProjectorPressed() }
        header.state.onCloseProjector = { [weak self] in self?.closeProjectorPressed() }
        header.state.onMode = { [weak self] editing in self?.modeChosen(editing) }
        header.state.onAddCue = { [weak self] kind in self?.addCueChosen(kind) }
        header.state.onShowSettings = { [weak self] on in
            guard let self else { return }
            self.window?.makeFirstResponder(self.root)
            self.setShowSettings(on)
        }
        showSettingsPanel.onTextScale = { [weak controller] value, continuous in
            controller?.setTextScale(value, coalescing: continuous)
        }
        showSettingsPanel.onTitle = { [weak controller] title in controller?.setTitle(title, coalescing: true) }
        showSettingsPanel.onGeometry = { [weak controller] g in controller?.setGeometry(g, coalescing: true) }
        showSettingsPanel.onGuides = { [weak controller] on in controller?.showsGuides = on }
        showSettingsPanel.finishedEditing = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.root)
        }
        // An edit still open is finished first, so it lands on the cue it was
        // made for rather than the one the click stands by.
        cueList.onClick = { [weak self] id in
            guard let self else { return }
            self.window?.makeFirstResponder(self.root)
            self.selectedTransition = nil
            self.showingShowSettings = false
            self.controller.standBy(id)
            self.refresh()
        }
        cueList.onTransitionClick = { [weak self] id in
            guard let self else { return }
            self.window?.makeFirstResponder(self.root)
            self.selectedTransition = id
            self.showingShowSettings = false
            self.refresh()
        }
        cueList.onStepClick = { [weak self] id, step in
            guard let self else { return }
            self.window?.makeFirstResponder(self.root)
            self.selectedTransition = nil
            self.showingShowSettings = false
            self.controller.standBy(id, step: step)
            self.refresh()
        }
        cueList.onDrop = { [weak self] url, id in self?.importMedia(url, id, nil) }
        cueList.onDropFiles = { [weak self] urls, position in self?.filesDropped(urls, at: position) }
        cueList.onDelete = { [weak controller] id in controller?.deleteCue(id) }
        cueList.onDuplicate = { [weak self] id in self?.duplicateCue(id) }
        cueList.onClearTransition = { [weak controller] id in
            controller?.edit("Clear Transition") { show in
                if let i = show.cues.firstIndex(where: { $0.id == id }) { show.cues[i].transition = .standard }
            }
        }
        cueList.onMoveCue = { [weak controller] id, row in controller?.moveCue(id, before: row) }
        cueList.onRenumberAll = { [weak self] in self?.confirmRenumber() }
        for panel in [editor, kindEditor] {
            panel.controller = controller
            panel.importMedia = { [weak self] url, id, slot in self?.importMedia(url, id, slot) }
            panel.chooseMedia = { [weak self] id, slot in self?.chooseMedia(id, slot) }
            panel.editPoints = { [weak self] id, stage in self?.showPoints(for: id, stage: stage) }
            panel.editRoute = { [weak self] id in self?.showRoute(for: id) }
            panel.finishedEditing = { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self.root)
            }
        }
        kindEditor.onSetting = { [weak controller] key, value, continuous in
            guard let controller, let id = controller.standingByCue?.id else { return }
            controller.setSetting(key, to: value, for: id, coalescing: continuous)
        }
        cueTransitions.onChange = { [weak self] key, value, continuous in
            guard let self, let id = self.selectedTransition else { return }
            self.controller.setSetting(key, to: value, for: id, coalescing: continuous)
        }
        listDivider.onDrag = { [weak self] x in
            guard let self else { return }
            self.listWidth = x
            self.root.needsLayout = true
        }
        inspectorDivider.onDrag = { [weak self] x in
            guard let self else { return }
            // The divider stands in the middle of the gap before the Inspector.
            self.inspectorWidth = self.root.bounds.width - 16 - (x + Self.columnGap / 2)
            self.root.needsLayout = true
        }
        listDivider.onFinished = { [weak self] in
            if let self { UserDefaults.standard.set(Double(self.listWidth.clamped(to: Self.listRange)), forKey: "ConsoleListWidth") }
        }
        inspectorDivider.onFinished = { [weak self] in
            if let self { UserDefaults.standard.set(Double(self.inspectorWidth.clamped(to: Self.inspectorRange)), forKey: "ConsoleInspectorWidth") }
        }
        tabs.selectedSegment = 0
        tabs.refusesFirstResponder = true
        tabs.target = self
        tabs.action = #selector(tabChosen)

        for view in [header, standby, cuesHeading, cueList, gotoLabel, gotoField, status, divider,
                     warning, previewHeading, previewFrame, nextHeading, nextFrame, runAgainButton, wordmark, inspectorFrame, editor, kindEditor, cueTransitions, showSettingsPanel, tabs, inspectorEmpty,
                     keybar, cueListEmpty, listDivider, inspectorDivider] as [NSView] {
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
            wordmark.decryptWordmark()
        }
        super.showWindow(sender)
    }

    #if DEBUG
    func holdWordmark(atFrame frame: Int) {
        wordmark.holdWordmark(atFrame: frame)
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
        controller.updateNextPreview()
        previewHeading.stringValue = live.map { "On screen: cue \($0.number)" } ?? "On screen"
        if controller.mode == .edit {
            nextHeading.stringValue = next.map { "Cue \($0.number)" } ?? "No cue selected"
        } else {
            nextHeading.stringValue = next.map { cue in
                let prompt = cue.line.trimmingCharacters(in: .whitespacesAndNewlines)
                return "Up next: cue \(cue.number)" + (prompt.isEmpty ? "" : " \u{2014} \(prompt)")
            } ?? "Up next"
        }
        runAgainButton.isEnabled = next != nil || live != nil
        // A step of a cue may stand by rather than the cue itself: GO carries
        // the live cue on or back to it, or fires another cue straight at it.
        let goPoint = controller.standingByGoPoint
        synchronizeWindowTitleWithDocumentName()

        // A transition stays selected until a cue is clicked, standing by moves on,
        // or it is no longer in the list: the first cue has none, and show mode shows none.
        if playhead.standby != lastStandby { selectedTransition = nil; showingShowSettings = false }
        if controller.mode != .edit { showingShowSettings = false }
        lastStandby = playhead.standby
        if let id = selectedTransition, controller.mode != .edit || show.index(of: id).map({ $0 < 1 }) != false {
            selectedTransition = nil
        }

        let isLive = projector.display != nil
        header.update(
            mode: controller.mode == .edit,
            lamp: playhead.blackout ? "Blacked out \u{2014} press B" : projector.lamp,
            live: isLive && !playhead.blackout,
            warn: playhead.blackout || projector.warning != nil,
            projectorOpen: projector.isOpen,
            showSettingsOn: showingShowSettings,
            goEnabled: next != nil,
            goTip: goPoint.map { $0.cue.id == playhead.live ? "Carry cue \($0.cue.number) on" : "Fire cue \($0.cue.number) at GO \($0.number)" }
                ?? next.map { "Fire cue \($0.number)" } ?? "End of the cue sheet"
        )
        standby.update(standby: next, live: live, goPoint: goPoint, entry: playhead.entry, arm: controller.standbyArmState)
        cueList.update(show: show, standby: playhead.standby, standbyStep: playhead.standbyStep, live: playhead.live,
                       taken: playhead.goPointsTaken, issues: Set(show.issues.flatMap(\.cues)), editing: controller.mode == .edit,
                       selectedTransition: selectedTransition)
        let editing = controller.mode == .edit ? controller.standingByCue : nil
        editor.update(cue: editing, goPoint: controller.standingByGoPoint)
        kindEditor.update(cue: editing, goPoint: controller.standingByGoPoint)
        cueTransitions.update(cue: selectedTransition.flatMap { show[$0] })
        // The second tab is named for the kind of cue standing by, so what
        // it holds is plain before it is opened.
        let kindTab = editing.map(\.kind.heading) ?? "Settings"
        if tabs.label(forSegment: 1) != kindTab {
            tabs.setLabel(kindTab, forSegment: 1)
            tabs.sizeToFit()
            root.needsLayout = true
        }

        status.stringValue = controller.message ?? ""
        warning.messages = booth().warnings(mode: controller.mode, projector: projector)
        showSettingsPanel.update(title: show.title, fallback: document?.displayName ?? "Untitled",
                                 settings: show.settings, guidesOn: controller.showsGuides, outputAspect: previewAspect)
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
        let noCues = controller.show.cues.isEmpty
        // The key reference has nothing to refer to until there are cues.
        let headerHeight: CGFloat = 54, keybarHeight: CGFloat = noCues ? 0 : 40
        keybar.isHidden = noCues
        let leftWidth = listWidth.clamped(to: Self.listRange)
        header.frame = NSRect(x: 0, y: 0, width: b.width, height: headerHeight)
        keybar.frame = NSRect(x: 0, y: b.height - keybarHeight, width: b.width, height: keybarHeight)
        let top = headerHeight + 1, bottom = b.height - keybarHeight

        // Left: the cue list, Go to, and the status line, or with no cues,
        // just a note.
        for view in [cuesHeading, cueList, gotoLabel, gotoField, status] as [NSView] { view.isHidden = noCues }
        cueListEmpty.isHidden = !noCues
        cueListEmpty.stringValue = controller.mode == .edit
            ? "No cues yet. Add one with Add Cue at the top."
            : "No cues yet. Switch to Edit mode to add some."
        centre(cueListEmpty, in: NSRect(x: 16, y: top, width: leftWidth - 32, height: max(0, bottom - top)))
        cuesHeading.frame = NSRect(x: 16, y: top + 15, width: leftWidth - 32, height: 18)
        let statusHeight = Desk.height(of: status, width: leftWidth - 32)
        status.frame = NSRect(x: 16, y: bottom - 12 - statusHeight, width: leftWidth - 32, height: statusHeight)
        let gotoY = status.frame.minY - (statusHeight > 0 ? 10 : 0) - 26
        gotoLabel.frame = NSRect(x: 16, y: gotoY + 4, width: 84, height: 18)
        gotoField.frame = NSRect(x: 104, y: gotoY, width: leftWidth - 120, height: 24)
        let listTop = cuesHeading.frame.maxY + 9
        cueList.frame = NSRect(x: 6, y: listTop, width: leftWidth - 12, height: max(0, gotoY - 12 - listTop))
        divider.frame = NSRect(x: leftWidth, y: top - 1, width: 1, height: bottom - top + 1)

        // Right: warnings, the previews, and in edit mode the Inspector.
        let x = leftWidth + 1 + 16, width = b.width - x - 16
        let regionTop = top + 16
        let headingHeight: CGFloat = 27, gap = Self.columnGap
        let editing = controller.mode == .edit
        // In edit mode with nothing standing by there is no cue to inspect,
        // so the message stands alone where the tabs would be.
        let settingsOn = editing && showingShowSettings
        let transitionSelected = editing && !settingsOn && selectedTransition != nil
        let inspecting = editing && !settingsOn && !transitionSelected && controller.standingByCue != nil
        showSettingsPanel.isHidden = !settingsOn
        tabs.isHidden = !inspecting
        for (i, panel) in inspectorPanels.enumerated() { panel.isHidden = !inspecting || i != tabs.selectedSegment }
        cueTransitions.isHidden = !transitionSelected
        inspectorEmpty.isHidden = !editing || settingsOn || inspecting || transitionSelected
        // The Inspector is always there: in edit mode it edits the cue
        // standing by, and in show mode it says what stands by and what is on screen.
        standby.isHidden = editing
        let tabsSize = tabs.fittingSize

        listDivider.frame = NSRect(x: leftWidth - 4, y: top, width: 9, height: max(0, bottom - top))
        // The Inspector is a column of its own, full height, so a long
        // panel scrolls rather than shrinking the pictures.
        let editorWidth = inspectorWidth.clamped(to: Self.inspectorRange)
            .clamped(to: 0...max(0, width - gap - Self.previewMinWidth))
        let previewWidth = width - editorWidth - gap
        let editorX = x + previewWidth + gap
        let region = NSRect(x: editorX, y: regionTop, width: editorWidth, height: max(0, bottom - 16 - regionTop))
        // A single line separates the Inspector from the previews, as the
        // cue list is separated; the Inspector's contents sit beside it.
        let lineX = editorX - gap / 2
        inspectorFrame.frame = NSRect(x: lineX, y: top - 1, width: 1, height: bottom - top + 1)
        let column = NSRect(x: lineX + 1, y: top, width: max(0, b.width - lineX - 1), height: max(0, bottom - top))
        inspectorDivider.frame = NSRect(x: editorX - gap / 2 - 4, y: regionTop, width: 9, height: region.height)
        if editing {
            let inner = column.insetBy(dx: Self.inspectorPadding, dy: Self.inspectorPadding)
            centre(inspectorEmpty, in: inner)
            tabs.frame = NSRect(x: inner.minX, y: inner.minY, width: tabsSize.width, height: tabsSize.height)
            let panelTop = inner.minY + tabsSize.height + 10
            let panelFrame = NSRect(x: inner.minX, y: panelTop, width: inner.width, height: max(0, inner.maxY - panelTop))
            for panel in inspectorPanels { panel.frame = panelFrame }
            cueTransitions.frame = inner
            showSettingsPanel.frame = inner
        } else {
            // The panel pads itself.
            standby.frame = NSRect(x: region.minX, y: region.minY, width: region.width,
                                   height: min(standby.height(width: region.width), region.height))
        }
        // The warning belongs to the previews' column; the Inspector runs full height beside it.
        var y = regionTop
        warning.isHidden = warning.messages.isEmpty
        if !warning.isHidden {
            let h = warning.height(width: previewWidth)
            warning.frame = NSRect(x: x, y: y, width: previewWidth, height: h)
            y += h + 14
        }
        placePreview(x: x, y: y, width: previewWidth, available: bottom - 16 - y - headingHeight,
                     headingHeight: headingHeight)
    }

    /// The space between the previews and the Inspector, where its divider stands.
    private static let columnGap: CGFloat = 24

    /// Centres a wrapping label in the space it is given, across and down.
    private func centre(_ label: NSTextField, in rect: NSRect) {
        // Narrow enough that a line of it doesn't run the whole column.
        let width = min(rect.width, 320)
        let h = label.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude)).height
        label.frame = NSRect(x: rect.midX - width / 2, y: rect.midY - h / 2, width: width, height: h)
    }

    /// Space between the Inspector panel's edge and what it holds.
    private static let inspectorPadding: CGFloat = 16

    /// The preview, as large as its space allows at the projector's shape,
    /// centred in it, with its heading just above its corner.
    private func placePreview(x: CGFloat, y: CGFloat, width: CGFloat, available: CGFloat, headingHeight: CGFloat) {
        let gap: CGFloat = 14
        if controller.mode == .edit {
            // The selected cue alone, as large as the space allows, with a
            // button under it to run it again.
            previewHeading.isHidden = true
            previewFrame.isHidden = true
            // With no cue selected the wordmark takes the place instead.
            let empty = controller.standingByCue == nil
            wordmark.isHidden = !empty
            nextHeading.isHidden = empty
            nextFrame.isHidden = empty
            runAgainButton.isHidden = empty
            if empty {
                let inset: CGFloat = 24
                wordmark.frame = NSRect(x: x + inset, y: y, width: max(0, width - inset * 2), height: max(0, available))
                return
            }
            let buttonHeight: CGFloat = 32
            let room = max(0, available - headingHeight - gap - buttonHeight)
            let w = min(width, (room * previewAspect).rounded(.down))
            let h = (w / previewAspect).rounded()
            let total = headingHeight + h + gap + buttonHeight
            let top = y + max(0, ((available + headingHeight - total) / 2).rounded())
            let left = x + ((width - w) / 2).rounded()
            nextHeading.frame = NSRect(x: left, y: top, width: w, height: 18)
            nextFrame.frame = NSRect(x: left, y: top + headingHeight, width: w, height: h)
            nextPreview.frame = nextFrame.bounds.insetBy(dx: 1, dy: 1)
            let size = runAgainButton.fittingSize
            runAgainButton.frame = NSRect(x: x + ((width - size.width) / 2).rounded(), y: nextFrame.frame.maxY + gap,
                                          width: size.width, height: buttonHeight)
            return
        }
        previewHeading.isHidden = false
        previewFrame.isHidden = false
        runAgainButton.isHidden = true
        wordmark.isHidden = true
        nextHeading.isHidden = false
        nextFrame.isHidden = false
        // The live preview, and under it the up-next preview, smaller, both
        // centred across the space and together centred down it.
        let ratio: CGFloat = 0.6
        let room = max(0, available - headingHeight - gap)
        let w = min(width, (room * previewAspect / (1 + ratio)).rounded(.down))
        let h = (w / previewAspect).rounded()
        let nw = (w * ratio).rounded(), nh = (nw / previewAspect).rounded()
        let total = headingHeight + h + gap + headingHeight + nh
        let top = y + max(0, ((available + headingHeight - total) / 2).rounded())
        let left = x + ((width - w) / 2).rounded()
        previewHeading.frame = NSRect(x: left, y: top, width: w, height: 18)
        previewFrame.frame = NSRect(x: left, y: top + headingHeight, width: w, height: h)
        preview.frame = previewFrame.bounds.insetBy(dx: 1, dy: 1)
        let nextLeft = x + ((width - nw) / 2).rounded(), nextTop = previewFrame.frame.maxY + gap
        nextHeading.frame = NSRect(x: nextLeft, y: nextTop, width: nw, height: 18)
        nextFrame.frame = NSRect(x: nextLeft, y: nextTop + headingHeight, width: nw, height: nh)
        nextPreview.frame = nextFrame.bounds.insetBy(dx: 1, dy: 1)
    }

    @objc private func runAgainPressed() {
        controller.rerun()
    }

    // MARK: Actions

    private func goPressed() {
        controller.go()
        window?.makeFirstResponder(root)
    }

    private func openProjectorPressed() {
        openProjector()
        window?.makeFirstResponder(root)
    }

    private func closeProjectorPressed() {
        closeProjector()
        window?.makeFirstResponder(root)
    }

    /// A new cue stands by, and the Cue tab opens on it to be filled in.
    private func addCueChosen(_ kind: Cue.Kind) {
        guard controller.addCue(kind) != nil else { return }
        showInspectorTab(0)
        window?.makeFirstResponder(root)
    }

    /// Pictures and clips dropped between cues become cues there, and the
    /// first stands by with the Cue tab open on it, as Add Cue leaves it.
    private func filesDropped(_ urls: [URL], at position: Int) {
        let before = controller.show.cues.count
        addMediaCues(urls, position)
        guard controller.show.cues.count > before else { return }
        selectedTransition = nil
        showingShowSettings = false
        showInspectorTab(0)
        window?.makeFirstResponder(root)
    }

    private func modeChosen(_ editing: Bool) {
        setMode(editing)
        window?.makeFirstResponder(root)
        refresh()
    }

    @objc private func tabChosen() {
        root.needsLayout = true
        window?.makeFirstResponder(root)
    }

    /// Show Settings in the Inspector, or back to the cue standing by.
    func setShowSettings(_ on: Bool) {
        guard !on || controller.mode == .edit else { return }
        showingShowSettings = on
        if on { selectedTransition = nil }
        refresh()
    }

    /// Show › Show Settings: the show's title, text size and projection area
    /// in the Inspector, where the header's toggle shows them.
    func showShowSettings() {
        setShowSettings(true)
    }

    /// Copies a cue and stands the copy by, as adding one does.
    func duplicateCue(_ id: UUID) {
        guard controller.mode == .edit, controller.duplicateCue(id) != nil else { return }
        showInspectorTab(0)
        window?.makeFirstResponder(root)
    }

    /// Edit › Duplicate Cue: the cue standing by.
    func duplicateStandbyCue() {
        if let id = controller.playhead.standby { duplicateCue(id) }
    }

    /// Edit › Add Cue: the same sheet the header's button opens.
    func showAddCue() {
        guard controller.mode == .edit else { return }
        header.state.showingAddCue = true
    }

    /// For the snapshot tool: shows one of the Inspector's tabs.
    func showInspectorTab(_ index: Int) {
        tabs.selectedSegment = index
        root.needsLayout = true
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paintDesk()
    }

    /// The desk's own background. The window has one too, but it isn't part
    /// of this view's drawing, so a snapshot of the view alone would come
    /// out with nothing behind it.
    func paintDesk() {
        wantsLayer = true
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = Desk.colour.cgColor
        }
    }

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

extension CGFloat {
    fileprivate func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// A thin strip between two columns, dragged sideways to resize them. It
/// reports where the pointer is, in the console's own coordinates.
final class ColumnDivider: NSView {
    var onDrag: (CGFloat) -> Void = { _ in }
    var onFinished: () -> Void = {}

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        guard let superview else { return }
        onDrag(superview.convert(event.locationInWindow, from: nil).x)
    }

    override func mouseUp(with event: NSEvent) {
        onFinished()
    }
}
