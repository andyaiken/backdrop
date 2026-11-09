import Testing
@testable import BackdropCore

@Suite("GO timeline")
struct GoTimelineTests {
    @Test("GO starts the next part then, or once the part before has finished, so nothing jumps")
    func timeline() {
        var t = GoTimeline(parts: [0, 76, 39])
        #expect(!t.isWaiting(at: -5) && t.isWaiting(at: 0), "waiting once the hold is over")
        t.carryOn(at: 10)
        #expect(!t.isWaiting(at: 50) && t.isWaiting(at: 86))
        t.carryOn(at: 60)
        #expect(t.starts == [0, 10, 86], "a GO before the first part has finished waits for it")
        #expect(!t.isFinished(at: 124) && t.isFinished(at: 125) && !t.isWaiting(at: 125))

        var early = GoTimeline(parts: [0, 33])
        early.carryOn(at: -20)
        #expect(early.starts == [0, 0], "a GO during the hold goes as the hold ends")
        var settled = GoTimeline(parts: [0, 76, 39])
        settled.carryOnToEnd()
        #expect(settled.starts == [0, 0, 76] && settled.isFinished(at: 115))
    }

    @Test("Something partway into a part starts once its part has been let go")
    func start() {
        var t = GoTimeline(parts: [0, 76, 39])
        #expect(t.start(part: 0, offset: 0) == 0)
        #expect(t.start(part: 1, offset: 43) == nil, "its part still waits for GO")
        t.carryOn(at: 10)
        #expect(t.start(part: 1, offset: 43) == 53)
    }

    @Test("A jump times every part before as over by now, and starts its part now, or when the hold ends")
    func jump() {
        var t = GoTimeline(parts: [0, 33, 33, 39])
        t.jump(toPart: 2, at: 50)
        #expect(t.starts == [17, 17, 50], "parts 0 and 1 ran back to back, ending now")
        #expect(!t.isWaiting(at: 82) && t.isWaiting(at: 83))
        t.jump(toPart: 1, at: 120)
        #expect(t.starts == [120, 120], "back to part 1, part 2 waiting again")
        #expect(t.start(part: 2, offset: 0) == nil)
        var early = GoTimeline(parts: [0, 33, 33])
        early.jump(toPart: 2, at: -10)
        #expect(early.starts == [-43, -43, 0], "during the hold: the parts before already over, this one as the hold ends")
        var same = GoTimeline(parts: [0, 33])
        same.jump(toPart: 0, at: 5)
        same.jump(toPart: 9, at: 5)
        #expect(same.starts == [0], "part 0, or one the cue doesn't have, changes nothing")
    }
}
