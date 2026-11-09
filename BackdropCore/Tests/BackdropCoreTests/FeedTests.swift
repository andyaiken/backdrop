import Foundation
import Testing
@testable import BackdropCore

@Suite("Live feed cues")
struct FeedTests {
    func feed(_ settings: FeedSettings = .init(device: "cam-1", deviceName: "Stage camera")) -> Cue {
        Cue(number: "9", content: .feed(FeedContent(text: "ACTOR", sub: "Handheld", settings: settings)))
    }

    @Test("A live feed round trips through show.json, and raises the version beyond any other cue")
    func roundTrip() throws {
        let cue = feed(FeedSettings(device: "cam-1", deviceName: "Stage camera", mirror: true,
                                    rotation: .quarter, fit: .fill, onLoss: .hold))
        let show = Show(title: "T", cues: [cue])
        #expect(show.version == 9 && Show.formatVersion >= 9)
        let back = try JSONDecoder().decode(Show.self, from: try JSONEncoder().encode(show))
        #expect(back.cues == [cue])
        #expect(Show(title: "T", cues: [Cue(content: .keypad(KeypadContent()))]).version == 8)
    }

    @Test("show.json reads by hand, and a missing or unknown setting is the default")
    func lenient() throws {
        let json = #"{"kind":"feed","num":"4","text":"X","settings":{"device":"a","rotation":45,"fit":"stretch"}}"#
        let cue = try JSONDecoder().decode(Cue.self, from: Data(json.utf8))
        guard case .feed(let f) = cue.content else { Issue.record("not a feed"); return }
        #expect(f.text == "X" && f.settings.device == "a" && f.settings.deviceName == "")
        #expect(f.settings.rotation == .none && f.settings.fit == .fit && f.settings.onLoss == .black && !f.settings.mirror)
        let bare = try JSONDecoder().decode(Cue.self, from: Data(#"{"kind":"feed"}"#.utf8))
        #expect(bare.content == .feed(FeedContent()))
    }

    @Test("A feed with no camera is a sheet problem; one that never finishes can't continue when finished")
    func issues() {
        var cue = feed(FeedSettings())
        var show = Show(cues: [cue, Cue(number: "10", content: .blank(BlankContent()))])
        #expect(show.issues == [.feedWithoutDevice(cue: cue.id)])
        #expect(show.message(for: show.issues[0]) == "Cue 9 has no camera chosen, and will go to black.")

        cue = feed()
        cue.continueMode = .whenFinished
        show = Show(cues: [cue, Cue(number: "10", content: .blank(BlankContent()))])
        #expect(show.issues == [.neverFinishes(cue: cue.id)])
        #expect(!cue.finishes)
    }

    @Test("Its label and caption are the cue's text and sub, and it is in the Add Cue menus")
    func labels() {
        var cue = feed()
        #expect(cue.text == "ACTOR" && cue.sub == "Handheld")
        cue.text = "NEW"
        cue.sub = "Wide"
        #expect(cue.content == .feed(FeedContent(text: "NEW", sub: "Wide", settings: FeedSettings(device: "cam-1", deviceName: "Stage camera"))))
        #expect(Cue.Kind.feed.heading == "Live Feed")
        #expect(Cue.Kind.common.contains(.feed) || Cue.Kind.others.contains(.feed))
    }
}
