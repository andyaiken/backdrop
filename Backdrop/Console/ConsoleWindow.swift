import AppKit
import BackdropCore
import QuartzCore
import BackdropStage

/// The operator's window, in one of two rooms. The Booth, show mode: the
/// rail of cues, the On stage and Next monitors, drawn by the same renderers
/// as the projector, the standby card, the GO plate and the keys. The Studio,
/// edit mode: the rail, the selected cue on the stage, and the Inspector,
/// which edits the cue standing by, its transition, or Stage setup.
///
/// Nothing in it takes keyboard focus except Go To while it is open, so the
/// show keys always reach the show: a focused button would be pressed by
/// Space, and a focused slider would eat the arrows.
@MainActor
final class ConsoleWindowController: NSWindowController, NSWindowDelegate {
    let controller: ShowController
    let preview = SurfaceView(role: .preview)
    /// The cue standing by, finished, smaller than the live preview.
    let nextPreview = SurfaceView(role: .preview)

    private let root = ConsoleRootView()
    private let header = HeaderView()
    /// Edit mode, nothing selected: the wordmark, on a screen of its own in
    /// the preview's place.
    private let wordmark = WordmarkView()
    private let wordmarkFrame = PanelView(fill: .black, border: Desk.line, radius: Desk.previewRadius)
    // The Booth.
    private let onStageMonitor = MonitorFrame()
    private let nextMonitor = MonitorFrame()
    private let onStageLabel = PanelHost(rootView: MonitorLabel(tag: "ON STAGE", tagColour: Booth.tally, filled: false, cue: ""))
    private let nextLabel = PanelHost(rootView: MonitorLabel(tag: "NEXT", tagColour: Booth.brass, filled: true, cue: ""))
    private let arrow = PanelHost(rootView: TransitionArrow(note: ""))
    private let card = PanelHost(rootView: StandbyCard())
    private let goPlate = PanelHost(rootView: GoPlate(tip: ""))
    private let keyRow = PanelHost(rootView: KeyRow())
    /// Before the first GO, in the On stage monitor's place.
    private let beginners = PanelHost(rootView: BeginnersView(checks: []))
    private let stopBands = StopBands()
    private let cautionLine = CautionLine()
    /// The caution whose lamp was last clicked, shown on the caution line
    /// while it lasts.
    private var selectedCaution: BoothWarning.ID?
    /// The card's number, sized for the card at the last layout.
    private var cardNumberSize: CGFloat = 104
    private let cuesHeading = Desk.label("CUES", font: Desk.sans(11, .semibold), colour: Desk.dim)
    private let cuesCount: NSTextField = {
        let label = Desk.label("", font: Desk.mono(11), colour: Desk.dim)
        label.alignment = .right
        return label
    }()
    let cueList = CueListView()
    /// Go To, while it is open: G, or a click on the standby number.
    private var goTo: GoToPanel?
    /// Every key, while ? shows it.
    private var keyHelp: KeyHelp?
    /// Watches clicks while Go To or the key help is open, to close them.
    private var clickMonitor: Any?
    /// Where Go To goes: over the standby card in the Booth, under the
    /// stage's header in the Studio.
    private var goToAnchor: NSRect = .zero
    private let status = StatusLine()
    private let divider = PanelView(fill: Desk.line)
    /// The tints behind the cue list and the Inspector, either side of the
    /// previews.
    private let listColumn = PanelView(fill: Desk.column)
    private let inspectorColumn = PanelView(fill: Desk.column)
    /// The Inspector's outline, around its forms, so it reads as a
    /// place even with nothing in it. It has no fill: the desk shows through.
    private let inspectorFrame = PanelView(fill: Desk.line)
    /// The Studio: which cue is on the stage, and Run again.
    private let stageHeader = PanelHost(rootView: StageHeader(number: "", kind: ""))
    /// The Studio with no cues: the empty model box.
    private let bareStage = BareStage()
    /// The Studio's storyboard: every cue's finished frame, in the stage's place.
    private let storyboardView = StoryboardView()
    /// List | Storyboard, at the top of the rail in the Studio.
    private let railSwitch: NSSegmentedControl = {
        let control = NSSegmentedControl(labels: ["List", "Storyboard"], trackingMode: .selectOne, target: nil, action: nil)
        control.controlSize = .small
        control.refusesFirstResponder = true
        return control
    }()
    /// The storyboard is showing, kept between launches.
    private var showingStoryboard = UserDefaults.standard.bool(forKey: "ConsoleStoryboard") {
        didSet { UserDefaults.standard.set(showingStoryboard, forKey: "ConsoleStoryboard") }
    }
    /// The Studio's stage setup, over the stage.
    private let stageSetup = StageSetupOverlay()
    /// Whether the alignment guides were on before stage setup turned them
    /// on, so they go back as they were.
    private var guidesBeforeSetup: Bool?
    /// The Studio: the cue on the stage, in time.
    private let timelineView = TimelineView()
    /// The Studio: the transition into the next cue, under the timeline.
    private let joinLine = PanelHost(rootView: JoinLine())
    /// The cue the timeline shows: the one on the stage, or the one a
    /// selected transition leads into.
    private var timelineCue: UUID?
    /// Where the projector chip's live picture goes, in the header's own
    /// coordinates.
    private var chipPicture: CGRect = .zero
    private let nextFrame = PanelView(fill: .black, border: Desk.line, radius: Desk.previewRadius)
    private(set) var editor = CueEditorPanel()
    private let cueTransitions = CueSettingsPanel()
    private let showSettingsPanel = ShowSettingsPanel()
    /// The Inspector shows Stage setup rather than a cue. Choosing a cue
    /// or a transition in the list switches it off.
    private var showingStageSetup = false {
        didSet {
            guard showingStageSetup != oldValue else { return }
            // The guides come on while the area is set, and go back after.
            if showingStageSetup {
                guidesBeforeSetup = controller.showsGuides
                controller.showsGuides = true
            } else if let was = guidesBeforeSetup {
                controller.showsGuides = was
                guidesBeforeSetup = nil
            }
        }
    }
    /// The cue whose transition in is selected in the cue list, if one is.
    /// The Inspector then shows that transition alone, in place of the cue.
    private var selectedTransition: UUID?
    /// The cue that stood by at the last refresh: a different one deselects the transition.
    private var lastStandby: UUID?
    /// What the Inspector says with no cue standing by, in place of an
    /// empty form.
    private let inspectorEmpty: NSTextField = {
        let label = Desk.label("No cue selected.",
                               font: Desk.sans(12.5), colour: Desk.dim, wraps: true)
        label.alignment = .center
        return label
    }()
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
    private static let listRange = ConsoleGeometry.railRange
    private static let inspectorRange = ConsoleGeometry.inspectorRange

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
        didSet {
            editor.mediaURL = mediaURL
            cueList.thumbnails.media = mediaURL
            storyboardView.thumbnails.media = mediaURL
        }
    }
    /// The morph points editor, while it has the stage.
    private var points: MorphPointsEditor?
    /// The map route editor, while it has the stage.
    private var route: MapRouteEditor?
    /// A focus mode has the stage.
    private var focusing: Bool { points != nil || route != nil }

    /// Open Projector, from the projector's lamp or Beginners.
    var openProjector: () -> Void = {}
    /// Close Projector, from the projector's lamp.
    var closeProjector: () -> Void = {}
    /// The projector lamp's Choose Projector Display, as the Show menu has it.
    var displayItems: () -> (items: [DisplayMenu.Item], note: String?) = { ([], nil) }
    var chooseDisplay: (DisplayIdentity) -> Void = { _ in }
    /// Lock for show, and holding the lock to unlock: true for edit mode.
    /// The document does the switching, as it does for the Show menu.
    var setMode: (_ editing: Bool) -> Void = { _ in }
    /// MIDI Show Control and OSC as Settings have them, for Beginners and
    /// the GO plate.
    var showControl: () -> ShowControlStatus = {
        ShowControlStatus(mscDevice: ShowControl.shared.mscDeviceID, oscPort: ShowControl.shared.oscPort)
    }
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
        root.onDisplayOptionsChanged = { [weak self] in self?.refresh() }
        root.console = self
        root.paintDesk()
        // The pictures sit 1pt inside their frames' borders, so their corners
        // are rounded 1pt less to run alongside them.
        // Inside their frames' borders, so their corners are rounded less to
        // run alongside them.
        for surface in [preview.surface, nextPreview.surface] {
            surface.cornerRadius = MonitorFrame.radius - MonitorFrame.border
            surface.cornerCurve = .continuous
        }
        preview.controller = controller
        controller.runner.attach(preview.surface)
        onStageMonitor.hold(preview)
        onStageMonitor.tally = .onStage
        nextPreview.controller = controller
        nextPreview.runner = controller.nextRunner
        controller.nextRunner.attach(nextPreview.surface)
        nextMonitor.hold(nextPreview)
        beginners.wantsLayer = true
        beginners.layer?.cornerRadius = MonitorFrame.radius
        beginners.layer?.masksToBounds = true
        wordmarkFrame.addSubview(wordmark)

        bareStage.onDrop = { [weak self] urls in self?.filesDropped(urls, at: 0) }
        railSwitch.target = self
        railSwitch.action = #selector(railSwitched)
        storyboardView.onSelect = { [weak self] id in self?.cueList.onClick(id) }
        storyboardView.onOpen = { [weak self] id in
            guard let self else { return }
            self.showingStoryboard = false
            self.cueList.onClick(id)
        }
        stageSetup.onChange = { [weak controller] g in controller?.setGeometry(g, coalescing: true) }
        stageSetup.onFinished = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.root)
        }
        timelineView.onSetting = { [weak self] key, value, coalescing in
            guard let self, let id = self.timelineCue else { return }
            self.controller.setSetting(key, to: value, for: id, coalescing: coalescing)
        }
        timelineView.onContinue = { [weak self] ms, coalescing in
            guard let self, let id = self.timelineCue else { return }
            self.controller.updateCue(id, "Change Continue Wait", coalescing: coalescing) { cue in
                switch cue.continueMode {
                case .whenFinished: cue.continueMode = .whenFinished(waitMs: ms)
                default: cue.continueMode = .after(ms: ms)
                }
            }
        }
        timelineView.onFinished = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.root)
        }
        // Run again's playhead, in the cue's frames from GO.
        timelineView.playhead = { [weak self] in
            guard let self, let hold = self.timelineView.timeline?.holdTicks,
                  let position = self.controller.nextRunner.position(at: CACurrentMediaTime()) else { return nil }
            return position + Double(hold)
        }
        nextPreview.onStep = { [weak self] in
            guard let self, self.controller.mode == .edit, !self.timelineView.isHidden else { return }
            self.timelineView.needsDisplay = true
        }
        bareStage.onAddCue = { [weak self] in self?.showAddCue() }
        header.state.onStandBy = { [weak self] id in self?.cueList.onClick(id) }
        header.state.onPictureFrame = { [weak self] frame in
            guard let self, frame != self.chipPicture else { return }
            self.chipPicture = frame
            self.root.needsLayout = true
        }

        header.state.onOpenProjector = { [weak self] in self?.openProjectorPressed() }
        header.state.onCloseProjector = { [weak self] in self?.closeProjectorPressed() }
        header.state.onLock = { [weak self] in self?.modeChosen(false) }
        header.state.onUnlock = { [weak self] in self?.modeChosen(true) }
        header.state.displays = { [weak self] in self?.displayItems() ?? ([], nil) }
        header.state.onChooseDisplay = { [weak self] display in self?.chooseDisplay(display) }
        header.state.onSelectCaution = { [weak self] id in
            guard let self else { return }
            self.selectedCaution = id
            self.refresh()
        }
        header.state.onAddCue = { [weak self] kind in self?.addCueChosen(kind) }
        header.state.onShowAddCue = { [weak self] in self?.showAddCue() }
        header.state.onGalleryClosed = { [weak self] in
            guard let self else { return }
            // Closed without a pick: a + above the first cue is forgotten.
            self.addingAtStart = false
            self.window?.makeFirstResponder(self.root)
        }
        header.state.onStageSetup = { [weak self] on in
            guard let self else { return }
            self.window?.makeFirstResponder(self.root)
            self.setStageSetup(on)
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
            self.showingStageSetup = false
            self.controller.standBy(id)
            self.refresh()
        }
        cueList.onTransitionClick = { [weak self] id in
            guard let self else { return }
            self.window?.makeFirstResponder(self.root)
            self.selectedTransition = id
            self.showingStageSetup = false
            self.refresh()
        }
        cueList.onStepClick = { [weak self] id, step in
            guard let self else { return }
            self.window?.makeFirstResponder(self.root)
            self.selectedTransition = nil
            self.showingStageSetup = false
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
        cueList.onMoveBy = { [weak controller] id, offset in controller?.moveCue(id, by: offset) }
        cueList.onInsert = { [weak self] after in self?.insertCue(after: after) }
        editor.controller = controller
        editor.importMedia = { [weak self] url, id, slot in self?.importMedia(url, id, slot) }
        editor.chooseMedia = { [weak self] id, slot in self?.chooseMedia(id, slot) }
        editor.editPoints = { [weak self] id, stage in self?.showPoints(for: id, stage: stage) }
        editor.editRoute = { [weak self] id in self?.showRoute(for: id) }
        editor.finishedEditing = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.root)
        }
        editor.onSetting = { [weak controller] key, value, continuous in
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
            // The divider stands on the Inspector's left edge.
            self.inspectorWidth = self.root.bounds.width - x
            self.root.needsLayout = true
        }
        listDivider.onFinished = { [weak self] in
            if let self { UserDefaults.standard.set(Double(self.listWidth.clamped(to: Self.listRange)), forKey: "ConsoleListWidth") }
        }
        inspectorDivider.onFinished = { [weak self] in
            if let self { UserDefaults.standard.set(Double(self.inspectorWidth.clamped(to: Self.inspectorRange)), forKey: "ConsoleInspectorWidth") }
        }
        for view in [listColumn, inspectorColumn, header, cuesHeading, cuesCount, cueList, status, divider,
                     stopBands, cautionLine, onStageMonitor, nextMonitor, onStageLabel, nextLabel, arrow, card, goPlate, keyRow,
                     beginners, stageHeader, nextFrame, bareStage, timelineView, joinLine, storyboardView, railSwitch, wordmarkFrame, inspectorFrame, editor, cueTransitions,
                     showSettingsPanel, inspectorEmpty, cueListEmpty, listDivider, inspectorDivider] as [NSView] {
            root.addSubview(view)
        }
        // Over the stage, whatever it shows.
        root.addSubview(stageSetup)
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
            bareStage.decrypt()
        }
        super.showWindow(sender)
    }

    #if DEBUG
    func holdWordmark(atFrame frame: Int, letters: TitleLetters? = nil) {
        wordmark.holdWordmark(atFrame: frame, letters: letters)
        bareStage.holdWordmark(atFrame: frame)
    }
    #endif

    /// Edit Points…: the morph points editor takes the stage, on one of the
    /// morph's stages, until Done or Escape.
    func showPoints(for id: UUID, stage: Int = 0) {
        guard controller.mode == .edit, let cue = controller.show[id], cue.kind == .morph else { return }
        if points?.cueID != id {
            closeFocus()
            let editor = MorphPointsEditor(controller: controller, cueID: id, mediaURL: mediaURL)
            editor.onClose = { [weak self] in self?.closeFocus() }
            root.addSubview(editor, positioned: .below, relativeTo: stageSetup)
            points = editor
        }
        points?.show(stage: stage)
        root.needsLayout = true
    }

    /// Edit Route…: the route editor takes the stage, until Done or Escape.
    func showRoute(for id: UUID) {
        guard controller.mode == .edit, let cue = controller.show[id], cue.kind == .map else { return }
        if route?.cueID != id {
            closeFocus()
            let editor = MapRouteEditor(controller: controller, cueID: id, mediaURL: mediaURL)
            editor.onClose = { [weak self] in self?.closeFocus() }
            root.addSubview(editor, positioned: .below, relativeTo: stageSetup)
            route = editor
        }
        root.needsLayout = true
    }

    #if DEBUG
    func closeFocusForSnapshot() { closeFocus() }

    func showStoryboardForSnapshot(_ on: Bool) {
        showingStoryboard = on
        refresh()
    }
    #endif

    @objc private func railSwitched() {
        showingStoryboard = railSwitch.selectedSegment == 1
        window?.makeFirstResponder(root)
        refresh()
    }

    private var noCuesYet: Bool { controller.show.cues.isEmpty }

    /// The stage back from a focus mode, and the keyboard to the show.
    private func closeFocus() {
        guard focusing else { return }
        // On the next turn: an editor may be closing itself mid-refresh.
        let editors: [NSView?] = [points, route]
        points = nil
        route = nil
        DispatchQueue.main.async { editors.forEach { $0?.removeFromSuperview() } }
        window?.makeFirstResponder(root)
        root.needsLayout = true
    }

    func refresh() {
        refreshPending = false
        if controller.mode != .edit { closeFocus() }
        points?.refresh()
        route?.refresh()
        let show = controller.show, playhead = controller.playhead, projector = controller.projector
        let live = playhead.live.flatMap { show[$0] }
        let next = playhead.standby.flatMap { show[$0] }
        controller.updateNextPreview()
        // Only edit mode captions its preview. In show mode the Inspector
        // beside each preview says what it is.
        if let cue = controller.standingByCue {
            stageHeader.rootView = StageHeader(number: cue.number, kind: cue.kind.heading,
                                               onRunAgain: { [weak self] in self?.controller.rerun() })
        }
        refreshTimeline()
        // A step of a cue may stand by rather than the cue itself: GO carries
        // the live cue on or back to it, or fires another cue straight at it.
        let goPoint = controller.standingByGoPoint
        synchronizeWindowTitleWithDocumentName()

        // A transition stays selected until a cue is clicked, standing by moves on,
        // or it is no longer in the list: the first cue has none, and show mode shows none.
        if playhead.standby != lastStandby { selectedTransition = nil; showingStageSetup = false }
        if controller.mode != .edit { showingStageSetup = false }
        lastStandby = playhead.standby
        if let id = selectedTransition, controller.mode != .edit || show.index(of: id).map({ $0 < 1 }) != false {
            selectedTransition = nil
        }

        applyRoom()

        let warnings = booth().warnings(mode: controller.mode, projector: projector)
        let cautions = warnings.filter { $0.tier == .caution }
        if let id = selectedCaution, !cautions.contains(where: { $0.id == id }) { selectedCaution = nil }
        stopBands.stops = warnings.filter { $0.tier == .stop }
        cautionLine.caution = controller.mode == .show
            ? cautions.first { $0.id == selectedCaution } ?? cautions.first : nil

        header.update(
            mode: controller.mode == .edit,
            lamp: playhead.blackout ? "Blacked out \u{2014} press B" : projector.lamp,
            live: projector.display != nil && !playhead.blackout,
            warn: projector.warning != nil,
            blackout: playhead.blackout,
            projectorOpen: projector.isOpen,
            stageSetupOn: showingStageSetup,
            cautions: cautions,
            selectedCaution: selectedCaution,
            issues: show.issues.enumerated().map { i, issue in
                SheetHealthIssue(id: i, cue: issue.cues.first, message: show.message(for: issue))
            }
        )
        if controller.mode == .show { refreshBooth(live: live, next: next, goPoint: goPoint) }
        // Each cue's issues, in the sheet's words, joined where it has several.
        var issues: [UUID: [String]] = [:]
        for issue in show.issues {
            for id in issue.cues { issues[id, default: []].append(show.message(for: issue)) }
        }
        cueList.update(show: show, standby: playhead.standby, standbyStep: playhead.standbyStep, live: playhead.live,
                       taken: playhead.goPointsTaken, issues: issues.mapValues { $0.joined(separator: " \u{00B7} ") },
                       room: controller.mode, selectedTransition: selectedTransition)
        let heading = NSMutableAttributedString(string: "CUES", attributes: [
            .font: Desk.sans(11, .semibold), .foregroundColor: Desk.room(controller.mode).dim, .kern: 2,
        ])
        cuesHeading.attributedStringValue = heading
        cuesCount.stringValue = show.cues.isEmpty ? "" : "\(show.cues.count)"
        cuesCount.textColor = Desk.room(controller.mode).dim
        let editing = controller.mode == .edit ? controller.standingByCue : nil
        editor.update(cue: editing, goPoint: controller.standingByGoPoint)
        cueTransitions.update(cue: selectedTransition.flatMap { show[$0] })

        status.update(message: controller.message, origin: controller.messageOrigin, room: Desk.room(controller.mode))
        showSettingsPanel.update(title: show.title, fallback: document?.displayName ?? "Untitled",
                                 settings: show.settings, guidesOn: controller.showsGuides, outputAspect: previewAspect)
        root.needsLayout = true
    }

    /// The timeline shows the cue on the stage, or with a transition
    /// selected, the cue it leads into, with its In bar lit. The join line
    /// under it is the transition into the cue after.
    private func refreshTimeline() {
        let show = controller.show
        let cue = selectedTransition.flatMap { show[$0] } ?? controller.standingByCue
        timelineCue = cue?.id
        guard controller.mode == .edit, let cue, let index = show.index(of: cue.id) else {
            timelineView.show(nil, cue: nil)
            return
        }
        timelineView.show(CueTimeline(cue: cue, show: show.settings, isFirst: index == 0), cue: cue)
        timelineView.transitionSelected = selectedTransition != nil
        let next = show.cues.indices.contains(index + 1) ? show.cues[index + 1] : nil
        joinLine.rootView = JoinLine(into: next, onClick: { [weak self] in
            guard let self, let next else { return }
            self.cueList.onTransitionClick(next.id)
        })
    }

    /// The Booth's monitors, card and plate, for what is live and next.
    private func refreshBooth(live: Cue?, next: Cue?, goPoint: ShowController.StandingByGoPoint?) {
        let show = controller.show, playhead = controller.playhead
        let arm = controller.standbyArmState
        let reach = playhead.standby.map { show.reach(from: $0) } ?? []
        // What stands by: the cue, or the step of one.
        let nextCue = goPoint?.cue ?? next
        let carriesOn = goPoint.map { $0.cue.id == playhead.live } ?? false

        onStageLabel.rootView = MonitorLabel(tag: "ON STAGE", tagColour: Booth.tally, filled: false,
                                             cue: live.map { "\($0.number) \u{00B7} \(CueText.name($0))" } ?? "Nothing yet",
                                             runAgain: live == nil ? nil : { [weak self] in self?.controller.rerun() })
        nextLabel.rootView = MonitorLabel(tag: "NEXT", tagColour: Booth.brass, filled: true,
                                          cue: nextCue.map { "\($0.number) \u{00B7} \(CueText.name($0))" } ?? "End of the cue sheet")
        onStageMonitor.slate = playhead.blackout ? MonitorFrame.Slate(title: "BLACKOUT", detail: "press B to restore") : nil
        nextMonitor.slate = next == nil ? MonitorFrame.Slate(title: "End of the cue sheet", detail: nil) : nil
        nextMonitor.tally = switch arm {
        case .arming?: .arming
        case .failed?: .failed
        default: .next
        }
        arrow.rootView = TransitionArrow(note: carriesOn ? "carries on" : (next.map(CueText.transitionNote) ?? ""))
        arrow.isHidden = next == nil

        card.rootView = StandbyCard(standby: next, live: live, goPoint: goPoint, stepsTaken: playhead.goPointsTaken,
                                    arm: arm, reach: reach, numberSize: cardNumberSize,
                                    onGoTo: { [weak self] in self?.showGoTo() })
        let tip = CueText.goTip(goPoint: goPoint, live: playhead.live, next: next)
        let then: String? = {
            if let goPoint {
                return goPoint.number < goPoint.count ? "then waits for GO \(goPoint.number + 1)" : nil
            }
            if let next, !next.goPoints().isEmpty { return "then waits for GO 1" }
            return CueText.reach(reach)
        }()
        let control = showControl()
        goPlate.rootView = GoPlate(tip: tip, then: then, remote: control.mscDevice != nil || control.oscPort != nil,
                                   enabled: next != nil, onGo: { [weak self] in self?.goPressed() })

        // Beginners, until anything is live.
        if live == nil {
            let issues = show.issues.map { show.message(for: $0) }
            let armed = next.flatMap { cue in arm.map { (number: cue.number, isFeed: cue.kind == .feed, state: $0) } }
            beginners.rootView = BeginnersView(
                checks: booth().checklist(mode: controller.mode, projector: controller.projector, showControl: control,
                                          issues: issues, arm: armed),
                onOpenProjector: { [weak self] in self?.openProjectorPressed() })
        }
    }

    // MARK: The room

    /// The mode at the last refresh, so a change of room can be seen.
    private var lastMode: ShowController.Mode?

    /// The Booth is always dark, and high-contrast dark with Increase
    /// Contrast, so its controls, menus, popovers and sheets are too. The
    /// Studio follows the Mac. Changing room cross-fades, unless motion is
    /// reduced.
    private func applyRoom() {
        guard let window else { return }
        let mode = controller.mode
        if let lastMode, lastMode != mode, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.3
            root.layer?.add(fade, forKey: "room")
        }
        lastMode = mode
        let appearance = mode == .show ? Booth.appearance : nil
        if window.appearance?.name != appearance?.name { window.appearance = appearance }
        let room = Desk.room(mode)
        window.backgroundColor = room.background
        listColumn.fill = room.panel
        divider.fill = room.line
        root.paintDesk()
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
        let editing = controller.mode == .edit
        // Stops go in a band across the full width under the header, and
        // in the Booth a caution's line under them; everything below moves
        // down for them.
        stopBands.isHidden = stopBands.stops.isEmpty
        let bandsHeight = stopBands.isHidden ? 0 : stopBands.height(width: b.width)
        cautionLine.isHidden = editing || cautionLine.caution == nil
        let lineHeight = cautionLine.isHidden ? 0 : CautionLine.height
        let stops = bandsHeight + lineHeight

        let rail: NSRect, bands: NSRect
        if editing {
            let tracks = showsTimeline ? timelineView.timeline.map { TimelineView.rows($0).count } : nil
            let f = ConsoleGeometry.studio(in: b, railWidth: listWidth, inspectorWidth: inspectorWidth,
                                           outputAspect: previewAspect, timelineTracks: tracks, stopBands: stops)
            header.frame = f.toolbar
            rail = f.rail
            bands = f.stopBands
            layoutStudio(f)
        } else {
            let f = ConsoleGeometry.booth(in: b, railWidth: listWidth, outputAspect: previewAspect, stopBands: stops)
            header.frame = f.header
            rail = f.rail
            bands = f.stopBands
            layoutBooth(f, noCues: noCues)
        }
        stopBands.frame = NSRect(x: bands.minX, y: bands.minY, width: bands.width, height: bandsHeight)
        cautionLine.frame = NSRect(x: bands.minX, y: bands.minY + bandsHeight, width: bands.width, height: lineHeight)
        layoutRail(rail, noCues: noCues)
        layoutOverlays()
    }

    /// The rail: the cue list, Go to, and the status line, or with no cues,
    /// just a note. In edit mode the empty list stays, under the note, so
    /// pictures and clips can be dropped in to start the sheet.
    private func layoutRail(_ rail: NSRect, noCues: Bool) {
        let inner = rail.width - 32
        cuesHeading.isHidden = noCues
        // The Studio has the List | Storyboard switch there instead.
        cuesCount.isHidden = noCues || controller.mode == .edit
        cueList.isHidden = noCues && controller.mode != .edit
        cueListEmpty.isHidden = !noCues
        cueListEmpty.stringValue = controller.mode == .edit
            ? "No cues yet. Add one with Add Cue at the top, or drop pictures and clips here."
            : "No cues yet. Hold the lock to edit, then add some."
        centre(cueListEmpty, in: rail.insetBy(dx: 16, dy: 0))
        cuesHeading.frame = NSRect(x: rail.minX + 16, y: rail.minY + 15, width: inner - 40, height: 18)
        cuesCount.frame = NSRect(x: rail.maxX - 56, y: rail.minY + 15, width: 40, height: 18)
        let statusHeight = status.height(width: rail.width - 24)
        status.frame = NSRect(x: rail.minX + 12, y: rail.maxY - 12 - statusHeight, width: rail.width - 24, height: statusHeight)
        let listBottom = status.frame.minY - (statusHeight > 0 ? 10 : 0)
        let listTop = cuesHeading.frame.maxY + 9
        cueList.frame = NSRect(x: rail.minX + 6, y: listTop, width: rail.width - 12, height: max(0, listBottom - listTop))
        listColumn.frame = rail
        divider.frame = NSRect(x: rail.maxX, y: rail.minY - 1, width: ConsoleGeometry.divider, height: rail.height + 1)
        listDivider.frame = NSRect(x: rail.maxX - 4, y: rail.minY, width: 9, height: rail.height)
    }

    /// Show mode: the two monitors side by side, the standby card under
    /// them, then GO and the keys.
    private func layoutBooth(_ f: ConsoleGeometry.BoothFrames, noCues: Bool) {
        for view in [inspectorColumn, inspectorFrame, inspectorDivider, editor, cueTransitions, showSettingsPanel,
                     inspectorEmpty, wordmarkFrame, stageHeader, nextFrame, bareStage, timelineView, joinLine, stageSetup, storyboardView,
                     railSwitch] as [NSView] {
            view.isHidden = true
        }
        let nothingLive = controller.playhead.live == nil
        for view in [nextMonitor, onStageLabel, nextLabel, card, goPlate] as [NSView] { view.isHidden = false }
        // Before the first GO, Beginners takes the On stage monitor's place.
        onStageMonitor.isHidden = nothingLive
        beginners.isHidden = !nothingLive
        // The keys have nothing to refer to until there are cues.
        keyRow.isHidden = noCues
        if nextPreview.superview !== nextMonitor { nextMonitor.hold(nextPreview) }
        // The live picture is the On stage monitor's again.
        if preview.superview !== onStageMonitor {
            onStageMonitor.hold(preview)
            preview.surface.cornerRadius = MonitorFrame.radius - MonitorFrame.border
        }

        onStageLabel.frame = f.onStageLabel
        onStageMonitor.frame = f.onStage
        beginners.frame = f.onStage
        nextLabel.frame = f.nextLabel
        nextMonitor.frame = f.next
        arrow.frame = f.arrow
        card.frame = f.card
        goPlate.frame = f.goPlate
        keyRow.frame = f.keyRow
        if cardNumberSize != f.cardNumberSize {
            cardNumberSize = f.cardNumberSize
            DispatchQueue.main.async { [weak self] in self?.setNeedsRefresh() }
        }
        goToAnchor = f.card
    }

    /// Edit mode: the selected cue on the stage, as large as it fits, and the
    /// Inspector, a column of its own, full height, so a long panel scrolls
    /// rather than shrinking the stage.
    private func layoutStudio(_ f: ConsoleGeometry.StudioFrames) {
        goToAnchor = NSRect(x: f.canvas.minX, y: f.canvasHeader.maxY, width: f.canvas.width, height: f.canvas.height)
        for view in [onStageMonitor, nextMonitor, onStageLabel, nextLabel, arrow, card, goPlate, keyRow, beginners] as [NSView] {
            view.isHidden = true
        }
        // The stage shows the cue standing by, drawn by the same surface the
        // Booth's Next monitor uses: it is the console's clock, and must
        // always be on screen.
        if nextPreview.superview !== nextFrame { nextFrame.addSubview(nextPreview) }
        for view in [inspectorColumn, inspectorFrame, inspectorDivider] as [NSView] { view.isHidden = false }
        let settingsOn = showingStageSetup
        let transitionSelected = !settingsOn && selectedTransition != nil
        let inspecting = !settingsOn && !transitionSelected && controller.standingByCue != nil
        showSettingsPanel.isHidden = !settingsOn
        editor.isHidden = !inspecting
        cueTransitions.isHidden = !transitionSelected
        // With nothing standing by there is no cue to inspect, so the message
        // stands alone where the form would be.
        inspectorEmpty.isHidden = settingsOn || inspecting || transitionSelected

        inspectorColumn.frame = f.inspector
        inspectorFrame.frame = NSRect(x: f.inspector.minX - ConsoleGeometry.divider, y: f.inspector.minY - 1,
                                      width: ConsoleGeometry.divider, height: f.inspector.height + 1)
        inspectorDivider.frame = NSRect(x: f.inspector.minX - 5, y: f.inspector.minY, width: 9, height: f.inspector.height)
        let inner = f.inspector.insetBy(dx: Self.inspectorPadding, dy: Self.inspectorPadding)
        centre(inspectorEmpty, in: inner)
        editor.frame = inner
        cueTransitions.frame = inner
        showSettingsPanel.frame = inner

        // The projector chip shows what the projector shows: the same
        // surface as the Booth's On stage monitor, small, over its slot.
        if preview.superview !== root {
            preview.removeFromSuperview()
            root.addSubview(preview, positioned: .above, relativeTo: header)
            preview.surface.cornerRadius = 3
        }
        preview.isHidden = chipPicture.isEmpty
        // The chip measures itself in the window's coordinates, from its
        // top left corner, title bar and all.
        let titleBar = (window?.frame.height ?? root.bounds.height) - root.bounds.height
        preview.frame = chipPicture.offsetBy(dx: 0, dy: -titleBar)

        // The rail's switch, and the storyboardView in the stage's place.
        railSwitch.isHidden = noCuesYet
        railSwitch.selectedSegment = showingStoryboard ? 1 : 0
        let switchSize = railSwitch.fittingSize
        railSwitch.frame = NSRect(x: f.rail.maxX - 12 - switchSize.width, y: f.rail.minY + 12,
                                  width: switchSize.width, height: switchSize.height)
        storyboardView.isHidden = !showingStoryboard || focusing || noCuesYet
        if !storyboardView.isHidden {
            storyboardView.frame = f.middle
            storyboardView.update(cues: controller.show.cues, settings: controller.show.settings, standby: controller.playhead.standby)
            for view in [stageHeader, nextFrame, wordmarkFrame, bareStage, timelineView, joinLine, stageSetup] as [NSView] {
                view.isHidden = true
            }
            // The live surface stays on screen, as the console's clock, under
            // the storyboardView.
            nextFrame.isHidden = false
            nextFrame.alphaValue = 0.01
            nextFrame.frame = NSRect(x: f.middle.minX, y: f.middle.minY, width: 2, height: 2)
            nextPreview.frame = nextFrame.bounds
            return
        }
        nextFrame.alphaValue = 1
        // A focus mode: the editor has the whole of the stage and timeline.
        if let editor = points ?? route {
            editor.frame = f.middle
            for view in [stageHeader, nextFrame, wordmarkFrame, bareStage, timelineView, joinLine, stageSetup] as [NSView] {
                view.isHidden = true
            }
            return
        }
        // Stage setup: the area, on the stage.
        stageSetup.isHidden = !showingStageSetup || controller.show.cues.isEmpty
        stageSetup.frame = f.canvas
        stageSetup.geometry = controller.show.settings.geometry

        timelineView.isHidden = !showsTimeline || timelineView.timeline == nil
        joinLine.isHidden = timelineView.isHidden
        timelineView.frame = f.timeline
        joinLine.frame = f.joinLine

        let noCues = controller.show.cues.isEmpty
        let empty = controller.standingByCue == nil
        // No cues at all: the bare stage, across the whole middle.
        bareStage.isHidden = !noCues
        if noCues {
            bareStage.frame = f.middle
        }
        // Cues, but none selected: the wordmark on the screen the cue would
        // have, so picking one doesn't move it.
        wordmarkFrame.isHidden = noCues || !empty
        stageHeader.isHidden = empty
        nextFrame.isHidden = empty
        if empty {
            wordmarkFrame.frame = f.canvas
            wordmark.frame = wordmarkFrame.bounds.insetBy(dx: 1, dy: 1)
            return
        }
        stageHeader.frame = NSRect(x: f.canvas.minX, y: f.canvasHeader.minY, width: f.canvas.width, height: f.canvasHeader.height)
        nextFrame.frame = f.canvas
        nextPreview.frame = nextFrame.bounds.insetBy(dx: 1, dy: 1)
    }

    /// The timeline goes under the stage while a cue is on it, and the stage
    /// isn't being set up or given over to a focus mode.
    private var showsTimeline: Bool {
        controller.mode == .edit && !showingStageSetup && !focusing && !showingStoryboard && controller.standingByCue != nil
    }

    /// Centres a wrapping label in the space it is given, across and down.
    private func centre(_ label: NSTextField, in rect: NSRect) {
        // Narrow enough that a line of it doesn't run the whole column.
        let width = min(rect.width, 320)
        let h = label.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude)).height
        label.frame = NSRect(x: rect.midX - width / 2, y: rect.midY - h / 2, width: width, height: h)
    }

    /// Space between the Inspector panel's edge and what it holds.
    private static let inspectorPadding: CGFloat = 16

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

    /// A + in the rail: a cue is to go after the cue at this index, or at the
    /// start for -1. That cue stands by, so Add Cue puts the new one after it.
    private func insertCue(after index: Int) {
        guard controller.mode == .edit else { return }
        window?.makeFirstResponder(root)
        addingAtStart = index < 0
        if index >= 0, controller.show.cues.indices.contains(index) {
            controller.standBy(controller.show.cues[index].id)
        }
        showAddCue()
    }

    /// The next cue added goes at the start of the sheet, from the + above
    /// the first cue.
    private var addingAtStart = false

    /// A new cue stands by, and the Inspector opens on it to be filled in.
    private func addCueChosen(_ kind: Cue.Kind) {
        if addingAtStart {
            addingAtStart = false
            guard controller.addCues([ShowController.emptyCue(kind)], at: 0, "Add \(kind.heading) Cue") else { return }
            window?.makeFirstResponder(root)
            return
        }
        guard controller.addCue(kind) != nil else { return }
        window?.makeFirstResponder(root)
    }

    /// Pictures and clips dropped between cues become cues there, and the
    /// first stands by in the Inspector, as Add Cue leaves it.
    private func filesDropped(_ urls: [URL], at position: Int) {
        let before = controller.show.cues.count
        addMediaCues(urls, position)
        guard controller.show.cues.count > before else { return }
        selectedTransition = nil
        showingStageSetup = false
        window?.makeFirstResponder(root)
    }

    private func modeChosen(_ editing: Bool) {
        setMode(editing)
        window?.makeFirstResponder(root)
        refresh()
    }

    /// Stage setup in the Inspector and on the stage, or back to the cue standing by.
    func setStageSetup(_ on: Bool) {
        guard !on || controller.mode == .edit else { return }
        showingStageSetup = on
        if on { selectedTransition = nil }
        refresh()
    }

    /// Show › Stage Setup: the show's title, text size and projection area
    /// in the Inspector, where the header's toggle shows them.
    func showStageSetup() {
        setStageSetup(true)
    }

    /// Copies a cue and stands the copy by, as adding one does.
    func duplicateCue(_ id: UUID) {
        guard controller.mode == .edit, controller.duplicateCue(id) != nil else { return }
        window?.makeFirstResponder(root)
    }

    /// Edit › Duplicate Cue: the cue standing by.
    func duplicateStandbyCue() {
        if let id = controller.playhead.standby { duplicateCue(id) }
    }

    /// Edit › Add Cue, the header's button and the rail's +: the cue
    /// gallery, saying where the cue will go.
    func showAddCue() {
        guard controller.mode == .edit else { return }
        header.state.galleryPlace = addingAtStart ? .atStart
            : controller.standingByCue.map(GalleryPlace.after) ?? .atEnd
        header.state.showingAddCue = true
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

// MARK: Go To and the key help

extension ConsoleWindowController: ConsoleKeys {
    /// G, here or on the projector: the console comes forward and Go To
    /// opens on it, empty. Already open, it stays as it is.
    func showGoTo() {
        guard let window else { return }
        if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
        closeKeyHelp()
        if let goTo {
            window.makeFirstResponder(goTo.field)
            return
        }
        let panel = GoToPanel()
        panel.field.onGo = { [weak self] in
            self?.closeGoTo()
            self?.controller.go()
        }
        panel.field.onCommit = { [weak self] typed in
            guard let self else { return false }
            guard !typed.isEmpty else { return false }
            if self.controller.standBy(number: typed) {
                self.closeGoTo()
                return true
            }
            self.goTo?.show(message: self.controller.message)
            self.layoutOverlays()
            return false
        }
        panel.field.onCancel = { [weak self] in self?.closeGoTo() }
        panel.field.onChange = { [weak self, weak panel] _ in
            panel?.show(message: nil)
            self?.layoutOverlays()
        }
        root.addSubview(panel)
        goTo = panel
        layoutOverlays()
        window.makeFirstResponder(panel.field)
        watchClicks()
    }

    /// Go To away with no change, and the keyboard back to the show keys.
    func closeGoTo() {
        guard let goTo else { return }
        goTo.removeFromSuperview()
        self.goTo = nil
        window?.makeFirstResponder(root)
        stopWatchingClicksIfDone()
    }

    func toggleKeyHelp() {
        if !closeKeyHelp() { showKeyHelp() }
    }

    func showKeyHelp() {
        guard keyHelp == nil else { return }
        let help = KeyHelp()
        root.addSubview(help)
        keyHelp = help
        layoutOverlays()
        watchClicks()
    }

    @discardableResult
    func closeKeyHelp() -> Bool {
        guard let keyHelp else { return false }
        keyHelp.removeFromSuperview()
        self.keyHelp = nil
        stopWatchingClicksIfDone()
        return true
    }

    /// Go To over its anchor, near the top, and the key help in the middle
    /// of the console. Both stay above everything else.
    fileprivate func layoutOverlays() {
        let b = root.bounds
        if let goTo {
            let size = goTo.fittingPanelSize
            let width = min(size.width, b.width - 32)
            var x = (goToAnchor.midX - width / 2).rounded()
            x = min(max(16, x), b.width - 16 - width)
            let y = goToAnchor.minY + 16
            goTo.frame = NSRect(x: x, y: y, width: width, height: size.height)
            if root.subviews.last !== goTo { root.addSubview(goTo, positioned: .above, relativeTo: nil) }
        }
        if let keyHelp {
            let size = keyHelp.contentSize
            keyHelp.frame = NSRect(x: (b.midX - size.width / 2).rounded(), y: (b.midY - size.height / 2).rounded(),
                                   width: size.width, height: size.height)
            if root.subviews.last !== keyHelp { root.addSubview(keyHelp, positioned: .above, relativeTo: nil) }
        }
    }

    /// While either is open, a click anywhere closes the key help, and a click
    /// outside Go To closes it. In the console, the click does nothing else:
    /// it was to put them away, not to stand a cue by.
    private func watchClicks() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            // AppKit calls a local monitor on the main thread, as it handles the event.
            nonisolated(unsafe) let event = event
            let swallow = MainActor.assumeIsolated { self?.clicked(event) ?? false }
            return swallow ? nil : event
        }
    }

    /// Whether the click is used up putting Go To or the key help away.
    private func clicked(_ event: NSEvent) -> Bool {
        let here = event.window === window
        var swallow = false
        if closeKeyHelp() { swallow = here }
        if let goTo, !(here && goTo.bounds.contains(goTo.convert(event.locationInWindow, from: nil))) {
            closeGoTo()
            swallow = swallow || here
        }
        return swallow
    }

    private func stopWatchingClicksIfDone() {
        guard goTo == nil, keyHelp == nil, let monitor = clickMonitor else { return }
        NSEvent.removeMonitor(monitor)
        clickMonitor = nil
    }

    /// Another window or app took the keyboard: Go To closes, so it never
    /// waits unseen to swallow keys.
    func windowDidResignKey(_ notification: Notification) {
        closeGoTo()
    }
}

