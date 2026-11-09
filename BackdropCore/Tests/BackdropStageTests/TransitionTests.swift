import BackdropCore
import QuartzCore
import Testing
@testable import BackdropStage

@Suite("Transitions")
@MainActor
struct TransitionTests {
    let renderer = TitleRenderer(random: SeededRandom(seed: 5), reduceMotion: { true })
    let runner: StageRunner
    let live = surface()
    let preview = surface(role: .preview)
    let fade = Transition(style: .fade, fadeMs: 500)
    let snap = Transition(style: .snap, fadeMs: 500)

    init() {
        runner = StageRunner(renderers: [.title: renderer])
        runner.attach(live)
        runner.attach(preview)
    }

    func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    @Test("The first cue fades straight up from black")
    func firstCue() {
        let a = titleCue("THE LOUVRE")
        runner.change(to: a, show: ShowSettings(), transition: fade, at: 10)
        #expect(runner.cue == a && runner.startedAt == 10)
        #expect(live.curtain == 1 && preview.curtain == 1, "every surface alike")
        _ = runner.tick(at: 10.25)
        #expect(close(live.curtain, 0.5) && close(preview.curtain, 0.5))
        _ = runner.tick(at: 10.5)
        #expect(live.curtain == 0 && !runner.isChanging)
    }

    @Test("Through black: down over the old cue, then up on the new one, whose clock starts in the dark")
    func throughBlack() {
        let a = titleCue("THE LOUVRE"), b = titleCue("ROSSLYN")
        runner.load(a, show: ShowSettings(), presentation: .settled, at: 0)
        runner.change(to: b, show: ShowSettings(), transition: fade, at: 10)
        #expect(runner.cue == a, "the old cue stays up while the curtain comes down")
        _ = runner.tick(at: 10.25)
        #expect(close(live.curtain, 0.5) && runner.cue == a)
        _ = runner.tick(at: 10.6)
        #expect(runner.cue == b && runner.startedAt == 10.5, "up from the moment it went black, not from the tick")
        #expect(close(live.curtain, 1 - TransitionTimingCheck.eased(0.2)))
        _ = runner.tick(at: 11)
        #expect(live.curtain == 0 && !runner.isChanging && runner.isRunning)
    }

    @Test("A GO during a fade out carries on down from where it got to")
    func goDuringFadeOut() {
        let a = titleCue("A"), b = titleCue("B"), c = titleCue("C")
        runner.load(a, show: ShowSettings(), presentation: .settled, at: 0)
        runner.change(to: b, show: ShowSettings(), transition: fade, at: 10)
        _ = runner.tick(at: 10.25)
        runner.change(to: c, show: ShowSettings(), transition: fade, at: 10.25)
        // Half the curtain left to fall, at the fade's own pace.
        _ = runner.tick(at: 10.5)
        #expect(runner.cue == c && runner.startedAt == 10.5 && live.curtain == 1, "B never comes up")
    }

    @Test("A GO during a fade in turns round and goes back down")
    func goDuringFadeIn() {
        let a = titleCue("A"), b = titleCue("B")
        runner.change(to: a, show: ShowSettings(), transition: fade, at: 10)
        _ = runner.tick(at: 10.25)
        runner.change(to: b, show: ShowSettings(), transition: fade, at: 10.25)
        _ = runner.tick(at: 10.3)
        #expect(runner.cue == a && live.curtain > 0.5, "going down again, not jumping")
        _ = runner.tick(at: 10.5)
        #expect(runner.cue == b && live.curtain == 1)
    }

    let cross = Transition(style: .crossfade, fadeMs: 500)

    @Test("A crossfade puts the new cue up at once, with the old one fading out over it")
    func crossfade() {
        let a = titleCue("A"), b = titleCue("B")
        runner.load(a, show: ShowSettings(), presentation: .settled, at: 0)
        runner.change(to: b, show: ShowSettings(), transition: cross, at: 10)
        #expect(runner.cue == b && runner.startedAt == 10, "no waiting for the curtain")
        #expect(live.curtain == 0 && preview.curtain == 0, "the stage never goes dark")
        #expect(live.dissolve == 1 && preview.dissolve == 1 && runner.isChanging)
        _ = runner.tick(at: 10.25)
        #expect(close(live.dissolve, 0.5) && close(preview.dissolve, 0.5) && live.curtain == 0)
        _ = runner.tick(at: 10.5)
        #expect(live.dissolve == 0 && !runner.isChanging)
    }

    @Test("The old picture is what the audience saw, not black")
    func crossfadeHoldsTheOldPicture() {
        let blank = BlankRenderer()
        let runner = StageRunner(renderers: [.title: renderer, .blank: blank])
        let s = surface()
        runner.attach(s)
        runner.load(titleCue("THE LOUVRE"), show: ShowSettings(), presentation: .settled, at: 0)
        func lit(_ b: Bitmap) -> Int {
            var n = 0
            for y in stride(from: 0, to: b.height, by: 4) { for x in stride(from: 0, to: b.width, by: 4) where !b.isBlack(x: x, y: y) { n += 1 } }
            return n
        }
        let before = lit(render(s))
        #expect(before > 0, "the title is on the surface")
        var black = Cue(content: .blank(BlankContent()))
        black.number = "2"
        runner.change(to: black, show: ShowSettings(), transition: cross, at: 10)
        #expect(lit(render(s)) >= before * 9 / 10, "the old title still shows, over the blank cue now running")
        _ = runner.tick(at: 10.5)
        #expect(lit(render(s)) == 0, "and gone once the dissolve ends")
    }

