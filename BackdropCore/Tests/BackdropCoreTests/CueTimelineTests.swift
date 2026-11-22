import Foundation
import Testing
@testable import BackdropCore

@Suite("Cue timeline")
struct CueTimelineTests {
    @Test("A decryption: the hold, then a bar per moving letter, fanned by the wave")
    func decryption() {
        var settings = TitleSettings()
        settings.holdTicks = 44
        settings.waveTicks = 3
        let cue = Cue(content: .title(TitleContent(text: "THE LAST LIGHT", key: "LANTERN", settings: settings)))
        let t = CueTimeline(cue: cue, show: ShowSettings(), isFirst: true)
        #expect(t.holdTicks == 44)
        #expect(t.transitionIn == nil, "the first cue has no transition in")
        let letters = try! #require(t.tracks.first)
        #expect(letters.name == "Letters")
        #expect(letters.spans.count == 14, "every character of THE LAST LIGHT travels, its spaces too: the ring has a space")
        #expect(letters.spans.allSatisfy { $0.start >= 44 })
        // The fan: each letter sets off later than the one before.
        let starts = letters.spans.map(\.start)
        #expect(starts == starts.sorted())
        #expect(t.endFrame == letters.spans.map(\.end).max())
        #expect(t.goes.isEmpty)
        #expect(t.then == .waits)
    }

    @Test("A keypad: a tick per key press at the pause, then the verdict flash")
    func keypad() {
        var content = KeypadContent(text: "Safe", script: "4417\nGOOD")
        content.settings.holdTicks = 20
        content.settings.pauseTicks = 14
        let cue = Cue(content: .keypad(content))
        let t = CueTimeline(cue: cue, show: ShowSettings(), isFirst: false)
        let keys = t.tracks[0].spans
        // 4, 4, 1, 7: the first stage. Then GOOD's OK, in the second.
        #expect(keys.prefix(4).map(\.start) == [20, 34, 48, 62])
        #expect(t.goes == [20 + 4 * 14], "the second stage waits for GO after the first's four presses")
        #expect(keys.last?.start == 20 + 4 * 14, "OK is pressed as the second stage starts")
        let flash = t.tracks[1].spans[0]
        #expect(flash.start == 20 + 4 * 14 + 14)
        #expect(flash.end == flash.start + KeypadCuePlan.flashTicks)
        #expect(t.endFrame == flash.end)
    }

    @Test("The transition in is the fade's length, and the first cue has none")
    func transition() {
        var cue = Cue(content: .blank(BlankContent()))
        cue.transition = Transition(style: .fade, fadeMs: 880)
        let t = CueTimeline(cue: cue, show: ShowSettings(), isFirst: false)
        #expect(t.transitionIn?.end == 20, "880 ms at the standard 44 ms clock")
        #expect(t.transitionIn?.key == .fade)
        cue.transition = Transition(style: .snap)
        #expect(CueTimeline(cue: cue, show: ShowSettings(), isFirst: false).transitionIn?.end == 0)
    }

    @Test("A morph with each stage on GO: a bar per stage, and a GO between them")
    func morph() {
        var settings = MorphSettings()
        settings.clockMs = 40
        settings.holdTicks = 10
        settings.morphMs = 2000
        settings.advance = .eachStep
        let cue = Cue(content: .morph(MorphContent(pictures: [MorphPicture(src: "a.png"), MorphPicture(src: "b.png"),
                                                              MorphPicture(src: "c.png")], settings: settings)))
        let t = CueTimeline(cue: cue, show: ShowSettings(), isFirst: false)
        let stages = t.tracks[0].spans
        #expect(stages.count == 2)
        #expect(stages[0].end - stages[0].start == 50, "2000 ms at 40 ms a frame")
        // The cue opens on its first picture and waits: each stage is a GO.
        #expect(t.goes == [10, 60])
        #expect(stages.map(\.start) == t.goes)
    }

    @Test("Then: waits for GO, or a timed continue")
    func then() {
        var cue = Cue(content: .text(TextContent(text: "Six weeks later")))
        #expect(CueTimeline(cue: cue, show: ShowSettings(), isFirst: false).then == .waits)
        cue.continueMode = .after(ms: 3000)
        #expect(CueTimeline(cue: cue, show: ShowSettings(), isFirst: false).then == .after(ms: 3000))
    }

    @Test("A video's length is passed in, since the model can't open its file")
    func video() {
        let cue = Cue(content: .video(VideoContent(text: "Storm", src: "media/storm.mov")))
        let t = CueTimeline(cue: cue, show: ShowSettings(), isFirst: false, clipSeconds: 4.4)
        #expect(t.tracks.first?.spans.first?.end == 100)
        #expect(CueTimeline(cue: cue, show: ShowSettings(), isFirst: false).tracks.isEmpty)
    }
}

/// The demo show's cues, each laid out, recorded once. A change that alters
/// them alters what the timeline says the stage does, so it should be
/// deliberate. Set RECORD_TIMELINE to write the fixture afresh.
@Suite("Cue timeline: recorded")
struct CueTimelineFixtureTests {
    static var show: [Cue] {
        var keypad = KeypadContent(text: "Safe", script: "4417\nGOOD")
        keypad.settings.pauseTicks = 14
        var anagram = AnagramContent(anagrams: [Anagram(text: "LISTEN", answer: "SILENT"), Anagram(text: "THE EYES", answer: "THEY SEE")])
        anagram.settings.advance = .eachAnagram
        var cues = [
            Cue(number: "1", content: .title(TitleContent(text: "THE LAST LIGHT", sub: "A play in two acts", key: "LANTERN"))),
            Cue(number: "2", content: .image(ImageContent(text: "Dusk", src: "dusk.png"))),
            Cue(number: "3", content: .anagram(anagram)),
            Cue(number: "4", content: .cascade(CascadeContent(text: "COME HOME"))),
            Cue(number: "5", content: .keypad(keypad)),
            Cue(number: "6", content: .text(TextContent(text: "Six weeks later"))),
        ]
        cues[3].continueMode = .after(ms: 3000)
        return cues
    }

    static func computed() -> [CueTimeline] {
        show.enumerated().map { i, cue in CueTimeline(cue: cue, show: ShowSettings(), isFirst: i == 0) }
    }

    @Test("The demo show's timelines are as recorded")
    func recorded() throws {
        let timelines = Self.computed()
        if let folder = ProcessInfo.processInfo.environment["RECORD_TIMELINE"] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(timelines).write(to: URL(fileURLWithPath: folder).appendingPathComponent("timeline.json"))
            return
        }
        #expect(try Fixtures.load("timeline", as: [CueTimeline].self) == timelines)
    }
}
