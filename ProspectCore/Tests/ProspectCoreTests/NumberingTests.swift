import Foundation
import Testing
@testable import ProspectCore

private func blank(_ number: String) -> Cue {
    Cue(number: number, content: .blank(BlankContent()))
}

private func sheet(_ numbers: [String]) -> Show {
    Show(cues: numbers.map(blank))
}

@Suite("Cue numbering")
struct NumberingTests {
    @Test("Lookup is trimmed and case-insensitive, otherwise exact")
    func lookupMatchesRecordedCases() throws {
        let fixture = try Fixtures.load("numbering", as: NumberingFixture.self).lookup
        let show = sheet(fixture.numbers)
        for c in fixture.cases {
            #expect(show.index(ofNumber: c.query) == (c.index < 0 ? nil : c.index), "\"\(c.query)\"")
        }
    }

    @Test(arguments: [
        ("4", "5", "4.5"),
        ("4", "4.5", "4.3"),
        ("4.5", "5", "4.8"),
        ("9", "9.1", "9.05"),
        ("4", "6", "5"),
        ("1", "10", "6"),
        ("4.50", "5", "4.8"),
        ("0", "1", "0.5"),
        ("12.99", "13", "12.995"),
        (" 7 ", "8", "7.5"),
    ])
    func numberBetween(_ a: String, _ b: String, _ expected: String) {
        #expect(Show.number(between: a, and: b) == expected)
    }

    @Test(arguments: [("P12", "13"), ("4", "P5"), ("5", "4"), ("4", "4"), ("4.5", "4.50"), ("", "1"), ("-1", "1"), ("1e2", "200")])
    func noNumberBetween(_ a: String, _ b: String) {
        #expect(Show.number(between: a, and: b) == nil)
    }

    @Test func insertionNumbers() {
        #expect(Show().numberForInsertion(after: nil) == "1")
        let show = sheet(["1", "2", "P12", "9.5"])
        #expect(show.numberForInsertion(after: 0) == "1.5")
        #expect(show.numberForInsertion(after: 1) == nil, "next to P12, the operator types it")
        #expect(show.numberForInsertion(after: 3) == "10", "after the last: the next whole number above the highest")
        #expect(show.numberForInsertion(after: nil) == "10")
        #expect(sheet(["P1", "P2"]).numberForInsertion(after: nil) == "1")
        #expect(sheet(["12a", "3"]).numberForInsertion(after: nil) == "13", "read as parseFloat reads it")
    }

    @Test func insertingNeverRenumbersNeighbours() {
        var show = sheet(["1", "2", "3"])
        let before = show.cues.map(\.number)
        let at = show.insert(blank("ignored"), after: 1)
        #expect(at == 2)
        #expect(show.cues.map(\.number) == ["1", "2", "2.5", "3"])
        #expect(show.cues.filter { $0.number != "2.5" }.map(\.number) == before)

        show.insert(blank(""), after: nil)
        #expect(show.cues.last?.number == "4")
    }

    @Test func duplicatesAreFound() {
        let show = sheet(["1", "2", " 1", "P3", "p3", "4", ""])
        let duplicates = show.duplicateNumbers
        #expect(duplicates.map(\.number) == ["1", "P3"])
        #expect(duplicates[0].cues == [show.cues[0].id, show.cues[2].id])
        #expect(sheet(["4.5", "4.50"]).duplicateNumbers.isEmpty, "string-equal, as lookup is")
    }

    @Test func renumberAll() {
        var show = sheet(["1", "1.5", "P12", "40"])
        show.renumberAll()
        #expect(show.cues.map(\.number) == ["1", "2", "3", "4"])
    }

    /// A preshow cue, Act One with a scene inside it, then Act Two.
    func acts() -> (Show, act1: UUID, scene: UUID, act2: UUID) {
        var show = sheet(["0.5", "1", "1.5", "2", "7", "8", "8.5"])
        let act1 = CueGroup(name: "Act One", level: 0, before: show.cues[1].id)
        let scene = CueGroup(name: "Scene 2", level: 1, before: show.cues[3].id)
        let act2 = CueGroup(name: "Act Two", level: 0, before: show.cues[5].id)
        show.groups = [act1, scene, act2]
        return (show, act1.id, scene.id, act2.id)
    }

    @Test("A group's cues are those under its heading, groups inside it included")
    func cuesInGroup() {
        let (show, act1, scene, act2) = acts()
        #expect(show.cues(inGroup: act1).compactMap { show[$0]?.number } == ["1", "1.5", "2", "7"])
        #expect(show.cues(inGroup: scene).compactMap { show[$0]?.number } == ["2", "7"])
        #expect(show.cues(inGroup: act2).compactMap { show[$0]?.number } == ["8", "8.5"])
    }

    @Test("Renumbering a group starts after the cues before it, unless told to start elsewhere")
    func renumberGroup() {
        var (show, act1, scene, act2) = acts()
        #expect(show.renumberStart(forGroup: act2) == 8, "the next whole number after 7")
        #expect(show.renumberStart(forGroup: act1) == 1)
        show.renumber(group: act2, from: 100)
        #expect(show.cues.map(\.number) == ["0.5", "1", "1.5", "2", "7", "100", "101"])
        show.renumber(group: act1, from: 1)
        #expect(show.cues.map(\.number) == ["0.5", "1", "2", "3", "4", "100", "101"], "the scene with it")
        #expect(show.renumberClashes(group: scene, from: 100) == ["100", "101"])
        #expect(show.renumberClashes(group: scene, from: 3).isEmpty, "its own numbers don't clash")
    }
}
