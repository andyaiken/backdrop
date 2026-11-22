import BackdropCore
import Foundation
import Testing
@testable import BackdropStage

/// Commands from other machines, end to end through the controller.
@Suite("Commands from other machines")
@MainActor
struct RemoteCommandTests {
    let renderer = TitleRenderer(random: SeededRandom(seed: 11), reduceMotion: { true })

    /// Cues 1, 2 and 3, in show mode, with cue 1 standing by.
    func controller(mode: ShowController.Mode = .show) -> ShowController {
        let cues = ["THE LOUVRE", "SAINT-SULPICE", "ROSSLYN CHAPEL"].enumerated().map { i, text in
            var cue = titleCue(text)
            cue.number = String(i + 1)
            return cue
        }
        let c = ShowController(show: Show(title: "Test", cues: cues), mode: mode, renderers: [.title: renderer], now: { 100 })
        c.runner.attach(surface())
        return c
    }

    func number(_ c: ShowController, _ id: UUID?) -> String? {
        id.flatMap { c.show[$0]?.number }
    }

    @Test("GO fires the cue standing by, and says who sent it")
    func go() {
        let c = controller()
        c.perform(.go(cue: nil), from: .osc("10.0.0.2"))
        #expect(number(c, c.playhead.live) == "1")
        #expect(number(c, c.playhead.standby) == "2")
        #expect(c.message == "Cue 1 fired by OSC from 10.0.0.2.")
    }

    @Test("GO for a cue by number fires that cue, not the one standing by")
    func goByNumber() {
        let c = controller()
        c.perform(.go(cue: "3"), from: .osc("QLab"))
        #expect(number(c, c.playhead.live) == "3")
        #expect(c.message == "Cue 3 fired by OSC from QLab.")
    }

    @Test("GO for a number not in the sheet fires nothing")
    func goForNoSuchCue() {
        let c = controller()
        c.perform(.go(cue: "12"), from: .osc("QLab"))
        #expect(c.playhead.live == nil)
        #expect(number(c, c.playhead.standby) == "1")
        #expect(c.message == "GO for cue 12 arrived by OSC from QLab, but no cue is numbered 12.")
    }

    @Test("GO past the end of the sheet says so")
    func endOfSheet() {
        let c = controller()
        c.perform(.go(cue: "3"), from: .osc("QLab"))
        c.perform(.go(cue: nil), from: .osc("QLab"))
        #expect(number(c, c.playhead.live) == "3")
        #expect(c.message == "GO arrived by OSC from QLab, but this is the end of the cue sheet.")
    }

    @Test("Standby moves the standby and fires nothing")
    func standBy() {
        let c = controller()
        c.perform(.standBy(cue: "2"), from: .osc("QLab"))
        #expect(c.playhead.live == nil)
        #expect(number(c, c.playhead.standby) == "2")
        #expect(c.message == "Cue 2 made next by OSC from QLab.")
        c.perform(.standBy(cue: "9"), from: .osc("QLab"))
        #expect(number(c, c.playhead.standby) == "2")
        #expect(c.message == "Asked by OSC from QLab to make cue 9 next, but no cue is numbered 9.")
    }

    @Test("Blackout on and off, whatever it was before")
    func blackout() {
        let c = controller()
        c.perform(.blackout(true), from: .msc("the lighting desk"))
        #expect(c.playhead.blackout)
        #expect(c.runner.blackout)
        c.perform(.blackout(true), from: .msc("the lighting desk"))
        #expect(c.playhead.blackout)
        c.perform(.blackout(false), from: .msc("the lighting desk"))
        #expect(!c.playhead.blackout)
        #expect(!c.runner.blackout)
        #expect(c.message == "Picture brought back by MIDI Show Control from the lighting desk.")
    }

    @Test("In edit mode, nothing from another machine does anything")
    func editMode() {
        let c = controller(mode: .edit)
        for command in [RemoteCommand.go(cue: nil), .go(cue: "2"), .standBy(cue: "3"), .blackout(true)] {
            c.perform(command, from: .osc("QLab"))
        }
        #expect(c.playhead.live == nil)
        #expect(!c.playhead.blackout)
        #expect(c.message == "Ignored blackout, which arrived by OSC from QLab: Backdrop only acts on cues from other machines in show mode.")
    }

    @Test("A message from show control says where it came from, until the console says something")
    func messageOrigin() {
        let c = controller()
        c.perform(.go(cue: nil), from: .osc("10.0.0.12"))
        #expect(c.messageOrigin == .osc("10.0.0.12"))
        #expect(c.messageOrigin?.badge == "OSC")
        c.go()
        #expect(c.messageOrigin == nil)
        c.perform(.blackout(true), from: .shortcut)
        #expect(c.messageOrigin?.badge == "SHORTCUT")
        #expect(c.message == "Blacked out by a shortcut. Press B to bring the picture back.")
    }
}
