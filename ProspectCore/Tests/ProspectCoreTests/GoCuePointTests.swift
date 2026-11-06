import Foundation
import Testing
@testable import ProspectCore

@Suite("GO cue points")
struct GoCuePointTests {
    let anagrams = [
        Anagram(text: "O, Draconian devil!", working: ["Dracula? No."], answer: "Leonardo da Vinci!"),
        Anagram(text: "Oh, lame saint!", answer: "The Mona Lisa!"),
    ]

    func defaults(_ advance: AnagramAdvance) -> ShowSettings {
        var s = ShowSettings()
        s.advance = advance
        return s
    }

    @Test("An anagram GO's cue point stays with the step it moves to, whichever way the cue waits")
    func anagram() {
        var cue = Cue(number: "4.8", content: .anagram(AnagramContent(anagrams: anagrams)))
        cue.setCuePoint("SOPHIE: \u{201C}It\u{2019}s an anagram.\u{201D}", ofGoPoint: 0, defaults: defaults(.eachStep))
        cue.setCuePoint("  LANGDON turns.  ", ofGoPoint: 2, defaults: defaults(.eachStep))
        #expect(cue.goPoints(defaults: defaults(.eachStep)).map(\.cuePoint)
                == ["SOPHIE: \u{201C}It\u{2019}s an anagram.\u{201D}", "", "LANGDON turns."])
        #expect(cue.goPoints(defaults: defaults(.eachAnagram)).map(\.cuePoint) == ["SOPHIE: \u{201C}It\u{2019}s an anagram.\u{201D}", "LANGDON turns."],
                "each anagram waits before its first move: the same moments")
        #expect(cue.goPoints(defaults: defaults(.byItself)).isEmpty)
        cue.setCuePoint("", ofGoPoint: 1, defaults: defaults(.eachAnagram))
        #expect(cue.goPoints(defaults: defaults(.eachStep)).map(\.cuePoint).last == "", "empty clears it")
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
        var morph = Cue(content: .morph(MorphContent(text: "", pictures: [MorphPicture(src: "a.png"), MorphPicture(src: "b.png"), MorphPicture(src: "c.png")])))
        morph.setCuePoint("Lights shift", ofGoPoint: 1, defaults: defaults(.eachStep))
        #expect(morph.goPoints(defaults: defaults(.eachStep)).map(\.cuePoint) == ["", "Lights shift"])
        guard case .morph(let m) = morph.content else { return }
        #expect(m.pictures[2].cuePoint == "Lights shift" && !m.isPlain)

        var map = Cue(content: .map(MapContent(route: [RoutePoint(at: PicturePoint(x: 0, y: 0)), RoutePoint(at: PicturePoint(x: 0.5, y: 0)),
                                                       RoutePoint(at: PicturePoint(x: 1, y: 0), stop: MapStop(place: "BOW"))])))
        map.setCuePoint("Phone rings", ofGoPoint: 0, defaults: defaults(.eachStep))
        #expect(map.goPoints(defaults: defaults(.eachStep)).map(\.cuePoint) == ["Phone rings"])
        map.setCuePoint("ignored", ofGoPoint: 0, defaults: defaults(.byItself))
        #expect(map.goPoints(defaults: defaults(.eachStep)).map(\.cuePoint) == ["Phone rings"], "no GO by itself, nothing to set")
    }

    @Test("show.json keeps them, as version 6; a show without any stays as it was")
    func json() throws {
        var cue = Cue(number: "4.8", content: .anagram(AnagramContent(anagrams: [Anagram(text: "Oh, lame saint!", answer: "The Mona Lisa!")])))
        let plain = Show(cues: [cue])
        #expect(plain.version == 2)
        cue.setCuePoint("SOPHIE looks up", ofGoPoint: 0, defaults: defaults(.eachAnagram))
        let data = try JSONEncoder().encode(cue)
        #expect(String(data: data, encoding: .utf8)?.contains("\"cuePoints\"") == true)
        #expect(try JSONDecoder().decode(Cue.self, from: data) == cue)
        #expect(Show(cues: [cue]).version == 6)
    }

    @Test("The DSM sheet prints each GO's cue point on its row")
    func sheet() {
        var cue = Cue(number: "4.8", content: .anagram(AnagramContent(anagrams: anagrams, overrides: AnagramOverrides(advance: .eachAnagram))))
        cue.setCuePoint("LANGDON turns.", ofGoPoint: 1, defaults: ShowSettings())
        let rows = CueSheet(show: Show(title: "T", cues: [cue]), title: "T", layout: .dsm).rows
        #expect(rows.map(\.cuePoint) == ["", "", "LANGDON turns."])
    }
}
