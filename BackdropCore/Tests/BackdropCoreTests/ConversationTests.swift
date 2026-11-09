import Foundation
import Testing
@testable import BackdropCore

@Suite("Text conversation cues")
struct ConversationTests {
    static let script = """
    < Are you coming tonight?
    > Yes, leaving now
    < Great, bring wine
    a note, ignored
    GO when she picks up
    < Where are you?
    GO
    > Outside
    """

    func content(_ settings: ConversationSettings = .init(), script: String = ConversationTests.script) -> ConversationContent {
        ConversationContent(text: "Chat", sub: "Mum", script: script, settings: settings)
    }

    @Test("The script is read into stages, with GO lines between and notes ignored")
    func parsing() {
        let c = content()
        #expect(c.stages.count == 3)
        #expect(c.stages[0].messages.map(\.text) == ["Are you coming tonight?", "Yes, leaving now", "Great, bring wine"])
        #expect(c.stages[0].messages.map(\.side) == [.received, .sent, .received])
        #expect(c.stages[1].cuePoint == "when she picks up" && c.stages[1].messages.map(\.text) == ["Where are you?"])
        #expect(c.stages[2].cuePoint == "" && c.stages[2].messages == [ConversationMessage(side: .sent, text: "Outside")])
        #expect(c.hasSent && c.messages.count == 5)
        #expect(content(script: "").stages.count == 1, "always a first stage")
        #expect(content(script: "GOING home\n< hi").stages.count == 1, "only a line that is GO makes a stage")
        #expect(content(script: "go\n<   \n< hi").stages.map(\.messages.count) == [0, 1], "lowercase go, and an empty message is nothing")
    }

    @Test("Each GO after the first stage is a GO point, with the line it waits for")
    func goPoints() {
        #expect(content().goPoints() == [
            GoPoint(unit: .stage, text: "Where are you?", cuePoint: "when she picks up"),
            GoPoint(unit: .stage, text: "Outside"),
        ])
        #expect(content(script: "< hi").goPoints().isEmpty)
    }

    @Test("Messages arrive one after another, a pause between, and a stage waits for its GO")
    func timing() {
        let plan = ConversationCuePlan(content(ConversationSettings(showTyping: false, pauseTicks: 10), script: "< a\n> b\nGO\n< c"))
        // Each is the arrival alone, with ten frames between.
        #expect(plan.parts == [10 + 10 + 10, 10])
        var timeline = GoTimeline(parts: plan.parts)
        func shown(_ f: Double) -> [Int] { plan.state(at: f, timeline: timeline).items.map(\.index) }
        #expect(shown(0) == [0] && shown(19) == [0])
        #expect(shown(20) == [0, 1])
        #expect(shown(500) == [0, 1], "the third waits for GO")
        #expect(timeline.isWaiting(at: 30))
        timeline.carryOn(at: 100)
        #expect(shown(100) == [0, 1, 2])
        #expect(timeline.isFinished(at: 110))
    }

    @Test("A received message shows dots and then grows; a sent one is typed into the bar first")
    func typing() {
        let plan = ConversationCuePlan(content(ConversationSettings(showTyping: true, pauseTicks: 0), script: "< hello\n> hi back"))
        let timeline = GoTimeline(parts: plan.parts)
        let dots = plan.state(at: 5, timeline: timeline)
        #expect(dots.items.count == 1 && dots.items[0].phase == .typing(5) && dots.composing == nil)
        // Twenty frames plus a frame a letter for the dots, then ten to arrive.
        let lead = 20.0 + 5
        #expect(plan.state(at: lead + 5, timeline: timeline).items[0].phase == .arriving(0.5, fromDots: true))
        #expect(plan.state(at: lead + 10, timeline: timeline).items[0].phase == .settled)
        // The sent one starts when the first has settled, and is in the bar, not the thread.
        let start = lead + 10
        let typing = plan.state(at: start + 4, timeline: timeline)
        #expect(typing.items.count == 1 && typing.composing == "hi", "typed 4 of its 14 frames: \(typing.composing ?? "nil")")
        let sent = plan.state(at: start + 14 + 5, timeline: timeline)
        #expect(sent.items.count == 2 && sent.composing == nil && sent.items[1].phase == .arriving(0.5, fromDots: false))
    }

    @Test("Only the last of a run from one side takes the tail")
    func tails() {
        let plan = ConversationCuePlan(content(ConversationSettings(showTyping: false), script: "< a\n< b\n> c\n> d\n> e\n< f"))
        var timeline = GoTimeline(parts: plan.parts)
        timeline.carryOnToEnd()
        let items = plan.state(at: 100_000, timeline: timeline).items
        #expect(items.map(\.hasTail) == [false, true, false, false, true, true])
        #expect(items.map(\.joinsPrevious) == [false, true, false, true, true, false])
    }

    @Test("A conversation round trips through show.json, and raises the version beyond any other cue")
    func roundTrip() throws {
        let cue = Cue(number: "3", content: .conversation(content(ConversationSettings(style: .generic, dark: false, showTyping: false, pauseTicks: 30))))
        let show = Show(title: "T", cues: [cue])
        #expect(show.version == 11 && Show.formatVersion >= 11)
        let back = try JSONDecoder().decode(Show.self, from: try JSONEncoder().encode(show))
        #expect(back.cues == [cue])
        let bare = try JSONDecoder().decode(Cue.self, from: Data(#"{"kind":"conversation","settings":{"style":"x","pauseTicks":9999}}"#.utf8))
        guard case .conversation(let c) = bare.content else { Issue.record("not a conversation"); return }
        #expect(c.settings.style == .imessage && c.settings.pauseTicks == SettingRange.pauseTicks.upperBound)
    }

    @Test("Its label and contact are the cue's text and sub, it has GO points, and it is in the Add Cue menus")
    func labels() {
        var cue = Cue(content: .conversation(content()))
        #expect(cue.text == "Chat" && cue.sub == "Mum" && cue.goPoints().count == 2)
        cue.sub = "Dad"
        #expect(cue.sub == "Dad")
        #expect(Cue.Kind.conversation.heading == "Text Conversation")
        #expect(Cue.Kind.others.contains(.conversation) && cue.finishes)
    }
}
