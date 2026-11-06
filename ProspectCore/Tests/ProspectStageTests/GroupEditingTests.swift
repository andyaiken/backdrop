import Foundation
import ProspectCore
import Testing
@testable import ProspectStage

/// Editing groups through the show controller, each change one step of undo.
@Suite("Editing groups")
@MainActor
struct GroupEditingTests {
    func controller(_ numbers: [String] = ["1", "2", "3", "4"]) -> ShowController {
        let cues = numbers.map { Cue(number: $0, content: .title(TitleContent(text: "CUE \($0)"))) }
        return ShowController(show: Show(title: "T", cues: cues), mode: .edit, renderers: [:])
    }

    func read(_ c: ShowController) -> [String] {
        c.show.outline.map { row in
            switch row {
            case .group(let g, let depth, _): String(repeating: "  ", count: depth) + "[\(g.name)]"
            case .cue(let cue, let depth): String(repeating: "  ", count: depth) + cue.number
            }
        }
    }

    func id(_ c: ShowController, _ number: String) -> UUID { c.show.cues.first { $0.number == number }!.id }

    @Test("Add Group puts a heading above the standby cue, inside the groups it is in")
    func add() {
        let c = controller()
        c.standBy(id(c, "1"))
        c.addGroup(named: "Act One")
        c.standBy(id(c, "3"))
        c.addGroup(named: "Scene 2")
        #expect(read(c) == ["[Act One]", "  1", "  2", "  [Scene 2]", "    3", "    4"])
        c.standBy(id(c, "1"))
        c.addGroup(named: "Scene 1")
        #expect(read(c) == ["[Act One]", "  [Scene 1]", "    1", "    2", "  [Scene 2]", "    3", "    4"], "under the heading already there")
        #expect(c.show.cues.map(\.number) == ["1", "2", "3", "4"], "the cues never move")
    }

    @Test("Renumbering a group is one step of undo, and leaves every other cue alone")
    func renumber() {
        let c = controller()
        c.standBy(id(c, "3"))
        let act = c.addGroup(named: "Act Two")!
        var edits: [(Show, String)] = []
        c.onEdit = { edits.append(($0, $1)) }
        c.renumber(group: act, from: 100)
        #expect(c.show.cues.map(\.number) == ["1", "2", "100", "101"])
        #expect(edits.map(\.1) == ["Renumber Act Two"])
        c.restore(edits[0].0)
        #expect(c.show.cues.map(\.number) == ["1", "2", "3", "4"])
    }

    @Test("A heading can be renamed, moved a level in or out, and deleted, keeping what was in it")
    func renameLevelDelete() throws {
        let c = controller()
        c.standBy(id(c, "1"))
        let act = try #require(c.addGroup(named: "Act One"))
        c.standBy(id(c, "3"))
        let scene = try #require(c.addGroup(named: "Scene"))
        c.renameGroup(scene, to: "  Scene 2 ")
        c.renameGroup(scene, to: "   ")
        #expect(c.show.groups.last?.name == "Scene 2", "trimmed, and never emptied")
        c.moveGroupLevel(scene, by: -1)
        #expect(read(c) == ["[Act One]", "  1", "  2", "[Scene 2]", "  3", "  4"])
        c.moveGroupLevel(scene, by: -1)
        #expect(c.show.groups.last?.level == 0, "no further out than the outermost")
        c.deleteGroup(act)
        #expect(read(c) == ["1", "2", "[Scene 2]", "  3", "  4"])
    }

    @Test("A cue dropped under a heading joins its group; a group's first cue dragged away leaves the heading")
    func moveCues() throws {
        let c = controller()
        c.standBy(id(c, "3"))
        c.addGroup(named: "Act Two")
        #expect(read(c) == ["1", "2", "[Act Two]", "  3", "  4"])
        // Row 3 is the first under the heading: dropped there, 1 joins Act Two.
        c.moveCue(id(c, "1"), before: 3)
        #expect(read(c) == ["2", "[Act Two]", "  1", "  3", "  4"])
        // Dragged out above the heading, 1 leaves it, and the heading stays.
        c.moveCue(id(c, "1"), before: 0)
        #expect(read(c) == ["1", "2", "[Act Two]", "  3", "  4"])
        c.moveCue(id(c, "3"), before: 5)
        #expect(read(c) == ["1", "2", "[Act Two]", "  4", "  3"], "its first cue moved within it, the heading where it was")
        c.moveCue(id(c, "4"), before: 1)
        #expect(read(c) == ["1", "4", "2", "[Act Two]", "  3"])
        c.moveCue(id(c, "4"), by: 1)
        #expect(read(c) == ["1", "2", "4", "[Act Two]", "  3"], "moving by one past another cue keeps the heading")
    }

    @Test("A group moves with everything in it, nested groups included")
    func moveGroup() throws {
        let c = controller(["1", "2", "3", "4", "5"])
        c.standBy(id(c, "1"))
        c.addGroup(named: "Act One")
        c.standBy(id(c, "2"))
        let scene = try #require(c.addGroup(named: "Scene"))
        c.standBy(id(c, "4"))
        // Added inside both groups around cue 4, then moved out to the top.
        let two = try #require(c.addGroup(named: "Act Two"))
        c.moveGroupLevel(two, by: -2)
        #expect(read(c) == ["[Act One]", "  1", "  [Scene]", "    2", "    3", "[Act Two]", "  4", "  5"])
        c.moveGroup(scene, before: 8)
        #expect(read(c) == ["[Act One]", "  1", "[Act Two]", "  4", "  5", "  [Scene]", "    2", "    3"])
        #expect(c.show.cues.map(\.number) == ["1", "4", "5", "2", "3"], "moving a group moves its cues in the running order")
        c.moveGroup(scene, before: 6)
        #expect(read(c) == ["[Act One]", "  1", "[Act Two]", "  4", "  5", "  [Scene]", "    2", "    3"], "dropped inside itself, nothing moves")
    }

    @Test("Deleting a group's first cue leaves its heading above the next; every change is one step of undo")
    func deleteAndUndo() throws {
        let c = controller()
        var steps: [Show] = []
        c.onEdit = { before, _ in steps.append(before) }
        c.standBy(id(c, "3"))
        c.addGroup(named: "Act Two")
        c.deleteCue(id(c, "3"))
        #expect(read(c) == ["1", "2", "[Act Two]", "  4"])
        #expect(steps.count == 2)
        c.restore(try #require(steps.last))
        #expect(read(c) == ["1", "2", "[Act Two]", "  3", "  4"])
    }

    @Test("Nothing changes in show mode")
    func locked() {
        let c = ShowController(show: Show(title: "T", cues: [Cue(number: "1", content: .blank(BlankContent()))]), renderers: [:])
        #expect(c.addGroup() == nil && c.show.groups.isEmpty)
    }
}
