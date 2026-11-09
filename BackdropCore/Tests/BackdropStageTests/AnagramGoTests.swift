import BackdropCore
import Testing
@testable import BackdropStage

/// An anagram cue that waits for GO partway, end to end: playhead, runner,
/// renderer and the clock.
@Suite("Anagram cues on GO")
@MainActor
struct AnagramGoTests {
    final class Clock {
        var time = 100.0
    }

    let clock = Clock()
    let anagrams = AnagramRenderer(random: SeededRandom(seed: 5))
    let titles = TitleRenderer(random: SeededRandom(seed: 11), reduceMotion: { true })
    let stage = surface()

    func controller(_ cues: [Cue]) -> ShowController {
        let cues = cues.map { cue in
            var cue = cue
            SettingKey.hold.set(.number(2), in: &cue)
            SettingKey.transition.set(.style(.snap), in: &cue)
            return cue
        }
        let clock = self.clock
        let c = ShowController(show: Show(title: "Test", cues: cues),
                               renderers: [.anagram: anagrams, .title: titles], now: { clock.time })
        c.runner.attach(stage)
        return c
    }

    /// Ticks at 60 Hz until nothing needs ticking, or `limit` seconds pass.
    /// Returns whether the clock came to rest.
    @discardableResult
    func runUntilIdle(_ c: ShowController, limit: Double = 30) -> Bool {
        let end = clock.time + limit
        var ticking = true
        c.needsTicks = { ticking = $0 }
        repeat {
            clock.time += 1.0 / 60
            c.tick(at: clock.time)
        } while ticking && clock.time < end
        return !ticking
    }

    func stepped(_ number: String, continues: ContinueMode = .whenCued) -> Cue {
        Cue(number: number, continueMode: continues, content: .anagram(AnagramContent(
            anagrams: [Anagram(text: "RATS", working: ["TSAR"], answer: "STAR")],
            settings: AnagramSettings(advance: .eachStep))))
    }

    @Test("Space carries a waiting cue on, step by step, and fires the next cue only after its last")
    func spaceCarriesOn() {
        let c = controller([stepped("1"), titleCue("NEXT")])
        let anagram = c.show.cues[0].id, next = c.show.cues[1].id
        c.go()
        #expect(runUntilIdle(c), "waiting for GO, the clock rests")
        #expect(c.standingByGoPoint == ShowController.StandingByGoPoint(cue: c.show.cues[0], point: GoPoint(unit: .step, text: "TSAR"),
                                                                        number: 1, count: 2))
        #expect(c.standingByCue?.id == anagram && c.playhead.standby == anagram && c.playhead.standbyStep == 0)
        #expect(anagrams.moveShown(0) == nil, "nothing has moved")

        c.go()
        #expect(c.playhead.live == anagram, "the same cue, carried on")
        #expect(runUntilIdle(c))
        #expect(anagrams.moveShown(0) == 0 && c.standingByGoPoint?.number == 2)

        c.go()
        #expect(runUntilIdle(c))
        #expect(anagrams.moveShown(0) == 1 && c.standingByGoPoint == nil)
        #expect(c.standingByCue?.id == next)
        c.go()
        #expect(c.playhead.live == next)
    }

    @Test("→ steps through the cue's GOs, then on to the next cue, which GO fires")
    func arrowsThroughSteps() {
        let c = controller([stepped("1"), titleCue("NEXT")])
        c.go()
        runUntilIdle(c)
        c.standByNext()
        #expect(c.standingByGoPoint?.number == 2)
        c.standByNext()
        #expect(c.standingByGoPoint == nil && c.playhead.standby == c.show.cues[1].id)
        c.go()
        #expect(c.playhead.live == c.show.cues[1].id)
    }

    @Test("GO on a later step jumps straight there; on a step done, it goes back and runs it again")
    func jumpsForwardAndBack() throws {
        let c = controller([stepped("1"), titleCue("NEXT")])
        let anagram = c.show.cues[0].id
        c.go()
        runUntilIdle(c)
        c.standBy(anagram, step: 1)
        c.go()
        #expect(anagrams.moveShown(0) == 1, "straight to the second move, the first already landed")
        #expect(runUntilIdle(c))
        #expect(c.standingByCue?.id == c.show.cues[1].id)

        c.standBy(anagram, step: 0)
        c.go()
        #expect(anagrams.moveShown(0) == 0, "back to the first move, from the phrase")
        let layers = try #require(anagrams.tree(for: stage)?.tracks.first?.pieces)
        #expect(layers.allSatisfy { $0.animationKeys() == nil }, "placed at once, nothing animating into place")
        #expect(runUntilIdle(c))
        #expect(anagrams.moveShown(0) == 0 && c.standingByGoPoint?.number == 2, "then waiting for the next GO as usual")
    }

    @Test("A step of another cue fires that cue there, after its transition, the steps before already done")
    func fireAtStep() {
        var cue = stepped("2")
        cue.transition = Transition(style: .fade, fadeMs: 200)
        let c = controller([titleCue("FIRST"), cue, titleCue("NEXT")])
        c.go()
        runUntilIdle(c)
        c.standBy(cue.id, step: 1)
        c.go()
        #expect(c.playhead.live == cue.id)
        #expect(runUntilIdle(c))
        #expect(anagrams.moveShown(0) == 1, "the second move ran, the first was already done")
        #expect(c.standingByCue?.id == c.show.cues[2].id)
    }

    @Test("A cue set to continue when finished continues only once its last GO has run")
    func continuesWhenFinished() {
        let c = controller([stepped("1", continues: .whenFinished), titleCue("NEXT")])
        c.go()
        runUntilIdle(c)
        #expect(c.playhead.live == c.show.cues[0].id, "waiting isn't finishing")
        c.go()
        runUntilIdle(c)
        #expect(c.playhead.live == c.show.cues[0].id)
        c.go()
        runUntilIdle(c)
        #expect(c.playhead.live == c.show.cues[1].id, "on by itself once the answer lands")
    }

    @Test("Edited on stage, the cue shows finished and waits for no more GOs; R brings them back")
    func editAndRerun() {
        let c = controller([stepped("1"), titleCue("NEXT")])
        c.enterEditMode()
        c.go()
        runUntilIdle(c)
        c.updateCue(c.show.cues[0].id, "Change Number") { $0.number = "1.1" }
        #expect(c.standingByGoPoint == nil && anagrams.moveShown(0) == 1)
        // In show mode R runs the live cue again; in edit mode it runs the selected one.
        c.enterShowMode()
        c.rerun()
        #expect(c.standingByGoPoint?.number == 1)
    }

    @Test("In edit mode R runs the one selected cue, which stays selected")
    func editRerunSingle() {
        let c = controller([stepped("1")])
        c.enterEditMode()
        c.rerun()
        #expect(c.playhead.live == c.show.cues[0].id)
        #expect(c.playhead.standby == c.show.cues[0].id)
        #expect(c.runner.cue?.id == c.show.cues[0].id)
        #expect(anagrams.moveShown(0) != nil || c.runner.needsTicks)
    }
}

extension AnagramRenderer {
    /// The move anagram `t` shows at the frame last painted: nil before its
    /// first sets off.
    func moveShown(_ t: Int) -> Int? {
        guard let f = lastFrame, let shown = shown(t, at: f), shown.start.map({ $0 <= f }) == true else { return nil }
        return shown.move
    }
}
