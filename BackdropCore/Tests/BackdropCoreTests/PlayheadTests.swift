import Testing
@testable import BackdropCore

private func show(_ cues: [Cue]) -> Show { Show(cues: cues) }

private func cue(_ number: String, continues: ContinueMode = .whenCued) -> Cue {
    Cue(number: number, continueMode: continues, content: .title(TitleContent(text: "CUE \(number)")))
}

@Suite("Playhead: only GO fires")
struct PlayheadTests {
    let sheet = show(["1", "2", "3", "9.5", "12"].map { cue($0) })

    @Test func opensWithNothingLiveAndTheFirstCueStandingBy() {
        let playhead = Playhead(show: sheet)
        #expect(playhead.live == nil)
        #expect(playhead.standby == sheet.cues[0].id)
        #expect(Playhead(show: Show()).standby == nil, "an empty sheet has nothing to stand by")
    }

    @Test func goFiresTheStandbyCueAndStandsByTheNext() {
        var playhead = Playhead(show: sheet)
        let fire = playhead.go(in: sheet)
        #expect(fire == Playhead.Fire(cue: sheet.cues[0].id, presentation: .run, automatic: false))
        #expect(playhead.live == sheet.cues[0].id)
        #expect(playhead.standby == sheet.cues[1].id)
    }

    @Test func goAtTheEndOfTheSheetDoesNothing() {
        var playhead = Playhead(show: sheet)
        for _ in sheet.cues { _ = playhead.go(in: sheet) }
        #expect(playhead.standby == nil)
        #expect(playhead.go(in: sheet) == nil)
        #expect(playhead.live == sheet.cues.last?.id)
    }

    @Test func arrowsMoveOnlyTheStandbyCue() {
        var playhead = Playhead(show: sheet)
        _ = playhead.go(in: sheet)
        let live = playhead.live

        playhead.standByNext(in: sheet)
        playhead.standByNext(in: sheet)
        #expect(playhead.standby == sheet.cues[3].id)
        playhead.standByPrevious(in: sheet)
        #expect(playhead.standby == sheet.cues[2].id)
        #expect(playhead.live == live)

        for _ in 0..<10 { playhead.standByNext(in: sheet) }
        #expect(playhead.standby == nil, "past the last cue is the end of the sheet")
        playhead.standByPrevious(in: sheet)
        #expect(playhead.standby == sheet.cues.last?.id)
        for _ in 0..<10 { playhead.standByPrevious(in: sheet) }
        #expect(playhead.standby == sheet.cues.first?.id)
        #expect(playhead.live == live)
    }

    @Test func listClicksAndGoToStandBy() {
        let numbered = show(["1", "2", "3", "9.5", "12", "P12", "7", "7"].map { cue($0) })
        var playhead = Playhead(show: numbered)
        playhead.standBy(numbered.cues[2].id)
        #expect(playhead.standby == numbered.cues[2].id)
        #expect(playhead.standBy(number: "12", in: numbered) && playhead.standby == numbered.cues[4].id, "digits")
        #expect(playhead.standBy(number: "9.5", in: numbered) && playhead.standby == numbered.cues[3].id, "a decimal")
        #expect(playhead.standBy(number: "P12", in: numbered) && playhead.standby == numbered.cues[5].id, "a letter and digits")
        #expect(playhead.standBy(number: " 9.5 ", in: numbered) && playhead.standby == numbered.cues[3].id, "surrounding spaces")
        let missing = playhead.standBy(number: "P99", in: numbered)
        #expect(!missing && playhead.standby == numbered.cues[3].id, "a miss leaves the standby cue alone")
        #expect(playhead.standBy(number: "7", in: numbered) && playhead.standby == numbered.cues[6].id,
                "a number used twice reaches the first cue with it")
        #expect(playhead.live == nil, "nothing fires")
    }

    @Test func rerunReplaysTheLiveCue() {
        var playhead = Playhead(show: sheet)
        #expect(playhead.rerun(in: sheet) == nil)
        _ = playhead.go(in: sheet)
        let standby = playhead.standby
        #expect(playhead.rerun(in: sheet) == Playhead.Fire(cue: sheet.cues[0].id, presentation: .run, automatic: false))
        #expect(playhead.standby == standby)
    }

    @Test func blackoutSurvivesGo() {
        var playhead = Playhead(show: sheet)
        playhead.blackout = true
        _ = playhead.go(in: sheet)
        #expect(playhead.blackout)
    }
}

@Suite("Playhead: continuing")
struct ContinueTests {
    let sheet = show([cue("1", continues: .whenFinished), cue("2", continues: .whenFinished), cue("3"), cue("4")])

