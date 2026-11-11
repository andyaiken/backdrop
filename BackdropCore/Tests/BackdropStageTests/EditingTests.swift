import CoreText
import BackdropCore
import Testing
@testable import BackdropStage

@Suite("Editing the sheet")
@MainActor
struct EditingTests {
    final class Log {
        var edits: [(Show, String)] = []
        var fired: [String] = []
    }

    let log = Log()

    func controller(_ cues: [Cue] = [], mode: ShowController.Mode = .edit) -> ShowController {
        let c = ShowController(show: Show(cues: cues), mode: mode, renderers: [.title: TitleRenderer(reduceMotion: { true })])
        let log = self.log
        c.onEdit = { log.edits.append(($0, $1)) }
        c.onFire = { log.fired.append($0.number) }
        return c
    }

    func numbered(_ number: String) -> Cue {
        var cue = titleCue("CUE \(number)")
        cue.number = number
        return cue
    }

    @Test func showModeLocksTheSheet() {
        let c = controller([numbered("1")], mode: .show)
        #expect(c.addCue(.title) == nil)
        #expect(!c.addCues([numbered("2")], at: 1, "Add Cues"))
        c.deleteCue(c.show.cues[0].id)
        c.setGeometry(Geometry(width: 50))
        #expect(c.show.cues.count == 1 && c.show.settings.geometry == Geometry())
        #expect(log.edits.isEmpty)
    }

    @Test func addingInsertsAfterTheStandbyCueAndStandsItBy() throws {
        let c = controller([numbered("1"), numbered("2")])
        let id = try #require(c.addCue(.image))
        #expect(c.show.cues.map(\.number) == ["1", "1.5", "2"])
        #expect(c.playhead.standby == id)
        #expect(log.edits.last?.1 == "Add Image Cue")
        #expect(log.edits.last?.0.cues.count == 2, "the sheet before, for undo")
    }

