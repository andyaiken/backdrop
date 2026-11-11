#if DEBUG
import AppKit
import BackdropCore
import BackdropStage
import UniformTypeIdentifiers

/// Debug builds only: offers Backdrop pictures and clips the ways other apps
/// do, and photos as an iPhone sends them, checks each lands where it
/// should, and writes what it found to result.txt.
///
///     Backdrop.app/Contents/MacOS/Backdrop -BackdropMediaCheck /some/folder
///
/// A promised file can only be received during a real drag, so promises are
/// checked only as far as what they say they will be. Dragging from Photos
/// or Safari itself has to be tried by hand. The show is in memory, so
/// nothing on disk or in Open Recent changes.
@MainActor
enum MediaCheck {
    private static var lines: [String] = []
    private static var failed = false

    private static func check(_ ok: Bool, _ what: String) {
        lines.append((ok ? "PASS  " : "FAIL  ") + what)
        if !ok { failed = true }
    }

    static func run(in directory: String) {
        let folder = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        steps(in: folder)
        try? (lines.joined(separator: "\n") + "\n").write(to: folder.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        exit(failed ? 1 : 0)
    }

    /// A private pasteboard, filled as a drag or an iPhone would fill one.
    private static func pasteboard(_ fill: (NSPasteboard) -> Void) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("BackdropMediaCheck-\(UUID().uuidString)"))
        pasteboard.clearContents()
        fill(pasteboard)
        return pasteboard
    }

    private static func picture(_ type: NSBitmapImageRep.FileType) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: type, properties: [:])!
    }

    /// Never asked for anything: a promise can't be received outside a drag.
    private final class Promiser: NSObject, NSFilePromiseProviderDelegate {
        func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { "IMG_0001" }
        func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL,
                                 completionHandler: @escaping (Error?) -> Void) { completionHandler(nil) }
    }

    private static func steps(in folder: URL) {
        // A picture as data, named by the web address beside it, as a
        // browser offers one.
        let png = picture(.png)
        let fromWeb = pasteboard { pasteboard in
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            item.setString("https://example.com/art/louvre.png", forType: .URL)
            pasteboard.writeObjects([item])
        }
        let web = MediaDrop(fromWeb)
        check(web?.types == [.png], "a picture offered as data is offered as a PNG")
        var received: [URL] = []
        web?.receive { received = $0 }
        check(received.map(\.lastPathComponent) == ["louvre.png"], "and named for its web address: \(received.map(\.lastPathComponent))")
        check(received.first.flatMap { try? Data(contentsOf: $0) } == png, "with the picture's own bytes")

        // Files, as Finder offers them.
        let still = folder.appendingPathComponent("still.jpg"), clip = folder.appendingPathComponent("clip.mov")
        try? picture(.jpeg).write(to: still)
        try? Data().write(to: clip)
        let finder = MediaDrop(pasteboard { $0.writeObjects([still as NSURL, clip as NSURL]) })
        check(finder?.types == [.jpeg, .quickTimeMovie], "files are offered by their types: \(finder?.types.map(\.identifier) ?? [])")
        finder?.receive { received = $0 }
        check(received == [still, clip], "and come in as they are, without copying")

        // Promised files, as Photos and Safari offer them: what each will be
        // is known before the drop, so the cue list can say where it would go.
        let promiser = Promiser()
        let promised = MediaDrop(pasteboard {
            $0.writeObjects([NSFilePromiseProvider(fileType: UTType.heic.identifier, delegate: promiser),
                             NSFilePromiseProvider(fileType: UTType.quickTimeMovie.identifier, delegate: promiser)])
        })
        check(promised?.types == [.heic, .quickTimeMovie], "promised files are offered by the types they will be: \(promised?.types.map(\.identifier) ?? [])")
        check(ShowDocument.cueKind(for: .heic) == .image && ShowDocument.cueKind(for: .quickTimeMovie) == .video,
              "a promised photo would make an image cue, and a promised clip a video cue")
        withExtendedLifetime(promiser) {}
        check(MediaDrop(pasteboard { $0.setString("hello", forType: .string) }) == nil, "text offers nothing")

        // Continuity Camera: photos as an iPhone sends them.
        let show = Show(title: "Media check", cues: [
            Cue(number: "1", content: .image(ImageContent(text: "Waiting"))),
            Cue(number: "2", content: .title(TitleContent(text: "THE LOUVRE"))),
        ])
        let document = ShowDocument(show: show, warnings: [])
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        guard let controller = document.controller, let console = document.console else {
            check(false, "the show opens")
            return
        }
        let jpeg = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        func photo() -> NSPasteboard { pasteboard { $0.setData(picture(.jpeg), forType: jpeg) } }
        func takes(_ type: NSPasteboard.PasteboardType) -> Bool {
            (console.validRequestor(forSendType: nil, returnType: type) as? ConsoleWindowController) === console
        }
        check(controller.mode == .edit, "a new show is in edit mode")
        check(takes(jpeg), "in edit mode, the console takes photos from an iPhone")
        check(!takes(.string), "but not text")

        controller.standBy(controller.show.cues[0].id)
        check(console.readSelection(from: photo()), "a photo is taken")
        if case .image(let content) = controller.show.cues[0].content {
            check(content.src.hasSuffix("/Photo.jpeg"), "into the image cue standing by, which was waiting for one: \(content.src)")
        } else {
            check(false, "cue 1 is still an image cue")
        }
        check(controller.show.cues.count == 2, "and no cue is added")

        controller.standBy(controller.show.cues[1].id)
        _ = console.readSelection(from: photo())
        let added = controller.show.cues.count == 3 ? controller.show.cues[2] : nil
        if case .image(let content)? = added?.content {
            check(content.text == "Photo" && content.src.hasSuffix("/Photo 2.jpeg"),
                  "after any other cue, a new image cue named Photo: \(content.text), \(content.src)")
        } else {
            check(false, "after any other cue, a new image cue, after the one standing by: \(controller.show.cues.map(\.kind.name))")
        }

        controller.enterShowMode()
        check(!takes(jpeg), "in show mode, the console takes nothing")
        check(!console.readSelection(from: photo()) && controller.show.cues.count == 3, "and a photo sent anyway changes nothing")

        let edit = NSApp.mainMenu?.items.first { $0.title == "Edit" }?.submenu
        check(edit?.items.contains { $0.identifier == NSMenuItem.importFromDeviceIdentifier } == true, "Edit has Import from iPhone or iPad")
    }
}
#endif