    @Test func theNextCueFiresWhenOneThatContinuesWhenFinishedSettles() {
        var playhead = Playhead(show: sheet)
        _ = playhead.go(in: sheet)
        let fire = playhead.liveCueSettled(sheet.cues[0].id, in: sheet)
        #expect(fire == Playhead.Fire(cue: sheet.cues[1].id, presentation: .run, automatic: true))
        #expect(playhead.live == sheet.cues[1].id)

        // A chain carries on.
        #expect(playhead.liveCueSettled(sheet.cues[1].id, in: sheet)?.cue == sheet.cues[2].id)
        #expect(playhead.liveCueSettled(sheet.cues[2].id, in: sheet) == nil, "cue 4 waits for GO")
        #expect(playhead.standby == sheet.cues[3].id)
    }

    @Test func aStaleSettleIsIgnored() {
        var playhead = Playhead(show: sheet)
        _ = playhead.go(in: sheet)
        playhead.standBy(sheet.cues[3].id)
        _ = playhead.go(in: sheet)
        #expect(playhead.liveCueSettled(sheet.cues[0].id, in: sheet) == nil)
        #expect(playhead.live == sheet.cues[3].id)
    }

    @Test func continuingTakesTheSheetOrderOverAMovedStandby() {
        var playhead = Playhead(show: sheet)
        _ = playhead.go(in: sheet)
        playhead.standBy(sheet.cues[3].id)
        #expect(playhead.liveCueSettled(sheet.cues[0].id, in: sheet)?.cue == sheet.cues[1].id)
        #expect(playhead.standby == sheet.cues[2].id)
    }

    @Test func armingCoversTheStandbyCueAndAnyContinue() {
        var playhead = Playhead(show: sheet)
        #expect(playhead.cuesThatMayFireNext(in: sheet) == [sheet.cues[0].id])
        _ = playhead.go(in: sheet)
        #expect(playhead.cuesThatMayFireNext(in: sheet) == [sheet.cues[1].id])
        playhead.standBy(sheet.cues[3].id)
        #expect(playhead.cuesThatMayFireNext(in: sheet) == [sheet.cues[1].id, sheet.cues[3].id])
    }

    @Test("A timed continue fires the next cue when its time comes, not when its cue settles")
    func timedContinue() {
        let timed = show([cue("1", continues: .after(ms: 5000)), cue("2"), cue("3")])
        var playhead = Playhead(show: timed)
        _ = playhead.go(in: timed)
        #expect(playhead.liveCueSettled(timed.cues[0].id, in: timed) == nil, "settling isn't the signal")
        #expect(playhead.continueAfter(timed.cues[0].id, in: timed)
                == Playhead.Fire(cue: timed.cues[1].id, presentation: .run, automatic: true))
        #expect(playhead.continueAfter(timed.cues[0].id, in: timed) == nil, "once it has moved on, a late timer is ignored")
        #expect(playhead.continueAfter(timed.cues[2].id, in: timed) == nil)
    }

    @Test("A wait after finishing isn't the playhead's to time: settling alone fires nothing")
    func waitAfterFinishing() {
        let waiting = show([cue("1", continues: .whenFinished(waitMs: 2000)), cue("2")])
        var playhead = Playhead(show: waiting)
        _ = playhead.go(in: waiting)
        #expect(playhead.liveCueSettled(waiting.cues[0].id, in: waiting) == nil)
        #expect(playhead.continueAfter(waiting.cues[0].id, in: waiting)?.cue == waiting.cues[1].id)
    }
}

@Suite("Playhead: resume and edits")
struct PlayheadEditTests {
    let sheet = show(["1", "2", "3", "4"].map { cue($0) })

    @Test func resumePutsTheCueUpSettledAndStandsByTheNext() {
        var playhead = Playhead(show: sheet)
        let fire = playhead.resume(at: sheet.cues[2].id, in: sheet)
        #expect(fire == Playhead.Fire(cue: sheet.cues[2].id, presentation: .settled, automatic: false))
        #expect(playhead.live == sheet.cues[2].id)
        #expect(playhead.standby == sheet.cues[3].id)
    }

    @Test func deletingTheStandbyCueStandsByWhatTakesItsPlace() {
        var playhead = Playhead(show: sheet)
        playhead.standBy(sheet.cues[1].id)
        var edited = sheet
        edited.cues.remove(at: 1)
        playhead.reconcile(from: sheet, to: edited)
        #expect(playhead.standby == sheet.cues[2].id)

        var emptied = edited
        emptied.cues.removeLast(2)
        playhead.reconcile(from: edited, to: emptied)
        #expect(playhead.standby == nil)
    }

    @Test func editsElsewhereLeaveTheStandbyAlone() {
        var playhead = Playhead(show: sheet)
        playhead.standBy(sheet.cues[2].id)
        var edited = sheet
        edited.cues.remove(at: 0)
        edited.cues.insert(cue("0.5"), at: 0)
        playhead.reconcile(from: sheet, to: edited)
        #expect(playhead.standby == sheet.cues[2].id)
    }
}
