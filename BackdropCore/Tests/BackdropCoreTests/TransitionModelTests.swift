import Foundation
import Testing
@testable import BackdropCore

@Suite("Transitions in the model")
struct TransitionModelTests {
    @Test("A new cue fades through black for half a second")
    func defaults() {
        let cue = Cue(content: .blank(BlankContent()))
        #expect(cue.transition == Transition(style: .fade, fadeMs: 500))
    }

    @Test("A cue can change the style, the fade time, or both")
    func changes() {
        var cue = Cue(content: .blank(BlankContent()))
        cue.transition.fadeMs = 1200
        #expect(cue.transition == Transition(style: .fade, fadeMs: 1200))
        cue.transition.style = .snap
        #expect(cue.transition == Transition(style: .snap, fadeMs: 1200))
    }

    @Test("show.json keeps a cue's transition")
    func coding() throws {
        var cue = Cue(number: "1", content: .title(TitleContent(text: "THE LOUVRE", key: "KEY")))
        cue.transition = Transition(style: .snap, fadeMs: 9000)
        let back = try JSONDecoder().decode(Cue.self, from: try JSONEncoder().encode(cue))
        #expect(back.transition == Transition(style: .snap, fadeMs: SettingRange.fadeMs.upperBound), "clamped on the way in")
    }

    @Test("A cue with no transition in its file opens with the standard one")
    func olderShows() throws {
        let cue = try JSONDecoder().decode(Cue.self, from: Data(#"{ "kind": "blank", "num": "1" }"#.utf8))
        #expect(cue.transition == .standard)
    }

    @Test("Transition and fade read and choose like the other settings")
    func settingKeys() {
        #expect(SettingKey.fade.format(.number(500)) == "0.5 s")
        #expect(SettingKey.fade.format(.number(1200)) == "1.2 s")
        #expect(SettingKey.transition.format(.style(.snap)) == "snap")
        #expect(SettingKey.transition.format(.style(.fade)) == "fade through black")
        #expect(SettingKey.transition.choice(at: 1) == .style(.snap))
        #expect(SettingKey.transition.choiceIndex(of: .style(.fade)) == 0)
        #expect(SettingKey.order.choiceIndex(of: .order(.random)) == 1)
        var cue = Cue(content: .video(VideoContent()))
        SettingKey.transition.set(.style(.snap), in: &cue)
        SettingKey.fade.set(.number(730), in: &cue)
        #expect(cue.transition == Transition(style: .snap, fadeMs: 700), "fade time snaps to its step")
        #expect(SettingKey.fade.value(in: cue) == .number(700))
    }

    @Test("A crossfade is a style like the others: chosen, stored, formatted, and with a length")
    func crossfade() throws {
        #expect(SettingKey.transition.format(.style(.crossfade)) == "crossfade")
        #expect(SettingKey.transition.choice(at: 2) == .style(.crossfade))
        #expect(SettingKey.transition.choiceIndex(of: .style(.crossfade)) == 2)
        #expect(Transition(style: .crossfade, fadeMs: 500).hasLength && Transition(style: .fade, fadeMs: 500).hasLength)
        #expect(!Transition(style: .snap, fadeMs: 500).hasLength)
        var cue = Cue(content: .blank(BlankContent()))
        cue.transition.style = .crossfade
        let json = String(decoding: try JSONEncoder().encode(cue), as: UTF8.self)
        #expect(json.contains("crossfade"))
        #expect(try JSONDecoder().decode(Cue.self, from: Data(json.utf8)).transition.style == .crossfade)
    }
}

@Suite("Wipes")
struct WipeTests {
    @Test("A wipe remembers where it starts from, and older files start from the left")
    func coding() throws {
        var cue = Cue(content: .blank(BlankContent()))
        cue.transition = Transition(style: .wipe, fadeMs: 800, wipeFrom: .bottomRight)
        let back = try JSONDecoder().decode(Cue.self, from: try JSONEncoder().encode(cue))
        #expect(back.transition.style == .wipe && back.transition.wipeFrom == .bottomRight)
        let old = try JSONDecoder().decode(Cue.self, from: Data(#"{ "kind": "blank", "num": "1" }"#.utf8))
        #expect(old.transition.wipeFrom == .left)
    }

    @Test("What a wipe has yet to reach shrinks away from its side or corner")
    func remaining() {
        func area(_ p: [CGPoint]) -> Double {
            var a = 0.0
            for i in p.indices { let q = p[(i + 1) % p.count]; a += p[i].x * q.y - q.x * p[i].y }
            return abs(a) / 2
        }
        for edge in WipeEdge.allCases {
            #expect(abs(area(edge.remaining(after: 0)) - 1) < 1e-9)
            #expect(edge.remaining(after: 1).isEmpty)
            #expect(area(edge.remaining(after: 0.75)) < area(edge.remaining(after: 0.25)))
        }
        // From the left, the right half is left at the halfway mark.
        #expect(abs(area(WipeEdge.left.remaining(after: 0.5)) - 0.5) < 1e-9)
        #expect(WipeEdge.left.remaining(after: 0.5).allSatisfy { $0.x >= 0.5 - 1e-9 })
        // From the top left, the bottom right corner is the last to go.
        #expect(WipeEdge.topLeft.remaining(after: 0.9).contains { abs($0.x - 1) < 0.3 && abs($0.y - 1) < 0.3 })
    }

    @Test("The edge reads and sets like the other settings")
    func settingKey() {
        var cue = Cue(content: .blank(BlankContent()))
        SettingKey.wipeFrom.set(.edge(.topRight), in: &cue)
        #expect(cue.transition.wipeFrom == .topRight)
        #expect(SettingKey.wipeFrom.format(.edge(.topRight)) == "top right")
        #expect(SettingKey.wipeFrom.choices().count == 8)
    }
}
