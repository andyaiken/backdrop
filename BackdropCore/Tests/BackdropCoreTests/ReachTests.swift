import Foundation
import Testing
@testable import BackdropCore

private func cue(_ number: String, _ continues: ContinueMode = .whenCued) -> Cue {
    Cue(number: number, continueMode: continues, content: .title(TitleContent(text: "CUE \(number)")))
}

@Suite("Reach: what one GO runs")
struct ReachTests {
    @Test("A cue that waits for GO reaches only itself")
    func noContinues() {
        let show = Show(cues: [cue("1"), cue("2")])
        #expect(show.reach(from: show.cues[0].id) == [Reach(cue: show.cues[0], via: .go)])
    }

    @Test("A chain of timed continues, stopping at the cue that waits")
    func afterChain() {
        let show = Show(cues: [cue("1", .after(ms: 3000)), cue("2", .after(ms: 0)), cue("3"), cue("4")])
        #expect(show.reach(from: show.cues[0].id).map(\.via) == [.go, .after(ms: 3000), .after(ms: 0)])
        #expect(show.reach(from: show.cues[0].id).map(\.cue.number) == ["1", "2", "3"])
    }

    @Test("A chain of continues when finished")
    func whenFinishedChain() {
        let show = Show(cues: [cue("5", .whenFinished), cue("6", .whenFinished(waitMs: 2000)), cue("7")])
        #expect(show.reach(from: show.cues[0].id).map(\.via) == [.go, .whenFinished(waitMs: 0), .whenFinished(waitMs: 2000)])
    }

    @Test("A chain runs to the last cue, and no further")
    func toTheEnd() {
        let show = Show(cues: [cue("1"), cue("2", .after(ms: 1000)), cue("3", .after(ms: 1000))])
        #expect(show.reach(from: show.cues[1].id).map(\.cue.number) == ["2", "3"])
        #expect(show.reach(from: UUID()).isEmpty)
    }

    @Test("A looping clip never finishes, so what waits for it isn't reached")
    func loopingClip() {
        var loop = VideoContent(text: "RAIN", src: "media/rain.mov")
        loop.atEnd = .loop
        let clip = Cue(number: "1", continueMode: .whenFinished, content: .video(loop))
        let show = Show(cues: [clip, cue("2")])
        #expect(show.reach(from: clip.id).map(\.cue.number) == ["1"])
        #expect(show.issues.contains(.neverFinishes(cue: clip.id)), "the sheet flags it too")
    }
}
