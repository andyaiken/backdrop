import Foundation
import Testing
@testable import ProspectCore

@Suite("GO cue points")
struct GoCuePointTests {
    let anagrams = [
        Anagram(text: "O, Draconian devil!", working: ["Dracula? No."], answer: "Leonardo da Vinci!"),
        Anagram(text: "Oh, lame saint!", answer: "The Mona Lisa!"),
    ]

    /// The cue waiting for GO in the way given.
    func advancing(_ advance: AnagramAdvance, _ cue: Cue) -> Cue {
        var cue = cue
        SettingKey.advance.set(.advance(advance), in: &cue)
        return cue
    }

    @Test("An anagram GO's cue point stays with the step it moves to, whichever way the cue waits")
    func anagram() {
        var cue = advancing(.eachStep, Cue(number: "4.8", content: .anagram(AnagramContent(anagrams: anagrams))))
        cue.setCuePoint("SOPHIE: \u{201C}It\u{2019}s an anagram.\u{201D}", ofGoPoint: 0)
        cue.setCuePoint("  LANGDON turns.  ", ofGoPoint: 2)
        #expect(cue.goPoints().map(\.cuePoint)
                == ["SOPHIE: \u{201C}It\u{2019}s an anagram.\u{201D}", "", "LANGDON turns."])
        #expect(advancing(.eachAnagram, cue).goPoints().map(\.cuePoint) == ["SOPHIE: \u{201C}It\u{2019}s an anagram.\u{201D}", "LANGDON turns."],
                "each anagram waits before its first move: the same moments")
        #expect(advancing(.byItself, cue).goPoints().isEmpty)
        cue = advancing(.eachAnagram, cue)
        cue.setCuePoint("", ofGoPoint: 1)
        #expect(advancing(.eachStep, cue).goPoints().map(\.cuePoint).last == "", "empty clears it")
    }

    @Test("Retyping the anagrams keeps each cue point whose step is still there")
    func carried() {
        var old = anagrams
        old[0].cuePoints = ["Dracula? No.": "A", "Leonardo da Vinci!": "B"]
        let new = Anagram.anagrams(fromParagraphs: "Oh, lame saint!\nThe Mona Lisa!\n\nO, Draconian devil!\nLeonardo da Vinci!")
        let carried = Anagram.carryingCuePoints(from: old, into: new)
        #expect(carried[0].cuePoints.isEmpty)
        #expect(carried[1].cuePoints == ["Leonardo da Vinci!": "B"], "moved to second place, its working gone")
    }

    @Test("A morph stage's and a map stop's GOs have cue points too")
    func morphAndMap() {
        var morph = advancing(.eachStep, Cue(content: .morph(MorphContent(text: "", pictures: [MorphPicture(src: "a.png"), MorphPicture(src: "b.png"), MorphPicture(src: "c.png")]))))
        morph.setCuePoint("Lights shift", ofGoPoint: 1)
        #expect(morph.goPoints().map(\.cuePoint) == ["", "Lights shift"])
        guard case .morph(let m) = morph.content else { return }
        #expect(m.pictures[2].cuePoint == "Lights shift" && !m.isPlain)

        let route = [RoutePoint(at: PicturePoint(x: 0, y: 0)), RoutePoint(at: PicturePoint(x: 0.5, y: 0)),
                     RoutePoint(at: PicturePoint(x: 1, y: 0), stop: MapStop(place: "BOW"))]
        var map = advancing(.eachStep, Cue(content: .map(MapContent(route: route))))
        map.setCuePoint("Phone rings", ofGoPoint: 0)
        #expect(map.goPoints().map(\.cuePoint) == ["Phone rings"])
        var byItself = advancing(.byItself, Cue(content: .map(MapContent(route: route))))
        let before = byItself
        byItself.setCuePoint("ignored", ofGoPoint: 0)
        #expect(byItself.goPoints().isEmpty && byItself == before, "no GO by itself, nothing to set")
    }

    @Test("show.json keeps them, as version 6; a show without any stays as it was")
    func json() throws {
        var cue = advancing(.eachAnagram, Cue(number: "4.8", content: .anagram(AnagramContent(anagrams: [Anagram(text: "Oh, lame saint!", answer: "The Mona Lisa!")]))))
        let plain = Show(cues: [cue])
        #expect(plain.version == 2)
        cue.setCuePoint("SOPHIE looks up", ofGoPoint: 0)
        let data = try JSONEncoder().encode(cue)
        #expect(String(data: data, encoding: .utf8)?.contains("\"cuePoints\"") == true)
        #expect(try JSONDecoder().decode(Cue.self, from: data) == cue)
        #expect(Show(cues: [cue]).version == 6)
    }

    @Test("The DSM sheet prints each GO's cue point on its row")
    func sheet() {
        var cue = Cue(number: "4.8", content: .anagram(AnagramContent(anagrams: anagrams, settings: AnagramSettings(advance: .eachAnagram))))
        cue.setCuePoint("LANGDON turns.", ofGoPoint: 1)
        let rows = CueSheet(show: Show(title: "T", cues: [cue]), title: "T", layout: .dsm).rows
        #expect(rows.map(\.cuePoint) == ["", "", "LANGDON turns."])
    }
}
