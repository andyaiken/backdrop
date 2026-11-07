import Foundation
import Testing
@testable import ProspectCore

@Suite("Morph stages")
struct MorphStageTests {
    let pair = MorphPair(from: PicturePoint(x: 0.25, y: 0.5), to: PicturePoint(x: 0.75, y: 0.5))

    /// Three pictures, so two stages: into the second with a point, into
    /// the third, a dissolve, in a second of its own.
    func painting(_ settings: MorphSettings = .init()) -> MorphContent {
        MorphContent(text: "PAINTING", pictures: [
            MorphPicture(src: "media/sketch.png"),
            MorphPicture(src: "media/wash.png", pairs: [pair]),
            MorphPicture(src: "media/finished.png", morphMs: 1000),
        ], settings: settings)
    }

    /// 100 ms frames, so a 3 s stage is 30 frames, and a pause of 10.
    let settings = MorphSettings(clockMs: 100, holdTicks: 0, morphMs: 3000, advance: .byItself, pauseTicks: 10)

    @Test("By itself, every stage is in the first part, each a pause after the one before lands")
    func byItself() {
        let plan = MorphCuePlan(painting(), settings: settings)
        #expect(plan.parts == [30 + 10 + 10])
        #expect(plan.stages.map(\.offset) == [0, 40])
        #expect(plan.stages.map(\.morphMs) == [3000, 1000], "the third picture's own time")
        #expect(plan.stages.map(\.mesh) == [MorphMesh(pairs: [pair]), MorphMesh(pairs: [])])
        let timeline = GoTimeline(parts: plan.parts)
        #expect(plan.shown(at: -5, timeline: timeline) == .init(stage: nil, progress: 0), "the first picture through the hold")
        #expect(plan.shown(at: 15, timeline: timeline) == .init(stage: 0, progress: 0.5))
        #expect(plan.shown(at: 35, timeline: timeline) == .init(stage: 0, progress: 1), "resting on the second picture")
        #expect(plan.shown(at: 45, timeline: timeline) == .init(stage: 1, progress: 0.5))
        #expect(!plan.isFinished(at: 49.9, timeline: timeline))
        #expect(plan.isFinished(at: 50, timeline: timeline))
    }

    @Test("Each stage on GO: the first picture stands until GO, and each stage waits for its own")
    func eachOnGO() {
        for advance in [AnagramAdvance.eachAnagram, .eachStep] {
            var s = settings
            s.advance = advance
            let plan = MorphCuePlan(painting(), settings: s)
            #expect(plan.parts == [0, 30, 10], "either GO choice, \(advance)")
            var timeline = GoTimeline(parts: plan.parts)
            #expect(timeline.isWaiting(at: 0))
            #expect(plan.shown(at: 100, timeline: timeline).stage == nil)
            timeline.carryOn(at: 100)
            #expect(plan.shown(at: 115, timeline: timeline) == .init(stage: 0, progress: 0.5))
            #expect(timeline.isWaiting(at: 130) && !plan.isFinished(at: 200, timeline: timeline))
            timeline.carryOn(at: 200)
            #expect(plan.isFinished(at: 210, timeline: timeline))
        }
    }

    @Test("GO straight to a stage puts up the picture before it, and runs it")
    func jump() {
        var s = settings
        s.advance = .eachStep
        let plan = MorphCuePlan(painting(), settings: s)
        var timeline = GoTimeline(parts: plan.parts)
        timeline.jump(toPart: 2, at: 50)
        #expect(plan.shown(at: 50, timeline: timeline) == .init(stage: 1, progress: 0), "the second picture, as it stands")
        #expect(plan.shown(at: 55, timeline: timeline) == .init(stage: 1, progress: 0.5))
    }

