import AppKit
import BackdropCore
import BackdropStage
import UniformTypeIdentifiers

/// A show on disk: the `.backdrop` package, opened with standard Open, Save,
/// Duplicate and version history, and autosaved in place.
///
/// The document keeps the file wrapper it read and hands back the same one,
/// with only show.json and the version replaced, so media are never
/// rewritten. In show mode the document is read-only: nothing can change, so
/// nothing is written.
final class ShowDocument: NSDocument {
    static let typeName = "com.andyaiken.backdrop.show"

    // `read(from:ofType:)` is declared callable off the main thread, and sets
    // these three. It never is here: documents aren't read concurrently (see
    // `canConcurrentlyReadDocuments`), so NSDocument reads on the main thread,
    // before any window exists.

    /// The show as read, or as handed over by Import. Once the windows exist
    /// the controller holds the live copy.
    nonisolated(unsafe) private var initialShow = Show()
    private var initialWarnings: [String] = []
    nonisolated(unsafe) private var package: FileWrapper?
    /// Imports not saved into the package yet: their path in the package,
    /// and the file they were copied from, which renderers use meanwhile.
    private var pendingMedia: [String: URL] = [:]
    /// New and imported shows are being written, so they start in edit
    /// mode. A show opened from disk always opens in show mode.
    nonisolated(unsafe) private var startsInEditMode = true

    private(set) var controller: ShowController?
    private(set) var console: ConsoleWindowController?
    private(set) var projector: ProjectorManager?
    private var clock: ClockSource?
    private var booth: BoothWatch?

    override class var autosavesInPlace: Bool { true }

    /// One at a time, on the main thread, which the properties `read` sets
    /// rely on.
    override nonisolated class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    /// A new, unsaved show with this sheet.
    convenience init(show: Show, warnings: [String]) {
        self.init()
        fileType = Self.typeName
        initialShow = show
        initialWarnings = warnings
    }

    var show: Show { controller?.show ?? initialShow }

    var projectorIsOpen: Bool { controller?.projector.isOpen ?? false }

    // MARK: Reading and writing

