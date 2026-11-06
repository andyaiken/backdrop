import AppKit
import ProspectCore
import ProspectStage
import UniformTypeIdentifiers

@main
@MainActor
enum ProspectMain {
    static let delegate = AppDelegate()

    static func main() {
        // The first document controller made becomes the shared one.
        _ = DocumentController()
        let app = ProspectApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

/// Quit asks about a live projector before anything else happens. Left to
/// AppKit, Quit saves and closes the show, and the projector with it, before
/// it asks the app delegate whether to quit at all, which is too late to ask.
final class ProspectApplication: NSApplication {
    override func terminate(_ sender: Any?) {
        guard let delegate = delegate as? AppDelegate else {
            super.terminate(sender)
            return
        }
        delegate.confirmQuit { quit in
            if quit { super.terminate(sender) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    private let displaySleep = DisplaySleepGuard()
    private var preferences: PreferencesWindowController?
    private var askingToQuit = false

    private var documents: DocumentController { NSDocumentController.shared as! DocumentController }
    /// The one show open, if any.
    private var current: ShowDocument? { documents.current }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            Preferences.reopenLastShow: true,
            Preferences.missingDisplay: MissingDisplay.window.rawValue,
        ])
        NSApp.mainMenu = MainMenu.build(displayMenuDelegate: self)

        #if DEBUG
        if let directory = UserDefaults.standard.string(forKey: "ProspectSnapshot") {
            Snapshots.run(to: directory)
            return
        }
        if let directory = UserDefaults.standard.string(forKey: "ProspectDocumentCheck") {
            DocumentCheck.run(in: directory)
            return
        }
        #endif

        // A quiet scene can run twenty minutes between cues, well inside any
        // sleep timer, so the display is kept awake whenever a show is open.
        displaySleep.hold(reason: "Prospect has a show open")
        // After any show Finder asked to open has been opened.
        DispatchQueue.main.async { self.openFirstShow() }
        NSApp.activate()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    /// The operator's first action on the night should be GO, not finding a
    /// file: after a crash, the show that was running, offering to resume;
    /// otherwise the most recent show; otherwise a new one.
    private func openFirstShow() {
        if let record = CrashRecords.read(), FileManager.default.fileExists(atPath: record.show.path) {
            documents.openDocument(withContentsOf: record.show, display: true) { [weak self] document, _, _ in
                MainActor.assumeIsolated {
                    guard let document = document as? ShowDocument else {
                        self?.documents.newDocument(nil)
                        return
                    }
                    self?.offerResume(record, in: document)
                }
            }
            return
        }
        guard documents.documents.isEmpty else { return }
        if UserDefaults.standard.bool(forKey: Preferences.reopenLastShow),
           let url = documents.recentDocumentURLs.first, FileManager.default.fileExists(atPath: url.path) {
            documents.openDocument(withContentsOf: url, display: true) { [weak self] document, _, _ in
                if document == nil { MainActor.assumeIsolated { self?.documents.newDocument(nil) } }
            }
        } else {
            documents.newDocument(nil)
        }
    }

    /// Resume puts the last fired cue straight back on the projector,
    /// finished, and stands by the next.
    private func offerResume(_ record: CrashRecord, in document: ShowDocument) {
        guard let window = document.console?.window, let controller = document.controller else { return }
        let cue = controller.show[record.cue] ?? controller.show.index(ofNumber: record.cueNumber).map { controller.show.cues[$0] }
        guard let cue else { return }
        let alert = NSAlert()
        alert.messageText = "Prospect stopped unexpectedly during the show."
        alert.informativeText = "The last cue fired was cue \(cue.number). Resuming puts it straight back on the projector, finished, and stands by the next."
        alert.addButton(withTitle: "Resume at Cue \(cue.number)")
        alert.addButton(withTitle: "Start from the Top")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated {
                document.projector?.open()
                controller.resume(at: cue.id)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        displaySleep.release()
        CrashRecords.clear()
    }

    /// Windows come and go while one show replaces another. Quitting follows
    /// the show instead: see DocumentController.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// While the projector is live, Quit asks first, on the console, before
    /// the show is saved or closed. Cancel is the default, so a reflexive
    /// Return doesn't quit, and Escape cancels.
    func confirmQuit(_ then: @escaping (Bool) -> Void) {
        guard let document = current, document.projectorIsOpen, let window = document.console?.window,
              let controller = document.controller else {
            then(true)
            return
        }
        // A second Quit while the sheet is up is the same question.
        guard !askingToQuit else { return }
        askingToQuit = true
        let alert = NSAlert()
        alert.messageText = "Quit while the projector is live?"
        let live = controller.playhead.live.flatMap { controller.show[$0] }
        alert.informativeText = live.map { "Cue \($0.number) stays on the projector until Prospect quits." }
            ?? "Quitting takes the projector window away."
        alert.addButton(withTitle: "Cancel")
        let quit = alert.addButton(withTitle: "Quit")
        quit.hasDestructiveAction = true
        window.makeKeyAndOrderFront(nil)
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                self?.askingToQuit = false
                then(response == .alertSecondButtonReturn)
            }
        }
    }

    // MARK: Settings

    @objc func showSettings(_ sender: Any?) {
        let preferences = self.preferences ?? PreferencesWindowController()
        self.preferences = preferences
        preferences.showWindow(nil)
    }

    // MARK: Edit

    @objc func addTitleCue(_ sender: Any?) { current?.controller?.addCue(.title) }
    @objc func addAnagramCue(_ sender: Any?) { current?.controller?.addCue(.anagram) }
    @objc func addImageCue(_ sender: Any?) { current?.controller?.addCue(.image) }
    @objc func addMorphCue(_ sender: Any?) { current?.controller?.addCue(.morph) }
    @objc func addMapCue(_ sender: Any?) { current?.controller?.addCue(.map) }
    @objc func addVideoCue(_ sender: Any?) { current?.controller?.addCue(.video) }
    @objc func addLayeredCue(_ sender: Any?) { current?.controller?.addCue(.layered) }
    @objc func addBlankCue(_ sender: Any?) { current?.controller?.addCue(.blank) }
    @objc func addTransition(_ sender: Any?) { current?.console?.addTransition() }
    @objc func renumberAllCues(_ sender: Any?) { current?.console?.confirmRenumber() }
    @objc func showShowSettings(_ sender: Any?) { current?.console?.showShowSettings() }

    // MARK: Show

    @objc func enterShowMode(_ sender: Any?) { current?.enterShowMode() }
    @objc func enterEditMode(_ sender: Any?) { current?.enterEditMode() }

    @objc func toggleProjector(_ sender: Any?) {
        guard let projector = current?.projector else { return }
        if projector.state.isOpen { projector.close() } else { projector.open() }
    }

    @objc func chooseProjectorDisplay(_ sender: NSMenuItem) {
        guard let display = sender.representedObject as? DisplayIdentity else { return }
        current?.projector?.choose(display)
    }

    @objc func toggleBlackout(_ sender: Any?) { current?.controller?.toggleBlackout() }

    // MARK: Window

    @objc func showConsole(_ sender: Any?) { current?.showWindows() }
    @objc func showProjector(_ sender: Any?) {
        if let projector = current?.projector, !projector.state.isOpen { projector.open() }
    }

    // MARK: Menus

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let controller = current?.controller
        let editing = controller?.mode == .edit
        switch item.action {
        case #selector(addTitleCue(_:)), #selector(addAnagramCue(_:)), #selector(addImageCue(_:)), #selector(addMorphCue(_:)), #selector(addMapCue(_:)), #selector(addVideoCue(_:)), #selector(addBlankCue(_:)), #selector(addLayeredCue(_:)):
            return editing
        case #selector(addTransition(_:)):
            return editing && controller?.playhead.standby != nil
        case #selector(showShowSettings(_:)):
            return editing
        case #selector(renumberAllCues(_:)):
            return editing && controller?.show.cues.isEmpty == false
        case #selector(enterShowMode(_:)): return controller != nil && editing
        case #selector(enterEditMode(_:)): return controller != nil && !editing
        case #selector(toggleProjector(_:)):
            item.title = current?.projector?.state.isOpen == true ? "Close Projector" : "Open Projector"
            return controller != nil
        case #selector(toggleBlackout(_:)):
            item.state = controller?.playhead.blackout == true ? .on : .off
            return controller != nil
        case #selector(chooseProjectorDisplay(_:)):
            return item.representedObject != nil
        case #selector(showConsole(_:)), #selector(showProjector(_:)):
            return controller != nil
        default:
            return true
        }
    }

    /// Choose Projector Display: every connected display by name. The
    /// console's own display is listed but can't be chosen.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let console = current?.projector?.consoleDisplay
        let chosen = current?.show.settings.projector
        let displays = Displays.current()
        for display in displays {
            let isConsole = console.map { display.identity.bestMatch(in: [$0]) != nil } ?? false
            let item = NSMenuItem(title: display.identity.name + (isConsole ? " \u{2014} the console\u{2019}s display" : ""),
                                  action: #selector(chooseProjectorDisplay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = isConsole ? nil : display.identity
            if let chosen, chosen.bestMatch(in: [display.identity]) != nil { item.state = .on }
            menu.addItem(item)
        }
        if displays.count < 2 {
            menu.addItem(.separator())
            let note = NSMenuItem(title: "Connect the projector to choose it here", action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
        }
    }
}