    @Test("Adding, moving, changing and removing layers are each one undo step")
    func layerEditsAreSingleUndoSteps() throws {
        let c = controller()
        let id = try #require(c.addCue(.layered))
        #expect(c.show[id]?.kind == .layered && log.edits.last?.1 == "Add Layered Image Cue")
        func change(_ name: String, _ body: @escaping (inout LayeredContent) -> Void) {
            c.updateCue(id, name) { cue in
                if case .layered(var l) = cue.content { body(&l); cue.content = .layered(l) }
            }
        }
        func layers() -> [String] {
            guard case .layered(let l) = c.show[id]?.content else { return [] }
            return l.layers.map(\.name)
        }
        for name in ["a", "b", "c"] { change("Add Layer") { $0.layers.append(ImageLayer(src: "\(name).png", name: name)) } }
        #expect(layers() == ["a", "b", "c"] && log.edits.count == 4)
        change("Move Layer") { $0.moveLayer(from: 0, to: 2) }
        #expect(layers() == ["b", "c", "a"] && log.edits.count == 5 && log.edits.last?.1 == "Move Layer")
        #expect(log.edits.last?.0.cues.first.map { if case .layered(let l) = $0.content { l.layers.map(\.name) } else { [] } } == ["a", "b", "c"],
                "the sheet before, for undo")
        change("Remove Layer") { $0.removeLayer(at: 1) }
        #expect(layers() == ["b", "a"] && log.edits.count == 6)
        change("Change Layer Life") { $0.layers[0].life = .untilNextGo }
        var onGo = try! #require(c.show[id])
        SettingKey.advance.set(.advance(.eachStep), in: &onGo)
        #expect(onGo.goPoints().map(\.text) == ["b", "b goes", "a"])
        change("Move Layer") { $0.moveLayer(from: 0, to: 0) }
        #expect(log.edits.count == 7, "a move to the same place changes nothing, and is no edit")
    }

    @Test("A new cue starts with every field empty")
    func newCuesStartEmpty() {
        let c = controller()
        for kind in Cue.Kind.allCases { c.addCue(kind) }
        #expect(c.show.cues.map(\.kind) == Cue.Kind.allCases)
        for cue in c.show.cues {
            #expect(cue.text.isEmpty && cue.sub.isEmpty && cue.line.isEmpty, "\(cue.kind)")
        }
        guard case .title(let decryption) = c.show.cues[0].content else { return }
        #expect(decryption.key.isEmpty)
    }

    @Test("An empty decryption fires, shows nothing and settles after its hold")
    func emptyDecryptionFires() throws {
        var time = 100.0
        let titles = TitleRenderer(random: SeededRandom(seed: 3), reduceMotion: { true })
        let c = ShowController(show: Show(), mode: .edit, renderers: [.title: titles], now: { time })
        let live = surface()
        c.runner.attach(live)
        let id = try #require(c.addCue(.title))
        c.enterShowMode()
        c.standBy(id)
        c.go()
        #expect(c.playhead.live == id)
        time += 30
        c.tick(at: time)
        #expect(!c.runner.isRunning)
        #expect(text(of: try #require(titles.tree(for: live)).title.runs).isEmpty)
    }

    @Test("Cues added together, as files dropped on the list are, are one undo step")
    func addingSeveralCuesAtAPlace() {
        let c = controller([numbered("1"), numbered("2")])
        let a = Cue(content: .image(ImageContent(text: "LOUVRE", src: "media/louvre.jpg")))
        let b = Cue(content: .video(VideoContent(text: "RAIN", src: "media/rain.mov")))
        #expect(c.addCues([a, b], at: 1, "Add Cues"))
        #expect(c.show.cues.map(\.number) == ["1", "1.5", "1.8", "2"])
        #expect(c.show.cues[1].id == a.id && c.show.cues[2].id == b.id, "in the order given")
        #expect(c.playhead.standby == a.id, "the first stands by")
        #expect(log.edits.count == 1 && log.edits.last?.1 == "Add Cues")
        #expect(log.edits.last?.0.cues.count == 2, "the sheet before, for undo")
        #expect(!c.addCues([], at: 0, "Add Cues") && log.edits.count == 1, "nothing to add isn't an edit")
    }

    @Test func anEmptySheetGetsCueOne() {
        let c = controller()
        c.addCue(.blank)
        #expect(c.show.cues.map(\.number) == ["1"])
        #expect(c.show.cues[0].kind == .blank)
    }

    @Test func updatingMovingDeleting() {
        let c = controller([numbered("1"), numbered("2"), numbered("3")])
        let second = c.show.cues[1].id
        c.updateCue(second, "Change Cue Point") { $0.line = "LANGDON: \u{201C}\u{2026}the rose line.\u{201D}" }
        #expect(c.show[second]?.line.hasPrefix("LANGDON") == true)
        c.moveCue(second, by: -1)
        #expect(c.show.cues.map(\.number) == ["2", "1", "3"], "numbers move with their cues")
        c.moveCue(second, by: -5)
        #expect(log.edits.count == 2, "a move that goes nowhere isn't an edit")
        c.standBy(second)
        c.deleteCue(second)
        #expect(c.show.cues.map(\.number) == ["1", "3"])
        #expect(c.playhead.standby == c.show.cues[0].id, "standby moves to what took the deleted cue's place")
    }

    @Test func undoPutsTheWholeSheetBack() {
        let c = controller([numbered("1"), numbered("2")])
        c.renumberAll()
        c.addCue(.title)
        let (before, name) = log.edits.last!
        #expect(name == "Add Decryption Cue")
        c.restore(before)
        #expect(c.show == before)
        c.setGeometry(Geometry(width: 60))
        c.restore(log.edits.last!.0)
        #expect(c.show.settings.geometry == Geometry())
        #expect(c.runner.geometry == Geometry(), "the stage follows an undo")
    }

    @Test func aDisplayChosenInShowModeIsntAnEdit() {
        let c = controller([numbered("1")], mode: .show)
        c.setProjectorDisplay(DisplayIdentity(uuid: "E", name: "EPSON"))
        #expect(c.show.settings.projector?.name == "EPSON")
        #expect(log.edits.isEmpty)
        let e = controller([numbered("1")])
        e.setProjectorDisplay(DisplayIdentity(uuid: "E", name: "EPSON"))
        #expect(log.edits.last?.1 == "Choose Projector Display")
    }

    @Test func everyFireIsReportedForTheCrashRecord() {
        var first = numbered("1")
        first.continueMode = .whenFinished
        let c = controller([first, numbered("2"), numbered("3")], mode: .show)
        c.go()
        c.tick(at: 1e6)
        c.tick(at: 1e6 + 0.02)
        #expect(log.fired == ["1", "2"], "GO, then the continue")
        c.resume(at: c.show.cues[2].id)
        #expect(log.fired.last == "3")
        #expect(c.playhead.live == c.show.cues[2].id)
    }
}

@Suite("Settings")
@MainActor
struct SettingsEditingTests {
    final class Log {
        var edits: [String] = []
        var merged = 0
        var time = 0.0
    }

    let log = Log()
    let titles = TitleRenderer(reduceMotion: { true })

    func controller(_ cues: [Cue] = []) -> ShowController {
        let log = self.log
        let c = ShowController(show: Show(cues: cues), mode: .edit, renderers: [.title: titles], now: { log.time })
        c.onEdit = { log.edits.append($1) }
        c.onMergedEdit = { log.merged += 1 }
        return c
    }

    @Test func textSizeIsAnUndoableEdit() {
        let c = controller()
        c.setTextScale(80)
        #expect(c.show.settings.textScale == 80)
        #expect(log.edits == ["Change Text Size"])
        c.enterShowMode()
        c.setTextScale(60)
        #expect(c.show.settings.textScale == 80, "locked in show mode")
    }

    @Test func aSliderDragIsOneUndoStep() {
        let title = titleCue("THE LOUVRE")
        let c = controller([title])
        for (i, value) in [40, 50, 60, 70].enumerated() {
            log.time = Double(i) * 0.05
            c.setSetting(.hold, to: .number(value), for: title.id, coalescing: true)
        }
        #expect(log.edits.count == 1 && log.merged == 3)
        #expect(c.show[title.id]!.timing.holdTicks == 70)

        log.time = 10
        c.setSetting(.hold, to: .number(20), for: title.id, coalescing: true)
        c.setSetting(.wave, to: .number(5), for: title.id, coalescing: true)
        #expect(log.edits.count == 3, "a pause, or a different setting, starts a new step")
        c.setGeometry(Geometry(width: 80), coalescing: true)
        c.setGeometry(Geometry(width: 70), coalescing: true)
        #expect(log.edits.last == "Change Projection Area" && log.edits.count == 4)
    }

