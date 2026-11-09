import AppKit
import BackdropCore
import BackdropStage

/// The menu bar. It adds what macOS users look for and nothing that
/// duplicates a show control: GO has no menu item and no key equivalent
/// beyond the spacebar, and changing mode has no key equivalent at all.
enum MainMenu {
    @MainActor
    static func build(displayMenuDelegate: NSMenuDelegate) -> NSMenu {
        let bar = NSMenu()

        let app = submenu(of: bar, titled: "Backdrop")
        app.addItem(withTitle: "About Backdrop", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Settings\u{2026}", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Backdrop", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Backdrop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = submenu(of: bar, titled: "File")
        file.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        file.addItem(withTitle: "Open\u{2026}", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        // The document controller fills the menu holding Clear Menu.
        let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        recent.submenu = recentMenu
        file.addItem(recent)
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(withTitle: "Save\u{2026}", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        let duplicate = file.addItem(withTitle: "Duplicate", action: #selector(NSDocument.duplicate(_:)), keyEquivalent: "s")
        duplicate.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: "Rename\u{2026}", action: #selector(NSDocument.rename(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Move To\u{2026}", action: #selector(NSDocument.move(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Revert to Saved", action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Browse All Versions\u{2026}", action: #selector(NSDocument.browseVersions(_:)), keyEquivalent: "")
        file.addItem(.separator())
        file.addItem(withTitle: "Print Cue Sheet\u{2026}", action: #selector(NSDocument.printDocument(_:)), keyEquivalent: "p")
        let export = file.addItem(withTitle: "Export Cue Sheet as PDF\u{2026}", action: #selector(ShowDocument.exportCueSheet(_:)), keyEquivalent: "p")
        export.keyEquivalentModifierMask = [.command, .option]
        file.addItem(.separator())
        file.addItem(withTitle: "Remove Unused Media\u{2026}", action: #selector(ShowDocument.removeUnusedMedia(_:)), keyEquivalent: "")

        let edit = submenu(of: bar, titled: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let addCue = edit.addItem(withTitle: "Add Cue\u{2026}", action: #selector(AppDelegate.addCue(_:)), keyEquivalent: "n")
        addCue.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(withTitle: "Duplicate Cue", action: #selector(AppDelegate.duplicateCue(_:)), keyEquivalent: "d")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Renumber All Cues\u{2026}", action: #selector(AppDelegate.renumberAllCues(_:)), keyEquivalent: "")

        let show = submenu(of: bar, titled: "Show")
        show.addItem(withTitle: "Enter Show Mode", action: #selector(AppDelegate.enterShowMode(_:)), keyEquivalent: "")
        show.addItem(withTitle: "Enter Edit Mode", action: #selector(AppDelegate.enterEditMode(_:)), keyEquivalent: "")
        show.addItem(.separator())
        show.addItem(withTitle: "Show Settings\u{2026}", action: #selector(AppDelegate.showShowSettings(_:)), keyEquivalent: "")
        show.addItem(.separator())
        show.addItem(withTitle: "Open Projector", action: #selector(AppDelegate.toggleProjector(_:)), keyEquivalent: "")
        let choose = NSMenuItem(title: "Choose Projector Display", action: nil, keyEquivalent: "")
        let displays = NSMenu(title: "Choose Projector Display")
        displays.delegate = displayMenuDelegate
        choose.submenu = displays
        show.addItem(choose)
        show.addItem(.separator())
        // Blackout's key is B, with the other show keys.
        show.addItem(withTitle: "Blackout", action: #selector(AppDelegate.toggleBlackout(_:)), keyEquivalent: "")

        let window = submenu(of: bar, titled: "Window")
        window.addItem(withTitle: "Console", action: #selector(AppDelegate.showConsole(_:)), keyEquivalent: "")
        window.addItem(withTitle: "Projector", action: #selector(AppDelegate.showProjector(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window

        return bar
    }

    @MainActor
    private static func submenu(of bar: NSMenu, titled title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        bar.addItem(item)
        return menu
    }
}