    override func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        initialShow = try ShowPackage.read(fileWrapper)
        package = fileWrapper
        startsInEditMode = false
    }

    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        let wrapper = try ShowPackage.updated(package, with: show)
        package = wrapper
        return wrapper
    }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        // Show mode never writes the document. Nothing can change in show
        // mode, and pending edits are saved on the way in, so there is
        // normally nothing to save; this only stops a save of a clean show.
        if controller?.mode == .show, !isDocumentEdited, !hasUnautosavedChanges,
           saveOperation == .saveOperation || saveOperation == .autosaveInPlaceOperation {
            completionHandler(nil)
            return
        }
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            if error == nil, saveOperation != .saveToOperation {
                self?.refreshPackage(from: url)
                // Saved, moved or renamed: where it is now, for reopening,
                // and what its cues say now, for Spotlight.
                self?.noteWhereItIs()
            }
            completionHandler(error)
        }
    }

    /// After a save, the wrapper is read back from where it was written, so
    /// its media refer to the package rather than to the files they were
    /// imported from, and the next save links them instead of copying.
    private func refreshPackage(from url: URL) {
        guard let saved = try? FileWrapper(url: url, options: []) else { return }
        package = saved
        pendingMedia.removeAll()
    }

    /// Where a cue's media path is on disk right now.
    func mediaURL(_ path: String) -> URL? {
        if let pending = pendingMedia[path] { return pending }
        guard let base = fileURL ?? autosavedContentsFileURL else { return nil }
        return base.appendingPathComponent(path)
    }

    // MARK: Windows

    override func makeWindowControllers() {
        let media: (String) -> URL? = { [weak self] path in self?.mediaURL(path) }
        let controller = ShowController(
            show: initialShow, warnings: initialWarnings, mode: startsInEditMode ? .edit : .show,
            renderers: [
                .title: TitleRenderer(),
                .anagram: AnagramRenderer(),
                .image: ImageRenderer(media: media),
                .morph: MorphRenderer(media: media),
                .map: MapRenderer(media: media),
                .layered: LayeredRenderer(media: media),
                .keypad: KeypadRenderer(),
                .sms: SMSRenderer(),
                .conversation: ConversationRenderer(),
                .cascade: CascadeRenderer(),
                .video: VideoRenderer(media: media),
                .feed: FeedRenderer(),
                .text: TextRenderer(),
                .blank: BlankRenderer(),
            ],
            // The console's preview finds pictures where the stage does.
            nextRenderers: [
                .title: TitleRenderer(),
                .anagram: AnagramRenderer(),
                .image: ImageRenderer(media: media),
                .morph: MorphRenderer(media: media),
                .map: MapRenderer(media: media),
                .layered: LayeredRenderer(media: media),
                .keypad: KeypadRenderer(),
                .sms: SMSRenderer(),
                .conversation: ConversationRenderer(),
                .cascade: CascadeRenderer(),
                .feed: FeedRenderer(),
                .text: TextRenderer(),
                .blank: BlankRenderer(),
            ]
        )
        self.controller = controller

        // addWindowController sets the console's document. Setting it first
        // makes AppKit treat the console as already added, and the show is
        // left owning no windows, so showWindows puts nothing on screen.
        let console = ConsoleWindowController(controller: controller)
        console.importMedia = { [weak self] url, cue, slot in self?.importMedia(from: url, into: cue, slot: slot) }
        console.chooseMedia = { [weak self] cue, slot in self?.chooseMedia(for: cue, slot: slot) }
        console.addMediaCues = { [weak self] urls, position in self?.addMediaCues(from: urls, at: position) }
        console.mediaURL = { [weak self] path in self?.mediaURL(path) }
        addWindowController(console)
        self.console = console

        let projector = ProjectorManager(controller: controller)
        projector.console = console.window
        self.projector = projector
        let clock = ClockSource(projector: projector.view, preview: console.nextPreview)
        self.clock = clock
        let booth = BoothWatch()
        booth.console = console.window
        booth.showURL = fileURL
        booth.onChange = { [weak console] in console?.setNeedsRefresh() }
        console.booth = { [weak booth] in booth?.conditions ?? BoothConditions() }
        self.booth = booth

        controller.changed = { [weak self, weak console] in
            // Saving, moving or renaming the show can put it on another disk,
            // and entering show mode is a change too, so the disk is right
            // by the time its warning would speak up.
            self?.booth?.showURL = self?.fileURL
            console?.setNeedsRefresh()
        }
        controller.needsTicks = { [weak clock] on in clock?.ticking = on }
        projector.onChange = { [weak clock, weak projector] in clock?.projectorVisible = projector?.isVisible ?? false }
        console.openProjector = { [weak projector] in projector?.open() }
        console.closeProjector = { [weak projector] in projector?.close() }
        console.setMode = { [weak self] editing in
            if editing { self?.enterEditMode() } else { self?.enterShowMode() }
        }
        console.screenChanged = { [weak projector, weak booth] in
            projector?.displaysChanged()
            booth?.readDisplays()
        }
        controller.onEdit = { [weak self] before, name in self?.registerUndo(back: before, name: name) }
        controller.onFire = { [weak self] cue in
            // Untitled shows have nowhere to be reopened from.
            guard let url = self?.fileURL else { return }
            CrashRecords.write(CrashRecord(show: url, cue: cue.id, cueNumber: cue.number, firedAt: Date()))
        }
        noteWhereItIs()
    }

    /// A show on disk is remembered, so Backdrop can open it again by itself,
    /// and goes into Spotlight, or is brought up to date there.
    private func noteWhereItIs() {
        guard let url = fileURL else { return }
        ShowBookmarks.remember(url)
        ShowSpotlight.index(self)
    }

    /// Closing a show is a clean stop, so there is nothing to resume.
    override func close() {
        projector?.close()
        CrashRecords.clear()
        super.close()
    }

    // MARK: Undo

    /// Every edit is undone by putting the whole sheet back, and redone the
    /// same way.
    private func registerUndo(back show: Show, name: String) {
        undoManager?.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated { document.restore(show, name: name) }
        }
        undoManager?.setActionName(name)
    }

    private func restore(_ show: Show, name: String) {
        guard let controller else { return }
        let current = controller.show
        controller.restore(show)
        registerUndo(back: current, name: name)
    }

    // MARK: Modes

    /// Pending edits are saved before the show locks, because nothing is
    /// written in show mode. Media no cue uses any longer goes at the same
    /// time: this is the one moment undo no longer needs it.
    func enterShowMode() {
        guard let controller, controller.mode == .edit else { return }
        guard hasUnautosavedChanges else {
            pruneUnusedMedia(then: { controller.enterShowMode() })
            return
        }
        autosave(withImplicitCancellability: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pruneUnusedMedia(then: { controller.enterShowMode() })
            }
        }
    }

    /// Removes media no cue refers to and saves, then calls `done`. Undo is
    /// dropped when anything goes, because an undo could bring back a cue
    /// whose picture is no longer in the package. Earlier versions keep the
    /// files, in File › Revert To. Imports not yet saved are never touched.
    private func pruneUnusedMedia(then done: @escaping () -> Void) {
        guard let controller, pendingMedia.isEmpty,
              let package = try? ShowPackage.updated(self.package, with: controller.show) else { return done() }
        self.package = package
        let unused = ShowPackage.unusedMedia(in: package, show: controller.show)
        guard !unused.isEmpty else { return done() }
        ShowPackage.removeMedia(unused, from: package)
        undoManager?.removeAllActions()
        updateChangeCount(.changeDone)
        autosave(withImplicitCancellability: false) { [weak controller] error in
            MainActor.assumeIsolated {
                done()
                if error == nil {
                    controller?.say("Show mode. Removed \(unused.count) unused file\(unused.count == 1 ? "" : "s") from the show.")
                }
            }
        }
    }

    func enterEditMode() {
        controller?.enterEditMode()
    }

    // MARK: Media

    /// Where in a morph's pictures a file goes. Every other cue has only the
    /// one.
    enum MediaSlot: Equatable {
        /// In the place of the picture at this index.
        case picture(Int)
        /// A new picture at the end.
        case add
    }

    /// Copies a picture or clip into the show and gives it to a cue. The
    /// original can then be moved or deleted without breaking the show.
    ///
    /// - Parameter slot: For a morph, where the picture goes. Without one, as
    ///   when a file is dropped on its row, it is added at the end.
    func importMedia(from url: URL, into cueID: UUID, slot: MediaSlot? = nil) {
        guard let controller, controller.mode == .edit, let cue = controller.show[cueID] else { return }
        guard Self.accepts(url, for: cue.kind) else {
            controller.say("\(url.lastPathComponent) isn\u{2019}t \(cue.kind == .video ? "a clip" : "a picture") this cue can use.")
            return
        }
        do {
            let package = try ShowPackage.updated(self.package, with: controller.show)
            self.package = package
            let path = try ShowPackage.importMedia(from: url, into: package)
            pendingMedia[path] = url
            controller.updateCue(cueID, cue.kind == .video ? "Set Clip" : "Set Picture") { cue in
                switch cue.content {
                case .image(var c): c.src = path; cue.content = .image(c)
                case .morph(var c):
                    // In a picture's place, keeping its points, or added
                    // at the end.
                    if case .picture(let i) = slot, c.pictures.indices.contains(i) {
                        c.pictures[i].src = path
                    } else {
                        c.pictures.append(MorphPicture(src: path))
                    }
                    cue.content = .morph(c)
                case .map(var c): c.src = path; cue.content = .map(c)
                case .video(var c): c.src = path; cue.content = .video(c)
                case .layered(var c):
                    // The base with no slot, as when dropped on its well; a
                    // layer in a layer's place, or added at the end.
                    if case .picture(let i) = slot, c.layers.indices.contains(i) {
                        c.layers[i].src = path
                    } else if slot == .add {
                        c.layers.append(ImageLayer(src: path))
                    } else {
                        c.base = path
                    }
                    cue.content = .layered(c)
                default: break
                }
            }
            checkLayerSize(of: url, in: cue, slot: slot)
        } catch {
            controller.say("\(url.lastPathComponent) couldn\u{2019}t be copied into the show.")
        }
    }

    /// A layer is a full-frame picture at the base's pixel size, with
    /// transparency; nothing else in the app enforces it, so say plainly when a
    /// layer just added, or a base just chosen, differs from the other.
    private func checkLayerSize(of url: URL, in cue: Cue, slot: MediaSlot?) {
        guard case .layered(let c) = cue.content, let size = Self.pixelSize(of: url) else { return }
        let isBase: Bool
        if case .picture = slot { isBase = false } else { isBase = slot != .add }
        if isBase {
            // A new base against the layers already there.
            let odd = c.layers.filter { layer in
                mediaURL(layer.src).flatMap(Self.pixelSize(of:)).map { $0 != size } ?? false
            }
            if !odd.isEmpty {
                controller?.say("The base is \(Int(size.width)) \u{00D7} \(Int(size.height)), but \(odd.count) layer\(odd.count == 1 ? " is" : "s are") a different size. Every layer must be the base\u{2019}s size, or the parts won\u{2019}t line up.")
            }
        } else if !c.base.isEmpty, let base = mediaURL(c.base).flatMap(Self.pixelSize(of:)), base != size {
            controller?.say("\(url.lastPathComponent) is \(Int(size.width)) \u{00D7} \(Int(size.height)), but the base is \(Int(base.width)) \u{00D7} \(Int(base.height)). Every layer must be the base\u{2019}s size, or the parts won\u{2019}t line up.")
        }
    }

    static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = properties[kCGImagePropertyPixelWidth] as? Int, let h = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }

    static func accepts(_ url: URL, for kind: Cue.Kind) -> Bool {
        UTType(filenameExtension: url.pathExtension).map { accepts($0, for: kind) } ?? false
    }

    /// By type, for what is being dragged before its files exist: Photos
    /// and Safari say what they will write, and write it only on the drop.
    static func accepts(_ type: UTType, for kind: Cue.Kind) -> Bool {
        switch kind {
        case .image, .morph, .map, .layered: type.conforms(to: .image)
        case .video: type.conforms(to: .movie)
        default: false
        }
    }

    /// The kind of cue a file dropped between cues makes: an image cue for
    /// a picture, a video cue for a clip, and none for anything else.
    static func cueKind(for url: URL) -> Cue.Kind? {
        UTType(filenameExtension: url.pathExtension).flatMap(cueKind(for:))
    }

    static func cueKind(for type: UTType) -> Cue.Kind? {
        if accepts(type, for: .video) { return .video }
        if accepts(type, for: .image) { return .image }
        return nil
    }

    /// Files dropped between cues: each picture becomes an image cue and
    /// each clip a video cue, named for its file and with the file copied
    /// into the show. They stand together at `position` in the sheet, in
    /// order of their names, as one undo step. Anything else is left out.
    func addMediaCues(from urls: [URL], at position: Int) {
        guard let controller, controller.mode == .edit else { return }
        let usable = urls.filter { Self.cueKind(for: $0) != nil }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let refused = urls.filter { Self.cueKind(for: $0) == nil }
        var cues: [Cue] = []
        var failed: [URL] = []
        if let package = try? ShowPackage.updated(self.package, with: controller.show) {
            self.package = package
            for url in usable {
                guard let path = try? ShowPackage.importMedia(from: url, into: package) else {
                    failed.append(url)
                    continue
                }
                pendingMedia[path] = url
                let name = url.deletingPathExtension().lastPathComponent
                cues.append(Cue(content: Self.cueKind(for: url) == .video
                    ? .video(VideoContent(text: name, src: path))
                    : .image(ImageContent(text: name, src: path))))
            }
        } else {
            failed = usable
        }
        controller.addCues(cues, at: position, cues.count == 1 ? "Add \(cues[0].kind.heading) Cue" : "Add Cues")
        func names(_ urls: [URL]) -> String { urls.map(\.lastPathComponent).joined(separator: ", ") }
        if !failed.isEmpty {
            controller.say("\(names(failed)) couldn\u{2019}t be copied into the show.")
        } else if !refused.isEmpty {
            controller.say(refused.count == 1
                ? "\(names(refused)) isn\u{2019}t a picture or a clip, so it wasn\u{2019}t added."
                : "\(names(refused)) aren\u{2019}t pictures or clips, so they weren\u{2019}t added.")
        }
    }

    func chooseMedia(for cueID: UUID, slot: MediaSlot? = nil) {
        guard let window = console?.window, let cue = controller?.show[cueID] else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = cue.kind == .video ? [.movie] : [.image]
        panel.message = switch (cue.kind, slot) {
        case (.video, _): "Choose a clip for cue \(cue.number)."
        case (.layered, .picture(let i)): "Choose a picture to take the place of layer \(i + 1) in cue \(cue.number)."
        case (.layered, .add): "Choose layers to add to cue \(cue.number), each the same size as the base, with transparency. Several at once are added in order of their names."
        case (.layered, _): "Choose the base picture for cue \(cue.number): the whole painting."
        case (.morph, .picture(let i)): "Choose a picture to take the place of picture \(i + 1) in cue \(cue.number)."
        case (.morph, _): "Choose pictures to add to cue \(cue.number). Several at once are added in order of their names."
        case (.map, _): "Choose a map for cue \(cue.number): a street map, light or dark, as large as you have."
        default: "Choose a picture for cue \(cue.number)."
        }
        // Adding to a morph may take several at once.
        panel.allowsMultipleSelection = (cue.kind == .morph || cue.kind == .layered) && slot == .add
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            MainActor.assumeIsolated {
                for url in urls { self?.importMedia(from: url, into: cueID, slot: slot) }
            }
        }
    }

    /// Remove Unused Media: files no cue refers to, after a confirmation.
    @objc func removeUnusedMedia(_ sender: Any?) {
        guard let controller, controller.mode == .edit, let window = console?.window,
              let package = try? ShowPackage.updated(package, with: controller.show) else { return }
        self.package = package
        let unused = ShowPackage.unusedMedia(in: package, show: controller.show)
        let alert = NSAlert()
        guard !unused.isEmpty else {
            alert.messageText = "Every picture and clip in the show is used by a cue."
            alert.beginSheetModal(for: window)
            return
        }
        alert.messageText = "Remove \(unused.count) unused file\(unused.count == 1 ? "" : "s") from the show?"
        alert.informativeText = unused.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            + "\n\nEarlier versions of the show keep them, in File \u{203A} Revert To."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                ShowPackage.removeMedia(unused, from: package)
                for path in unused { self.pendingMedia.removeValue(forKey: path) }
                self.updateChangeCount(.changeDone)
                controller.say("Removed \(unused.count) unused file\(unused.count == 1 ? "" : "s").")
            }
        }
    }

    // MARK: Cue sheet

    /// The title printed at the head of every page: the show's own, or the
    /// file's name if it hasn't one.
    var sheetTitle: String { show.title.isEmpty ? displayName : show.title }

    /// Print Cue Sheet: the print panel, with the layout chosen in it. The
    /// panel is a sheet on the console, never on the projector.
    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = printInfo.copy() as! NSPrintInfo
        info.dictionary().addEntries(from: printSettings)
        return CueSheetPrinting.operation(for: show, title: sheetTitle, layout: .dsm, printInfo: info)
    }

    /// Export Cue Sheet as PDF: a save panel with the layout and paper, and
    /// no print panel.
    @objc func exportCueSheet(_ sender: Any?) {
        guard let window = console?.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(sheetTitle) cue sheet.pdf"
        let layout = NSPopUpButton(frame: .zero, pullsDown: false)
        layout.addItems(withTitles: CueSheet.Layout.allCases.map(\.name))
        let paper = NSPopUpButton(frame: .zero, pullsDown: false)
        paper.addItems(withTitles: ["A4", "US Letter"])
        // Start from whichever the Mac's printing defaults to.
        paper.selectItem(at: abs(NSPrintInfo.shared.paperSize.width - CueSheetView.letter.width) < 1 ? 1 : 0)
        let grid = NSGridView(views: [[NSTextField(labelWithString: "Layout:"), layout], [NSTextField(labelWithString: "Paper:"), paper]])
        grid.rowSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 80))
        grid.frame = accessory.bounds.insetBy(dx: 20, dy: 12)
        accessory.addSubview(grid)
        panel.accessoryView = accessory
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let chosen = CueSheet.Layout.allCases[layout.indexOfSelectedItem]
                let size = paper.indexOfSelectedItem == 1 ? CueSheetView.letter : CueSheetView.a4
                let ok = CueSheetPrinting.exportPDF(for: self.show, title: self.sheetTitle, layout: chosen, paper: size, to: url)
                self.controller?.say(ok ? "Saved the cue sheet as \(url.lastPathComponent)." : "The cue sheet couldn\u{2019}t be saved.")
            }
        }
    }

    // MARK: Menus

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        let editing = controller?.mode == .edit
        switch item.action {
        case #selector(save(_:)), #selector(removeUnusedMedia(_:)):
            return editing && super.validateUserInterfaceItem(item)
        default:
            return super.validateUserInterfaceItem(item)
        }
    }
}
