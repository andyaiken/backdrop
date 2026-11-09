import Foundation
import Testing
@testable import BackdropCore

@Suite struct KeypadTests {
    @Test func stagesVerdictsAndBoxes() {
        let c = KeypadContent(script: "1332\n<<<<\n1123\nGOOD\n")
        #expect(c.stages.count == 4)
        #expect(c.stages[3].verdict == .good)
        #expect(c.boxCount == 4)
        #expect(c.goPoints().map(\.text) == ["\u{232B}\u{232B}\u{232B}\u{232B}", "1123", "GOOD"])
    }

    @Test func badAndMixedCase() {
        #expect(KeypadContent(script: "12 bad").stages[0].verdict == .bad)
        #expect(KeypadContent(script: "12 bad").stages[0].keys.count == 2)
    }

    @Test func emptyScriptHasFourBoxes() {
        #expect(KeypadContent().boxCount == 4)
    }

    @Test func starAndHashAreKeys() {
        #expect(KeypadContent(script: "4#*").stages[0].keys == [.digit("4"), .digit("#"), .digit("*")])
    }

    @Test func stateFollowsTimeline() {
        let c = KeypadContent(script: "1\n<12\nBAD", settings: .init(pauseTicks: 10))
        let plan = KeypadCuePlan(c)
        var t = GoTimeline(parts: plan.parts)
        #expect(plan.state(at: 0, timeline: t).entry == ["1"])
        #expect(plan.state(at: 0, timeline: t).pressed == .digit("1"))
        t.carryOn(at: 20)
        #expect(plan.state(at: 20, timeline: t).entry == [])
        t.carryOn(at: 60)
        // The BAD stage presses OK first, then the verdict comes up from 70.
        #expect(plan.state(at: 60, timeline: t).verdict == nil)
        #expect(plan.state(at: 60, timeline: t).pressed == .ok)
        let s = plan.state(at: 70, timeline: t)
        #expect(s.entry == ["1", "2"] && s.verdict == .bad && s.lit)
        #expect(plan.state(at: 110, timeline: t).lit)
    }

    @Test func codable() throws {
        let cue = Cue(content: .keypad(KeypadContent(text: "Safe", script: "4\n2\nGOOD")))
        let back = try JSONDecoder().decode(Cue.self, from: JSONEncoder().encode(cue))
        #expect(back == cue)
    }
}