    @Test("The first cue has nothing to dissolve from, so it comes up out of black")
    func crossfadeFirstCue() {
        runner.change(to: titleCue("A"), show: ShowSettings(), transition: cross, at: 10)
        #expect(live.curtain == 1 && live.dissolve == 0)
    }

    @Test("A snap, a fade or a load cuts a crossfade short")
    func crossfadeCutShort() {
        let a = titleCue("A"), b = titleCue("B"), c = titleCue("C")
        runner.load(a, show: ShowSettings(), presentation: .settled, at: 0)
        runner.change(to: b, show: ShowSettings(), transition: cross, at: 10)
        runner.change(to: c, show: ShowSettings(), transition: snap, at: 10.1)
        #expect(runner.cue == c && live.dissolve == 0 && !runner.isChanging)
        runner.change(to: b, show: ShowSettings(), transition: cross, at: 11)
        runner.change(to: a, show: ShowSettings(), transition: fade, at: 11.1)
        _ = runner.tick(at: 11.7)
        #expect(runner.cue == a && live.dissolve == 0, "gone with the cue it was fading out of")
    }

    @Test("A snap is at once, and cuts short any fade")
    func snapCutsAFadeShort() {
        let a = titleCue("A"), b = titleCue("B"), c = titleCue("C")
        runner.load(a, show: ShowSettings(), presentation: .settled, at: 0)
        runner.change(to: b, show: ShowSettings(), transition: fade, at: 10)
        _ = runner.tick(at: 10.2)
        runner.change(to: c, show: ShowSettings(), transition: snap, at: 10.2)
        #expect(runner.cue == c && live.curtain == 0 && !runner.isChanging)
    }

    @Test("A cue on its way off never settles, so nothing continues from it")
    func outgoingCueDoesntSettle() {
        let a = titleCue("A"), b = titleCue("B")
        runner.load(a, show: ShowSettings(), presentation: .settled, at: 0)
        runner.change(to: b, show: ShowSettings(), transition: fade, at: 0)
        #expect(runner.tick(at: 0.1) == nil)
    }

    @Test("Fading keeps the host ticking until the curtain is up")
    func needsTicksWhileFading() {
        let a = titleCue("A"), b = titleCue("B")
        runner.load(a, show: ShowSettings(), presentation: .settled, at: 0)
        _ = runner.tick(at: 0.1)
        #expect(!runner.needsTicks)
        runner.change(to: b, show: ShowSettings(), transition: fade, at: 1)
        #expect(runner.needsTicks)
    }
}

/// The same easing the runner uses, written out, so a test reads the curve
/// rather than calling the code under test.
enum TransitionTimingCheck {
    static func eased(_ t: Double) -> Double { t * t * (3 - 2 * t) }
}

@Suite("Transitions in a show")
@MainActor
struct ShowTransitionTests {
    final class Clock {
        var time = 100.0
    }

    let clock = Clock()
    let renderer = TitleRenderer(random: SeededRandom(seed: 6), reduceMotion: { true })
    let stage = surface()

    func controller(_ cues: [Cue]) -> ShowController {
        let clock = self.clock
        let c = ShowController(show: Show(title: "Test", cues: cues), renderers: [.title: renderer], now: { clock.time })
        c.runner.attach(stage)
        return c
    }

    func runUntilIdle(_ c: ShowController) {
        repeat {
            clock.time += 1.0 / 60
            c.tick(at: clock.time)
        } while c.runner.needsTicks
    }

    @Test("A cue's own transition in applies however it is reached")
    func ownTransitionAppliesAfterAJump() {
        var snapped = titleCue("SNAPPED")
        snapped.number = "2"
        snapped.transition = Transition(style: .snap)
        var third = titleCue("THIRD")
        third.number = "3"
        let c = controller([titleCue("FIRST"), snapped, third])
        c.go()
        runUntilIdle(c)
        // Skip cue 2: cue 3 arrives by the standard fade.
        c.standBy(third.id)
        c.go()
        #expect(c.runner.isChanging && c.runner.cue?.number == "1")
        runUntilIdle(c)
        // Back to cue 2, out of order: its own snap.
        c.standBy(snapped.id)
        c.go()
        #expect(!c.runner.isChanging && c.runner.cue == snapped && stage.curtain == 0)
    }

    @Test("R runs the live cue again from its transition")
    func rerunFades() {
        let only = titleCue("THE LOUVRE")
        let c = controller([only])
        c.go()
        runUntilIdle(c)
        c.rerun()
        #expect(c.runner.isChanging && c.runner.cue == only)
        clock.time += 0.25
        c.tick(at: clock.time)
        #expect(stage.curtain > 0.4 && stage.curtain < 0.6)
        runUntilIdle(c)
        #expect(stage.curtain == 0 && c.runner.cue == only)
    }

    @Test("Resuming after a crash puts the cue up at once")
    func resumeIsInstant() {
        let only = titleCue("THE LOUVRE")
        let c = controller([only])
        c.resume(at: only.id)
        #expect(!c.runner.isChanging && stage.curtain == 0 && c.runner.cue == only)
    }
}
