#if DEBUG
import AppIntents
import AppKit
import BackdropCore
import BackdropStage
import CoreSpotlight

/// Debug builds only: runs Backdrop's intents and their queries against a
/// show, as Shortcuts and Spotlight would, puts a show into Spotlight and
/// finds it there by a word on one of its cues, and writes what it found to
/// result.txt.
///
///     Backdrop.app/Contents/MacOS/Backdrop -BackdropIntentsCheck /some/folder
///
/// The show is in memory, and the one put into Spotlight is taken out
/// again, so nothing on disk, in Open Recent or in Spotlight changes.
@MainActor
enum IntentsCheck {
    private static var lines: [String] = []
    private static var failed = false

    private static func check(_ ok: Bool, _ what: String) {
        lines.append((ok ? "PASS  " : "FAIL  ") + what)
        if !ok { failed = true }
    }

    static func run(in directory: String) {
        let folder = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Task {
            await steps(in: folder)
            try? (lines.joined(separator: "\n") + "\n").write(to: folder.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
            exit(failed ? 1 : 0)
        }
    }

    private static func steps(in folder: URL) async {
        var louvre = Cue(number: "1", content: .title(TitleContent(text: "THE LOUVRE", sub: "PARIS")))
        louvre.line = "SOPHIE: \u{201C}Come with me.\u{201D}"
        let show = Show(title: "Intents check", cues: [
            louvre,
            Cue(number: "2", content: .image(ImageContent(text: "Mona Lisa"))),
            Cue(number: "3", content: .blank(BlankContent())),
        ])
        let document = ShowDocument(show: show, warnings: [])
        // A show macOS restored at launch would otherwise be the one open,
        // which intents act on. Backdrop has one show open at a time.
        let restored = NSDocumentController.shared.documents
        NSDocumentController.shared.addDocument(document)
        for other in restored { other.close() }
        document.makeWindowControllers()
        guard let controller = document.controller else {
            check(false, "the show opens")
            return
        }
        controller.enterShowMode()
        check(OpenShow.controller === controller, "intents find the show open")

        // The cue query, as Shortcuts asks it.
        let query = CueQuery()
        let all = (try? await query.suggestedEntities()) ?? []
        check(all.map(\.title) == ["Cue 1: THE LOUVRE", "Cue 2: Mona Lisa", "Cue 3: Blank cue"], "every cue is offered, named by number and words: \(all.map(\.title))")
        let found = (try? await query.entities(matching: "mona")) ?? []
        check(found.map(\.id) == ["2"], "a cue is found by its words")
        check(((try? await query.entities(matching: "3")) ?? []).map(\.id) == ["3"], "and by its number")
        check(((try? await query.entities(for: ["1", "9"])) ?? []).map(\.id) == ["1"], "a saved cue number finds that cue, and one not in the show finds nothing")

        // Stand By Cue.
        // A parameter is set through its wrapper, so the intent itself needn't be mutable.
        let standBy = StandByCueIntent()
        standBy.cue = all[2]
        _ = try? await standBy.perform()
        check(controller.playhead.standby.flatMap { controller.show[$0]?.number } == "3", "Stand By Cue stands cue 3 by")
        check(controller.playhead.live == nil, "and fires nothing")
        check(controller.message == "Standby for cue 3 arrived by a shortcut.", "and the status line says so: \(controller.message ?? "nothing")")

        // Blackout, each way.
        let blackout = BlackoutIntent()
        blackout.change = .on
        _ = try? await blackout.perform()
        check(controller.playhead.blackout, "Blackout On blacks out")
        blackout.change = .toggle
        _ = try? await blackout.perform()
        check(!controller.playhead.blackout, "Blackout On or Off brings the picture back when blacked out")
        _ = try? await blackout.perform()
        check(controller.playhead.blackout, "and blacks out when not")
        blackout.change = .off
        _ = try? await blackout.perform()
        check(!controller.playhead.blackout, "Blackout Off brings the picture back")

        // Nothing in edit mode.
        controller.enterEditMode()
        var refused: Error?
        do { _ = try await standBy.perform() } catch { refused = error }
        check((refused as? ShowIntentError) == .editMode, "in edit mode, a shortcut is refused, and says why")
        controller.enterShowMode()

        // Spotlight: a show put in, found by a word on a cue, taken out.
        let word = "zq" + UUID().uuidString.prefix(8).lowercased()
        var marked = show
        marked.cues[1].text = "Mona Lisa \(word)"
        let entity = ShowEntity(url: folder.appendingPathComponent("Intents check.backdrop"), show: marked)
        check(entity.attributeSet.textContent?.contains(word) == true, "a show's cue words go to Spotlight with it")
        do {
            try await CSSearchableIndex.default().indexAppEntities([entity])
            check(true, "the show is put into Spotlight")
        } catch {
            check(false, "the show is put into Spotlight: \(error)")
        }
        var hits: [String] = []
        let deadline = Date().addingTimeInterval(15)
        while hits.isEmpty, Date() < deadline {
            hits = await search("textContent == \"*\(word)*\"cd")
            if hits.isEmpty { try? await Task.sleep(for: .milliseconds(500)) }
        }
        // App Intents names an entity's item by its type, then its identifier.
        check(hits.contains("ShowEntity/" + entity.id), "Spotlight finds it by a word on a cue: \(hits)")
        try? await CSSearchableIndex.default().deleteAppEntities(identifiedBy: [entity.id], ofType: ShowEntity.self)
        var gone = false
        let later = Date().addingTimeInterval(15)
        while !gone, Date() < later {
            gone = await search("textContent == \"*\(word)*\"cd").isEmpty
            if !gone { try? await Task.sleep(for: .milliseconds(500)) }
        }
        check(gone, "and it is taken out again")
    }

    /// The identifiers of Backdrop's own Spotlight items that match.
    private static func search(_ queryString: String) async -> [String] {
        await withCheckedContinuation { (done: CheckedContinuation<[String], Never>) in
            let query = CSSearchQuery(queryString: queryString, queryContext: nil)
            let found = Found()
            query.foundItemsHandler = { items in found.add(items.map(\.uniqueIdentifier)) }
            query.completionHandler = { _ in done.resume(returning: found.all) }
            query.start()
        }
    }

    private final class Found: @unchecked Sendable {
        private let lock = NSLock()
        private var ids: [String] = []
        func add(_ more: [String]) { lock.withLock { ids += more } }
        var all: [String] { lock.withLock { ids } }
    }
}
#endif
