#if DEBUG
import AppKit
import ProspectCore
import ProspectStage

/// Debug builds only: drives a document through import, Save As, Save and
/// reopen, checking each step, and writes what it found to result.txt.
///
///     Prospect.app/Contents/MacOS/Prospect -ProspectDocumentCheck /some/folder
@MainActor
enum DocumentCheck {
    private static var lines: [String] = []
    private static var failed = false

    private static func check(_ ok: Bool, _ what: String) {
        lines.append((ok ? "PASS  " : "FAIL  ") + what)
        if !ok { failed = true }
    }

    private static func write(to folder: URL) {
        try? (lines.joined(separator: "\n") + "\n").write(to: folder.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }

    private static func finish(in folder: URL) -> Never {
        // The scratch show shouldn't be what the app reopens next launch.
        NSDocumentController.shared.clearRecentDocuments(nil)
        write(to: folder)
        exit(failed ? 1 : 0)
    }

    /// The last check edits the open show and closes its console, as the
    /// operator would. That must save the edit and quit. Prospect exits if it
    /// passes and hangs if it doesn't, so whatever runs the check has to notice
    /// a hang, and look for the edit in the saved show.json.
    private static func finish(in folder: URL, closing document: ShowDocument?) {
        guard !failed, let document, let console = document.console?.window as? ConsoleWindow else { finish(in: folder) }
        document.enterEditMode()
        document.controller?.setTitle("Check, closed with this unsaved")
        // AppKit counts an edit as unsaved once the run loop goes idle after
        // it, so the console is closed a moment later, as in use.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            check(document.show.title == "Check, closed with this unsaved", "the title can be edited in edit mode")
            check(document.isDocumentEdited, "an edit marks the show as changed")
            guard !failed else { finish(in: folder) }
            NSDocumentController.shared.clearRecentDocuments(nil)
            lines.append("LAST  closing the console with an unsaved edit saves it and quits: Prospect exits now if this passes, and hangs if it doesn't")
            write(to: folder)
            console.performClose(nil)
            // Quitting can finish on a later turn of the run loop. If it
            // still hasn't after a while, it was refused.
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                check(false, "closing the console didn't quit")
                write(to: folder)
                exit(1)
            }
        }
    }

    private static func inode(_ url: URL) -> UInt64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? NSNumber)?.uint64Value
    }

    static func run(in directory: String) {
        let folder = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // A picture to import.
        let picture = folder.appendingPathComponent("gallery.png")
        let ctx = CGContext(data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 0.8, green: 0.6, blue: 0.3, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 36))
        try? NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])?.write(to: picture)

        let document = ShowDocument(show: Show(title: "Check"), warnings: [])
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        guard let controller = document.controller else { finish(in: folder) }
        check(document.windowControllers.contains { $0 === document.console } && document.console?.document === document,
              "the console belongs to the show, so showing the show shows it")
        // Closing the console must go to Quit without asking the show whether
        // it can close first: quitting from inside that request deadlocks.
        if let window = document.console?.window as? ConsoleWindow {
            var quitAsked = false
            window.onPerformClose = { quitAsked = true }
            window.performClose(nil)
            check(quitAsked && document.windowControllers.contains { $0 === document.console },
                  "closing the console asks to quit, and leaves the show to Quit")
            window.onPerformClose = { NSApp.terminate(nil) }
        } else {
            check(false, "the console is a ConsoleWindow, whose close is Quit")
        }
        check(controller.mode == .edit, "a new show starts in edit mode")
        guard let titleID = controller.addCue(.title), let imageID = controller.addCue(.image) else {
            check(false, "cues can be added")
            finish(in: folder)
        }
        check(controller.show.cues.map(\.number) == ["1", "2"], "added cues are numbered 1 and 2")

        // A cue dropped just under a group's heading joins that group, keeping
        // its number and its place in the running order.
        controller.standBy(imageID)
        if let group = controller.addGroup(named: "Act One"), let row = controller.show.span(of: group)?.lowerBound {
            controller.moveCue(titleID, before: row + 1)
            check(controller.show.groups(around: titleID).map(\.name) == ["Act One"] && controller.show.cues.map(\.number) == ["1", "2"],
                  "a cue dropped under a heading joins its group")
            // Right-clicking a cue in edit mode offers to renumber its group.
            if let console = document.console {
                console.refresh()
                let cueMenu = console.cueList.menuTitles(forCue: titleID), groupMenu = console.cueList.menuTitles(forGroup: group)
                check(cueMenu == ["Renumber Cues in \u{201C}Act One\u{201D}\u{2026}", "Renumber All Cues\u{2026}"]
                      && groupMenu.contains("Renumber Cues in \u{201C}Act One\u{201D}\u{2026}"),
                      "a cue's right-click menu renumbers its group: \(cueMenu.joined(separator: " | "))")
            }
            controller.renumber(group: group, from: 100)
            let numbers = controller.show.cues(inGroup: group).compactMap { controller.show[$0]?.number }
            check(numbers.first == "100" && numbers.count == controller.show.cues.count, "a group renumbers from where it is told: \(numbers)")
            controller.renumberAll()
            controller.deleteGroup(group)
        }

        // Tab runs down what the cue shows, then where it comes in the book,
        // skipping what this kind of cue doesn't have.
        if let console = document.console {
            func stops(for id: UUID) -> [String] {
                controller.standBy(id)
                console.refresh()
                console.window?.contentView?.layoutSubtreeIfNeeded()
                return console.editor.tabStops
            }
            let decryption = stops(for: titleID), image = stops(for: imageID)
            if let anagramID = controller.addCue(.anagram) {
                let anagram = stops(for: anagramID)
                check(anagram == ["anagrams", "number", "line"], "Tab through an anagram cue: \(anagram.joined(separator: ", "))")
                controller.deleteCue(anagramID)
            }
            check(decryption == ["text", "sub", "key", "number", "line"], "Tab through a decryption cue: \(decryption.joined(separator: ", "))")
            check(image == ["text", "number", "line"], "Tab through an image cue, which has no caption: \(image.joined(separator: ", "))")
        }

        document.importMedia(from: picture, into: imageID)
        let src = controller.show[imageID]?.mediaPath ?? ""
        check(src == "media/gallery.png", "an imported picture gets a path in the package: \(src)")
        check(document.mediaURL(src) == picture, "before saving, it is read from where it came from")
        check(document.undoManager?.canUndo == true, "edits are undoable")

        let url = folder.appendingPathComponent("Check.prospect")
        try? FileManager.default.removeItem(at: url)
        document.save(to: url, ofType: ShowDocument.typeName, for: .saveAsOperation) { error in
            MainActor.assumeIsolated {
                check(error == nil, "Save As writes the package \(error.map { "\($0)" } ?? "")")
                let fm = FileManager.default
                check(fm.fileExists(atPath: url.appendingPathComponent("show.json").path)
                      && fm.fileExists(atPath: url.appendingPathComponent("version").path)
                      && fm.fileExists(atPath: url.appendingPathComponent(src).path), "show.json, version and the picture are in the package")
                check(document.mediaURL(src) == url.appendingPathComponent(src), "after saving, the picture is read from the package")
                let before = inode(url.appendingPathComponent(src))

                controller.updateCue(titleID, "Change Cue Point") { $0.line = "LANGDON: \u{201C}\u{2026}the rose line.\u{201D}" }
                document.save(to: url, ofType: ShowDocument.typeName, for: .saveOperation) { error in
                    MainActor.assumeIsolated {
                        check(error == nil, "Save writes again")
                        check(before != nil && inode(url.appendingPathComponent(src)) == before, "the second save left the picture where it was")
                        let json = (try? String(contentsOf: url.appendingPathComponent("show.json"), encoding: .utf8)) ?? ""
                        check(json.contains("the rose line"), "show.json has the edit")
                        document.close()

                        NSDocumentController.shared.openDocument(withContentsOf: url, display: false) { reopened, _, error in
                            MainActor.assumeIsolated {
                                let reopened = reopened as? ShowDocument
                                check(reopened != nil && error == nil, "the show reopens")
                                reopened?.makeWindowControllers()
                                check(reopened?.controller?.mode == .show, "a show opened from disk opens in show mode")
                                check(reopened?.show.cues.count == 2, "both cues came back")
                                let resolved = reopened?.mediaURL(src)?.standardizedFileURL.path
                                let expected = url.appendingPathComponent(src).standardizedFileURL.path
                                check(resolved == expected, "media resolve inside the package: \(resolved ?? "nil") / fileURL \(reopened?.fileURL?.absoluteString ?? "nil")")
                                check(reopened?.controller?.addCue(.blank) == nil, "and can't be edited until edit mode")

                                // The cue sheet, through what the menu items use.
                                let operation = try? reopened?.printOperation(withSettings: [:])
                                check(operation?.view is CueSheetView, "Print Cue Sheet prints the cue sheet")
                                let pdf = folder.appendingPathComponent("Check cue sheet.pdf")
                                if let reopened {
                                    check(CueSheetPrinting.exportPDF(for: reopened.show, title: reopened.sheetTitle, layout: .dsm,
                                                                     paper: CueSheetView.a4, to: pdf), "Export Cue Sheet as PDF writes a file")
                                }
                                let size = (try? FileManager.default.attributesOfItem(atPath: pdf.path)[.size] as? NSNumber)?.intValue ?? 0
                                check(size > 1000, "and it isn't empty (\(size) bytes)")
                                finish(in: folder, closing: reopened)
                            }
                        }
                    }
                }
            }
        }
    }
}
#endif