    @Test("Each stage on GO is a GO point, named by the picture it becomes; by itself there are none")
    func goPoints() {
        let cue = Cue(content: .morph(painting()))
        #expect(cue.goPoints().isEmpty)
        let onGo = Cue(content: .morph(painting(MorphSettings(advance: .eachAnagram))))
        #expect(onGo.goPoints() == [GoPoint(unit: .stage, text: "wash"), GoPoint(unit: .stage, text: "finished")],
                "either GO choice waits before each stage")
    }

    @Test("A morph's Advance offers By itself or Each stage on GO, and reads so")
    func advanceChoices() {
        #expect(SettingKey.advance.choices(for: .morph).map(\.label) == ["By itself", "Each stage on GO"])
        #expect(SettingKey.advance.choices().map(\.label) == ["By itself", "Each anagram on GO", "Each step on GO"])
        #expect(SettingKey.advance.choiceIndex(of: .advance(.eachAnagram), for: .morph) == 1)
        #expect(SettingKey.advance.format(.advance(.eachAnagram), for: .morph) == "each stage on GO")
        var cue = Cue(content: .morph(MorphContent()))
        SettingKey.advance.set(.advance(.eachStep), in: &cue)
        SettingKey.pause.set(.number(20), in: &cue)
        guard case .morph(let c) = cue.content else { return }
        #expect(c.settings == MorphSettings(advance: .eachStep, pauseTicks: 20))
    }

    @Test("Two pictures keep show.json's flat shape; more, or a stage's own time, take a list and version 4")
    func json() throws {
        let plain = Cue(number: "9", content: .morph(MorphContent(text: "LEONARDO", src: "media/a.jpg", into: "media/b.jpg", pairs: [pair])))
        let flat = try #require(String(data: JSONEncoder().encode(plain), encoding: .utf8))
        #expect(flat.contains("\"into\":\"media\\/b.jpg\"") && !flat.contains("pictures"))
        #expect(Show(cues: [plain]).version == 2)

        let staged = Cue(number: "10", content: .morph(painting()))
        let data = try JSONEncoder().encode(staged)
        let list = try #require(String(data: data, encoding: .utf8))
        #expect(list.contains("\"pictures\":[") && !list.contains("\"into\""))
        #expect(try JSONDecoder().decode(Cue.self, from: data) == staged)
        #expect(Show(cues: [plain, staged]).version == 4)

        var timed = MorphContent(text: "", src: "media/a.jpg", into: "media/b.jpg")
        timed.pictures[1].morphMs = 2000
        #expect(!timed.isPlain, "a stage's own time can't be said in the flat shape")

        let json = #"""
            { "version": 4, "cues": [{ "id": "\#(UUID())", "num": "1", "kind": "morph", "line": "", "text": "",
              "pictures": [{ "src": "a.png", "pairs": [{ "from": [0.1, 0.1], "to": [0.2, 0.2] }] }, { "src": "b.png", "morphMs": 99999 }] }] }
            """#
        let read = try Show(jsonData: Data(json.utf8))
        guard case .morph(let m) = read.cues[0].content else { Issue.record("not a morph"); return }
        #expect(m.pictures[0].pairs.isEmpty, "the first picture has nothing to match from")
        #expect(m.pictures[1].morphMs == SettingRange.morphMs.upperBound, "clamped")
        #expect(read.cues[0].mediaPaths == ["a.png", "b.png"])
    }

    @Test("Reordering keeps a stage's points only while it joins the same two pictures")
    func reorder() {
        var c = painting()
        c.pictures[2].pairs = [pair]
        c.movePicture(from: 2, to: 0)
        #expect(c.pictures.map(\.src) == ["media/finished.png", "media/sketch.png", "media/wash.png"])
        #expect(c.pictures.map(\.pairs) == [[], [], [pair]], "sketch into wash is still a stage, with its point")
        #expect(c.pictures[0].morphMs == nil, "the first picture has no stage into it")
        var d = painting()
        d.removePicture(at: 0)
        #expect(d.pictures.map(\.src) == ["media/wash.png", "media/finished.png"])
        #expect(d.pictures[0].pairs.isEmpty && d.pictures[1].morphMs == 1000)
    }

    @Test("The DSM sheet names the pictures, and gives each stage on GO a row")
    func sheet() {
        let show = Show(title: "T", cues: [Cue(number: "9", content: .morph(painting(MorphSettings(advance: .eachStep))))])
        let rows = CueSheet(show: show, title: "T", layout: .dsm).rows
        #expect(rows.map(\.type) == ["Morph", "GO 1", "GO 2"])
        #expect(rows[0].content == ["PAINTING", "sketch \u{2192} wash \u{2192} finished"])
        #expect(rows[1].content == ["wash"])
        let settings = CueSheet(show: show, title: "T", layout: .operatorSettings).rows[0].settings
        #expect(settings.first { $0.name == "Advance" }?.value == "each stage on GO")
        #expect(settings.filter { $0.name.hasPrefix("Picture") }.map(\.value)
                == ["sketch.png", "wash.png \u{00B7} 1 point", "finished.png \u{00B7} a dissolve \u{00B7} 1.0 s"])
        #expect(show.issues.isEmpty)
    }
}
