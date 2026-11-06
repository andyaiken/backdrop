import Foundation
import Testing
@testable import ProspectCore

private func cue(_ number: String) -> Cue {
    Cue(number: number, content: .title(TitleContent(text: "CUE \(number)")))
}

@Suite("Group cues")
struct GroupsTests {
    /// Preshow, then Act One with two scenes, then Act Two with nothing
    /// nested, then an empty group at the end.
    let show: Show = {
        let cues = ["0.5", "1", "2", "3", "4", "5"].map(cue)
        let groups = [
            CueGroup(name: "Act One", level: 0, before: cues[1].id),
            CueGroup(name: "Scene 1", level: 1, before: cues[1].id),
            CueGroup(name: "Scene 2", level: 1, before: cues[3].id),
            CueGroup(name: "Act Two", level: 0, before: cues[4].id),
            CueGroup(name: "Curtain call", level: 0, before: nil),
        ]
        return Show(title: "T", cues: cues, groups: groups)
    }()

    func read(_ rows: [OutlineRow]) -> [String] {
        rows.map { row in
            switch row {
            case .group(let g, let depth, let count): String(repeating: "  ", count: depth) + "\(g.name) (\(count))"
            case .cue(let c, let depth): String(repeating: "  ", count: depth) + c.number
            }
        }
    }

    @Test("The outline: each heading where it stands, each cue at the depth of the groups around it")
    func outline() {
        #expect(read(show.outline) == [
            "0.5",
            "Act One (3)", "  Scene 1 (2)", "    1", "    2", "  Scene 2 (1)", "    3",
            "Act Two (2)", "  4", "  5",
            "Curtain call (0)",
        ])
        #expect(show.groups(around: show.cues[2].id).map(\.name) == ["Act One", "Scene 1"])
        #expect(show.groups(around: show.cues[0].id).isEmpty, "the preshow belongs to no group")
    }

    @Test("A level deeper than the group above allows reads as one step in")
    func levelGaps() {
        let cues = ["1", "2"].map(cue)
        let show = Show(cues: cues, groups: [CueGroup(name: "Act", level: 0, before: cues[0].id),
                                             CueGroup(name: "Deep", level: 5, before: cues[1].id)])
        #expect(read(show.outline) == ["Act (2)", "  1", "  Deep (1)", "    2"])
    }

    @Test("Running the show never sees groups: the cues are unchanged")
    func running() {
        #expect(show.cues.map(\.number) == ["0.5", "1", "2", "3", "4", "5"])
        var p = Playhead(show: show)
        var fired: [String] = []
        while let fire = p.go(in: show) { fired.append(show[fire.cue]?.number ?? "?") }
        #expect(fired == ["0.5", "1", "2", "3", "4", "5"], "GO runs straight through every group")
    }

    @Test("show.json lists headings where they read, and a show with groups is version 3")
    func json() throws {
        let data = try show.jsonData()
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == 3)
        let entries = try #require(object["cues"] as? [[String: Any]])
        #expect(entries.map { $0["kind"] as? String == "group" ? "[\($0["name"] as? String ?? "")]" : $0["num"] as? String ?? "" }
            == ["0.5", "[Act One]", "[Scene 1]", "1", "2", "[Scene 2]", "3", "[Act Two]", "4", "5", "[Curtain call]"])
        #expect(try Show(jsonData: data) == show)
    }

    @Test("A show with no groups keeps version 2 and today's shape")
    func noGroups() throws {
        let plain = Show(title: "T", cues: show.cues)
        let object = try #require(JSONSerialization.jsonObject(with: plain.jsonData()) as? [String: Any])
        #expect(object["version"] as? Int == 2)
        #expect((object["cues"] as? [[String: Any]])?.allSatisfy { $0["kind"] as? String != "group" } == true)
        #expect(try ShowPackage.updated(nil, with: plain).fileWrappers?["version"]?.regularFileContents == Data("2\n".utf8))
        #expect(try ShowPackage.updated(nil, with: show).fileWrappers?["version"]?.regularFileContents == Data("3\n".utf8))
    }

    @Test("Deleting a group's first cue leaves its heading above the next cue")
    func deleteFirstCue() {
        var edited = show
        edited.cues.removeAll { $0.number == "4" }
        edited.tidyGroups(after: show)
        #expect(read(edited.outline).suffix(3) == ["Act Two (1)", "  5", "Curtain call (0)"])
        var last = show
        last.cues.removeAll { ["4", "5"].contains($0.number) }
        last.tidyGroups(after: show)
        #expect(read(last.outline).suffix(2) == ["Act Two (0)", "Curtain call (0)"], "with nothing left after it, at the end, in order")
    }

    @Test("The printed sheet: a heading row per group, everything in it indented, no new pages")
    func sheet() {
        let rows = CueSheet(show: show, title: "T", layout: .dsm).rows
        #expect(rows.map { $0.heading ? "[\($0.content[0])]" : $0.number } ==
            ["0.5", "[Act One]", "[Scene 1]", "1", "2", "[Scene 2]", "3", "[Act Two]", "4", "5", "[Curtain call]"])
        #expect(rows.map(\.depth) == [0, 0, 1, 2, 2, 1, 2, 0, 1, 1, 0])
        #expect(CueSheet(show: show, title: "T", layout: .operatorSettings).rows.filter(\.heading).count == 5, "in both layouts")
    }
}