    @Test func aCuesSettingsAreSetOnTheCue() throws {
        let image = Cue(number: "2", content: .image(ImageContent(text: "GALLERY")))
        let c = controller([image])
        c.setSetting(.grid, to: .number(20), for: image.id)
        #expect(SettingKey.grid.value(in: c.show[image.id]!) == .number(20))
        #expect(log.edits.last == "Change Grid for Cue 2")
        c.setSetting(.histogram, to: .flag(false), for: image.id)
        #expect(log.edits.count == 1, "an image has no histogram to set")
    }

    @Test func aCuesSettingIsWhatItRunsWith() {
        let title = titleCue("THE LOUVRE")
        let c = controller([title])
        c.setSetting(.hold, to: .number(4), for: title.id)
        #expect(c.show[title.id]!.timing.holdTicks == 4)
    }

    @Test func textSizeRefitsATitleOnStage() throws {
        let stage = surface()
        let c = controller([titleCue("THE LOUVRE")])
        c.runner.attach(stage)
        c.go()
        let before = CTFontGetSize(try #require(tree(titles, on: stage)?.layout).titleFont)
        c.setTextScale(50)
        let after = CTFontGetSize(try #require(tree(titles, on: stage)?.layout).titleFont)
        #expect(abs(after - before / 2) < 0.01)
    }
}

@Suite("Editing what is on stage")
@MainActor
struct LiveEditTests {
    let titles = TitleRenderer(random: SeededRandom(seed: 8), reduceMotion: { true })
    let stage = surface()

    func controller(_ cues: [Cue]) -> ShowController {
        let c = ShowController(show: Show(cues: cues), mode: .edit, renderers: [.title: titles])
        c.runner.attach(stage)
        return c
    }

    func onStage() -> String { text(of: tree(titles, on: stage)!.title.runs) }

    @Test("An edit to the cue on stage shows at once, finished")
    func redrawsTheLiveCue() {
        let louvre = titleCue("THE LOUVRE")
        let c = controller([louvre])
        c.go()
        #expect(c.runner.isRunning, "mid-reveal")
        c.updateCue(louvre.id, "Change Place") { $0.text = "THE TUILERIES" }
        #expect(onStage() == "THE TUILERIES")
        #expect(!c.runner.isRunning, "drawn finished, not run again")
    }

    @Test("A redraw never sets off a continue")
    func redrawDoesntContinue() {
        var first = titleCue("THE LOUVRE")
        first.continueMode = .whenFinished
        var second = titleCue("ROSSLYN")
        second.number = "2"
        let c = controller([first, second])
        c.go()
        c.updateCue(first.id, "Change Place") { $0.text = "THE TUILERIES" }
        for i in 1...5 { c.tick(at: Double(i) * 0.02 + 1e6) }
        #expect(c.playhead.live == first.id, "the next cue waits for a real settle")
    }

    @Test("Edits elsewhere leave the stage alone")
    func editsElsewhere() {
        let first = titleCue("THE LOUVRE")
        var second = titleCue("ROSSLYN")
        second.number = "2"
        let c = controller([first, second])
        c.go()
        c.updateCue(second.id, "Change Place") { $0.text = "ROSSLYN CHAPEL" }
        #expect(c.runner.isRunning, "the cue on stage carries on resolving")
    }

    @Test("Geometry and text size relayout the cue on stage rather than redrawing it")
    func geometryDoesntRedraw() {
        let c = controller([titleCue("THE LOUVRE")])
        c.go()
        c.setGeometry(Geometry(width: 80, height: 80))
        c.setTextScale(80)
        #expect(c.runner.isRunning, "still resolving, not redrawn finished")
        c.setSetting(.sceneLine, to: .flag(false), for: c.show.cues[0].id)
        #expect(!c.runner.isRunning, "a setting titles use does redraw")
    }

    @Test("Deleting the cue on stage takes it off")
    func deletingTheLiveCue() {
        let louvre = titleCue("THE LOUVRE")
        let c = controller([louvre, titleCue("NEXT")])
        c.go()
        c.deleteCue(louvre.id)
        #expect(c.playhead.live == nil)
        #expect(c.runner.cue == nil)
        #expect(tree(titles, on: stage)!.root.isHidden)
    }

    @Test("The show's title is an undoable edit, refused in show mode")
    func title() {
        let c = controller([])
        var names: [String] = []
        c.onEdit = { names.append($1) }
        c.setTitle("  The Da Vinci Code ")
        #expect(c.show.title == "The Da Vinci Code" && names == ["Change Show Title"])
        c.enterShowMode()
        c.setTitle("Something Else")
        #expect(c.show.title == "The Da Vinci Code")
    }
}