// MARK: Continuity Camera

/// Edit › Import from iPhone or iPad: a photo taken with an iPhone or iPad
/// nearby. AppKit fills the menu with the devices, and asks the responder
/// chain who takes the pictures they send. In edit mode, the console does.
/// AppKit asks on the main thread, so the conformance is the main actor's.
extension ConsoleWindowController: @MainActor NSServicesMenuRequestor {
    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?,
                                 returnType: NSPasteboard.PasteboardType?) -> Any? {
        if sendType == nil, let returnType, controller.mode == .edit,
           MediaDrop.pictureTypes.contains(where: { $0.identifier == returnType.rawValue }) {
            return self
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    func readSelection(from pasteboard: NSPasteboard) -> Bool {
        guard controller.mode == .edit, let photo = MediaDrop(pasteboard, unnamed: "Photo") else { return false }
        photo.receive { [weak self] urls in self?.importPhotos(urls) }
        return true
    }

    /// Into the cue standing by if it is an image cue still waiting for its
    /// picture, as when a cue was added for a photo not yet taken. Otherwise
    /// a new image cue after it.
    func importPhotos(_ urls: [URL]) {
        guard let url = urls.first else { return }
        if let cue = controller.standingByCue, case .image(let content) = cue.content, content.src.isEmpty {
            importMedia(url, cue.id, nil)
        } else {
            let after = controller.standingByCue.flatMap { controller.show.index(of: $0.id) }
            filesDropped(urls, at: after.map { $0 + 1 } ?? controller.show.cues.count)
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
    /// For G and ?.
    weak var console: ConsoleKeys?
    var onLayout: () -> Void = {}
    /// Increase Contrast, Reduce Motion or the like changed: the window
    /// controller works out the room again.
    var onDisplayOptionsChanged: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: frame)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func displayOptionsChanged() {
        onDisplayOptionsChanged()
        paintDesk()
        // Every view below redraws, so colours worked out for the old
        // setting are worked out again.
        func redraw(_ view: NSView) {
            view.needsDisplay = true
            view.subviews.forEach(redraw)
        }
        redraw(self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paintDesk()
    }

    /// The desk's own background. The window has one too, but it isn't part
    /// of this view's drawing, so a snapshot of the view alone would come
    /// out with nothing behind it.
    func paintDesk() {
        wantsLayer = true
        let colour = controller.map { Desk.room($0.mode).background } ?? Desk.colour
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = colour.cgColor
        }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        onLayout()
    }

    override func keyDown(with event: NSEvent) {
        guard let controller, ShowKeys.handle(event, controller: controller, console: console) else {
            super.keyDown(with: event)
            return
        }
    }

    /// A click on empty space takes the keyboard back from a form.
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
