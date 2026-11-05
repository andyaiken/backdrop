import Foundation
import Testing
@testable import ProspectCore

private func anagramCue(_ number: String, _ anagrams: [Anagram], advance: AnagramAdvance? = nil) -> Cue {
    Cue(number: number, content: .anagram(AnagramContent(anagrams: anagrams, overrides: AnagramOverrides(advance: advance))))
}

private func titleCue(_ number: String, continues: ContinueMode = .whenCued) -> Cue {
    Cue(number: number, continueMode: continues, content: .title(TitleContent(text: "CUE \(number)")))
}

@Suite("Anagrams: several to a cue, and working")
struct AnagramWorkingTests {
    static let louvre = Anagram(text: "O, Draconian devil!", working: ["Dracula? No."], answer: "Leonardo da Vinci!")
    static let lisa = Anagram(text: "Oh, lame saint!", answer: "The Mona Lisa!")
    /// Short words, so every start and length comes out exact with `Still`.
    static let rats = Anagram(text: "RATS", working: ["TSAR"], answer: "STAR")
    static let listen = Anagram(text: "LISTEN", answer: "SILENT")

    func plan(_ anagrams: [Anagram], pause: Int = 10, advance: AnagramAdvance = .byItself) -> AnagramCuePlan {
        var still = Still()
        return AnagramCuePlan(anagrams, wave: 3, pause: pause, advance: advance, random: &still)
    }

    // MARK: The text box

    @Test("The text box: a paragraph an anagram, phrase first, answer last, working between")
    func paragraphs() {
        let typed = "O, Draconian devil!\nDracula? No.\nLeonardo da Vinci!\n\n  Oh, lame saint!  \nThe Mona Lisa!\n\n\nRose"
        let read = Anagram.anagrams(fromParagraphs: typed)
        #expect(read == [Self.louvre, Self.lisa, Anagram(text: "Rose")], "a lone line is solved already")
        #expect(Anagram.paragraphs(read) == "O, Draconian devil!\nDracula? No.\nLeonardo da Vinci!\n\nOh, lame saint!\nThe Mona Lisa!\n\nRose")
        #expect(Anagram.anagrams(fromParagraphs: "RATS\r\nSTAR") == [Anagram(text: "RATS", answer: "STAR")], "a Windows line break is one break")
        #expect(Anagram.anagrams(fromParagraphs: "  \n\n") == [])
        #expect(Self.louvre.steps == ["O, Draconian devil!", "Dracula? No.", "Leonardo da Vinci!"])
        #expect(Anagram(text: "RATS", working: [" "], answer: "").steps == ["RATS"], "blank steps are left out")
    }

    @Test("~ before a phrase ignores its anagram, and is written back")
    func ignoreMark() {
        let read = Anagram.anagrams(fromParagraphs: "~ O, Draconian devil!\nLeonardo da Vinci!\n\n~Oh, lame saint!\nThe Mona Lisa!\n\nRATS\nSTAR")
        #expect(read == [Anagram(text: "O, Draconian devil!", answer: "Leonardo da Vinci!", ignored: true),
                         Anagram(text: "Oh, lame saint!", answer: "The Mona Lisa!", ignored: true),
                         Anagram(text: "RATS", answer: "STAR")])
        #expect(Anagram.paragraphs(read) == "~ O, Draconian devil!\nLeonardo da Vinci!\n\n~ Oh, lame saint!\nThe Mona Lisa!\n\nRATS\nSTAR")
        #expect(read.map(\.isSolvedOnStage) == [false, false, true])
        let alone = Anagram(text: "Leonardo da Vinci!")
        #expect(alone.isSolvedAlready && !alone.isSolvedOnStage)
        #expect(Anagram(text: "Leonardo da Vinci!", ignored: true).isSolvedAlready, "one line is solved, ignored or not")
    }

    // MARK: show.json

    @Test("A single plain anagram stays flat in show.json; several, or working, are listed")
    func json() throws {
        let plain = Cue(number: "4", content: .anagram(AnagramContent(text: "RATS", answer: "STAR")))
        let flat = try #require(String(data: JSONEncoder().encode(plain), encoding: .utf8))
        #expect(flat.contains("\"text\":\"RATS\"") && flat.contains("\"answer\":\"STAR\"") && !flat.contains("anagrams"),
                "as version 1 wrote it, so a plain show diffs as nothing")

        let worked = anagramCue("5", [Self.rats, Self.listen])
        let data = try JSONEncoder().encode(worked)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["text"] == nil && object["answer"] == nil, "nothing said twice")
        let list = try #require(object["anagrams"] as? [[String: Any]])
        #expect(list.count == 2 && list[0]["working"] as? [String] == ["TSAR"] && list[1]["working"] == nil)
        #expect(try JSONDecoder().decode(Cue.self, from: data) == worked)

        let empty = Cue(number: "6", content: .anagram(AnagramContent()))
        #expect(try JSONDecoder().decode(Cue.self, from: JSONEncoder().encode(empty)) == empty)

        let ignored = anagramCue("7", [Anagram(text: "RATS", answer: "STAR", ignored: true)])
        let marked = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(ignored)) as? [String: Any])
        #expect((marked["anagrams"] as? [[String: Any]])?.first?["ignored"] as? Bool == true, "an ignored one is listed, to say so")
        #expect(list[0]["ignored"] == nil, "and only it")
        #expect(try JSONDecoder().decode(Cue.self, from: JSONEncoder().encode(ignored)) == ignored)
    }

    @Test("A version 1 show reads as it was; this version writes 2")
    func versions() throws {
        let old = #"{"version": 1, "cues": [{"kind": "anagram", "num": "1", "text": "RATS", "answer": "STAR"}]}"#
        let show = try Show(jsonData: Data(old.utf8))
        #expect(show.cues[0].content == .anagram(AnagramContent(text: "RATS", answer: "STAR")))
        #expect(show.cues[0].text == "RATS" && show.cues[0].sub == "STAR")
        let written = try #require(JSONSerialization.jsonObject(with: show.jsonData()) as? [String: Any])
        #expect(written["version"] as? Int == 2)
    }

    // MARK: Steps

    @Test("Letters a step of working doesn't use dim on a line beneath it, in the order they stood")
    func dimmedLine() {
        let p = plan([Anagram(text: "O, Draconian devil!", working: ["LEONARDO"], answer: "Leonardo da Vinci!")])
        let steps = p.tracks[0].steps
        #expect(steps.map(\.lines) == [["O, Draconian devil!"], ["LEONARDO", "c i a n d v i"], ["Leonardo da Vinci!"]])
        #expect(steps.map(\.dimFrom) == [1, 1, 1], "the phrase and the answer stand alone")

        let into = p.tracks[0].moves[0].plan
        #expect(into.pieces.filter { $0.to?.line == 1 }.count == 7, "seven letters wait beneath")
        #expect(into.pieces.filter { $0.to == nil }.map(\.character) == [",", "!"], "punctuation fades, as it always has")
        let out = p.tracks[0].moves[1].plan
        #expect(out.pieces.filter(\.travels).count == 15, "the answer takes every letter back up")
        #expect(out.pieces.filter { $0.from?.line == 1 }.count == 7)
    }

    @Test("Letters that wrong working brings in, and later steps don't use, wait beneath too")
    func wrongWorking() {
        let p = plan([Anagram(text: "RATS", working: ["RUST", "STAR"], answer: "TSAR")])
        // RUST brings a U and leaves an A; STAR takes the A back and leaves the U.
        #expect(p.tracks[0].steps.map(\.lines) == [["RATS"], ["RUST", "A"], ["STAR", "U"], ["TSAR"]])
        #expect(p.tracks[0].moves.map(\.warms) == [false, false, true], "only the answer warms")
    }

    // MARK: Parts

    @Test("By itself: each step a pause after the last lands, each anagram a pause after the last is solved")
    func byItself() {
        let p = plan([Self.rats, Self.listen])
        // RATS to TSAR and on to STAR take 9 + 24 each; LISTEN 15 + 24.
        #expect(p.tracks[0].moves.map(\.plan.duration) == [33, 33] && p.tracks[1].moves[0].plan.duration == 39)
        #expect(p.parts == [33 + 10 + 33 + 10 + 39])
        #expect(p.tracks.flatMap(\.moves).map(\.offset) == [0, 43, 86])
    }

    @Test("Each anagram on GO, and each step on GO, split the cue into parts")
    func parts() {
        let anagrams = [Self.rats, Anagram(text: "Rose"), Self.listen]
        let each = plan(anagrams, advance: .eachAnagram)
        #expect(each.parts == [0, 76, 39], "nothing before the first GO; an anagram solved already has no turn")
        #expect(each.tracks[0].moves.map(\.part) == [1, 1] && each.tracks[0].moves.map(\.offset) == [0, 43])
        #expect(each.tracks[1].moves.isEmpty && each.tracks[1].still.fromLines == ["Rose"])
        let steps = plan(anagrams, advance: .eachStep)
        #expect(steps.parts == [0, 33, 33, 39])
        for advance in AnagramAdvance.allCases {
            let content = AnagramContent(anagrams: anagrams)
            #expect(plan(anagrams, advance: advance).parts.count - 1 == content.goPoints(advance).count, "\(advance)")
        }
        #expect(AnagramContent(anagrams: anagrams).goPoints(.eachStep) ==
            [GoPoint(unit: .step, text: "TSAR"), GoPoint(unit: .step, text: "STAR"), GoPoint(unit: .step, text: "SILENT")])
        #expect(AnagramContent(anagrams: anagrams).goPoints(.eachAnagram).map(\.text) == ["RATS", "LISTEN"])
    }

    @Test("An ignored anagram keeps its phrase, jumbled; one line alone stands solved; the cue skips both")
    func skipped() {
        let anagrams = [Anagram(text: "LISTEN", working: ["TINSEL"], answer: "SILENT", ignored: true), Anagram(text: "Leonardo da Vinci!"),
                        Self.rats]
        let p = plan(anagrams, advance: .eachStep)
        #expect(p.tracks.map(\.steps.count) == [1, 1, 3] && p.tracks.map(\.moves.count) == [0, 0, 2])
        #expect(p.tracks[0].still.fromLines == ["LISTEN"] && !p.tracks[0].solvedAlready)
        #expect(p.tracks[1].still.fromLines == ["Leonardo da Vinci!"] && p.tracks[1].solvedAlready)
        #expect(p.parts == [0, 33, 33], "two GOs, both for RATS")
        #expect(AnagramContent(anagrams: anagrams).goPoints(.eachAnagram).map(\.text) == ["RATS"])
        #expect(plan(anagrams).parts == [33 + 10 + 33], "by itself, straight to RATS")
    }

    @Test("Each anagram shows the latest move to set off, or its first, waiting")
    func shown() {
        let p = plan([Self.rats, Self.listen, Anagram(text: "Rose")], advance: .eachAnagram)
        var t = GoTimeline(parts: p.parts)
        t.carryOn(at: 10)
        #expect(p.shown(p.tracks[0], at: 5, timeline: t)! == (0, 10))
        #expect(p.shown(p.tracks[0], at: 60, timeline: t)! == (1, 53))
        #expect(p.shown(p.tracks[1], at: 60, timeline: t)! == (0, nil), "still waiting for its GO")
        #expect(p.shown(p.tracks[2], at: 60, timeline: t) == nil, "a phrase with no answer stands still")
    }

    // MARK: The sheet

    @Test("Each anagram is checked on its own; working may use any letters")
    func issues() {
        let cue = anagramCue("6", [Anagram(text: "RATS", working: ["XYZ"], answer: "STAR"), Anagram(text: "Listen", answer: "Silents"),
                                   Anagram(text: "Rose"), Anagram(text: "Rose", answer: "Orbs", ignored: true)])
        let empty = anagramCue("7", [])
        let show = Show(title: "T", cues: [cue, empty])
        #expect(show.issues == [
            .anagramLettersDiffer(cue: cue.id, anagram: 1, extra: "", missing: "S"),
            .anagramWithoutPhrase(cue: empty.id, anagram: 0),
        ], "neither one solved already nor one ignored is checked")
        #expect(show.issues.map(show.message(for:)) == [
            "Cue 6\u{2019}s second anagram isn\u{2019}t exact: only the answer has S. Those letters fade instead of moving.",
            "Cue 7 needs both phrases: the one that appears and the one it rearranges into.",
        ])
    }

    @Test("The printed sheet lists each anagram, its working and its answer, and gives every GO a row of its own")
    func sheet() {
        func rows(_ advance: AnagramAdvance?, _ layout: CueSheet.Layout = .dsm) -> [CueSheet.Row] {
            CueSheet(show: Show(title: "T", cues: [anagramCue("4", [Self.louvre, Self.lisa], advance: advance)]), title: "T", layout: layout).rows
        }
        let lines = ["O, Draconian devil!", "\u{2026} Dracula? No.", "\u{2192} Leonardo da Vinci!", "Oh, lame saint!", "\u{2192} The Mona Lisa!"]
        #expect(rows(nil).count == 1 && rows(nil)[0].content == lines)
        let each = rows(.eachAnagram)
        #expect(each[0].content == lines, "the cue's own row as before")
        #expect(each.dropFirst().map(\.type) == ["GO 1", "GO 2"] && each.dropFirst().map(\.go) == [1, 2])
        #expect(each.dropFirst().map(\.content) == [["O, Draconian devil!"], ["Oh, lame saint!"]])
        #expect(each.dropFirst().allSatisfy { $0.number.isEmpty && $0.cuePoint.isEmpty }, "no number, and a cue point left for pencil")
        #expect(rows(.eachStep).dropFirst().map(\.content) == [["Dracula? No."], ["Leonardo da Vinci!"], ["The Mona Lisa!"]])
        #expect(rows(.eachStep, .operatorSettings).count == 1, "the operator's layout keeps one row a cue")
        let skipped = CueSheet(show: Show(title: "T", cues: [anagramCue("4", [Anagram(text: "Leonardo da Vinci!"),
            Anagram(text: "Oh, lame saint!", answer: "The Mona Lisa!", ignored: true)], advance: .eachStep)]), title: "T", layout: .dsm)
        #expect(skipped.rows.map(\.content) == [["Leonardo da Vinci! (solved)", "Oh, lame saint! (ignored)"]], "and no GO for either")
        let settings = CueSheet(show: Show(title: "T", cues: [anagramCue("4", [Self.rats], advance: .eachStep)]), title: "T",
                                layout: .operatorSettings).rows[0].settings
        #expect(settings.first { $0.name == "Advance" } == CueSheet.Setting(name: "Advance", value: "each step on GO", overridden: true))
    }

    // MARK: Settings

    @Test("Advance and Pause: show defaults any anagram cue can override")
    func settings() throws {
        #expect(ShowSettings().advance == .byItself && ShowSettings().pauseTicks == 44)
        var cue = anagramCue("1", [Self.rats])
        SettingKey.advance.setOverride(.advance(.eachStep), in: &cue)
        SettingKey.pause.setOverride(.number(999), in: &cue)
        guard case .anagram(let c) = cue.content else { return }
        let resolved = ShowSettings().resolved(c.overrides)
        #expect(resolved.advance == .eachStep && resolved.pauseTicks == 160, "clamped to the slider")
        #expect(cue.goPoints(defaults: ShowSettings()).count == 2)
        #expect(SettingKey.pause.format(.number(0)) == "none" && SettingKey.advance.format(.advance(.eachAnagram)) == "each anagram on GO")
        #expect(SettingKey.advance.choiceIndex(of: .advance(.eachStep)) == 2)
        #expect(!SettingKey.pause.applies(to: .title) && !SettingKey.advance.applies(to: .image))

        let json = #"{"advance": "anagram", "pauseTicks": 999}"#
        let decoded = try JSONDecoder().decode(ShowSettings.self, from: Data(json.utf8))
        #expect(decoded.advance == .eachAnagram && decoded.pauseTicks == 160)
        let back = try JSONDecoder().decode(Cue.self, from: JSONEncoder().encode(cue))
        #expect(SettingKey.advance.override(in: back) == .advance(.eachStep))
    }

    // MARK: The playhead

    @Test("GO carries a waiting cue on, step by step, before the next cue fires")
    func goCarriesOn() {
        let sheet = Show(cues: [titleCue("1"), anagramCue("2", [Self.rats], advance: .eachStep), titleCue("3")])
        let (two, three) = (sheet.cues[1].id, sheet.cues[2].id)
        var p = Playhead(show: sheet)
        _ = p.go(in: sheet)
        #expect(p.standby == two && p.standbyStep == nil)
        #expect(p.go(in: sheet) == Playhead.Fire(cue: two, presentation: .run, automatic: false))
        #expect(p.standby == two && p.standbyStep == 0, "its first step stands by next")
        #expect(p.go(in: sheet) == Playhead.Fire(cue: two, presentation: .carryOn, automatic: false))
        #expect(p.standbyStep == 1 && p.live == two)
        _ = p.go(in: sheet)
        #expect(p.standby == three && p.standbyStep == nil)
        #expect(p.go(in: sheet)?.cue == three)
    }

    @Test("The arrows move a row at a time, through every cue's steps, live or not")
    func arrows() {
        let sheet = Show(cues: [titleCue("1"), anagramCue("2", [Self.rats], advance: .eachStep), titleCue("3")])
        let (one, two, three) = (sheet.cues[0].id, sheet.cues[1].id, sheet.cues[2].id)
        var p = Playhead(show: sheet)
        var rows: [String] = []
        func row() -> String { [p.standby.map { $0 == one ? "1" : $0 == two ? "2" : $0 == three ? "3" : "?" } ?? "end",
                                p.standbyStep.map { "/\($0)" } ?? ""].joined() }
        for _ in 0..<5 {
            rows.append(row())
            p.standByNext(in: sheet)
        }
        rows.append(row())
        #expect(rows == ["1", "2", "2/0", "2/1", "3", "end"])
        rows = []
        for _ in 0..<5 {
            p.standByPrevious(in: sheet)
            rows.append(row())
        }
        p.standByPrevious(in: sheet)
        rows.append(row())
        #expect(rows == ["3", "2/1", "2/0", "2", "1", "1"], "from the end of the sheet back to the first cue, which stays")
        p.standBy(two, step: 1, in: sheet)
        #expect(row() == "2/1")
        p.standBy(two, step: 5, in: sheet)
        #expect(row() == "2", "a step the cue doesn't have stands by the cue")
        p.standBy(two, step: 1, in: sheet)
        p.standBy(three)
        #expect(row() == "3", "a click on a cue stands by the cue itself")
    }

    @Test("A step of another cue fires that cue there, the steps before it already done")
    func fireAtStep() {
        let sheet = Show(cues: [titleCue("1"), anagramCue("2", [Self.rats], advance: .eachStep), titleCue("3")])
        let two = sheet.cues[1].id
        var p = Playhead(show: sheet)
        _ = p.go(in: sheet)
        p.standBy(two, step: 1, in: sheet)
        #expect(p.go(in: sheet) == Playhead.Fire(cue: two, presentation: .run, automatic: false, step: 1))
        #expect(p.live == two && p.goPointsTaken == 2)
        #expect(p.standby == sheet.cues[2].id && p.standbyStep == nil)
    }

    @Test("Within the live cue, GO jumps straight to a step, forward or back")
    func jumps() {
        let sheet = Show(cues: [anagramCue("1", [Self.rats], advance: .eachStep), titleCue("2")])
        let one = sheet.cues[0].id
        var p = Playhead(show: sheet)
        _ = p.go(in: sheet)
        p.standBy(one, step: 1, in: sheet)
        #expect(p.go(in: sheet) == Playhead.Fire(cue: one, presentation: .carryOn, automatic: false, step: 1), "forward, past step 0")
        #expect(p.goPointsTaken == 2 && p.standby == sheet.cues[1].id)
        p.standBy(one, step: 0, in: sheet)
        #expect(p.go(in: sheet) == Playhead.Fire(cue: one, presentation: .carryOn, automatic: false, step: 0), "back to a step done")
        #expect(p.goPointsTaken == 1 && p.standbyStep == 1)
        #expect(p.go(in: sheet) == Playhead.Fire(cue: one, presentation: .carryOn, automatic: false), "then on to the next as usual")
    }

    @Test("R starts a cue's steps again; a resume or a redraw finishes them; a delete clears them")
    func rerunAndResume() {
        let sheet = Show(cues: [anagramCue("1", [Self.rats, Self.listen], advance: .eachAnagram), titleCue("2")])
        let id = sheet.cues[0].id
        var p = Playhead(show: sheet)
        _ = p.go(in: sheet)
        _ = p.go(in: sheet)
        #expect(p.standbyStep == 1)
        #expect(p.rerun(in: sheet)?.presentation == .run)
        #expect(p.standby == id && p.standbyStep == 0 && p.goPointsTaken == 0)
        p.liveCueRedrawn(in: sheet)
        #expect(p.goPointsTaken == 2 && p.standby == sheet.cues[1].id, "finished, it waits for nothing")

        var resumed = Playhead(show: sheet)
        _ = resumed.resume(at: id, in: sheet)
        #expect(resumed.goPointsTaken == 2 && resumed.standby == sheet.cues[1].id, "put up finished, it waits for nothing")

        var deleted = Playhead(show: sheet)
        _ = deleted.go(in: sheet)
        let edited = Show(cues: [sheet.cues[1]])
        deleted.reconcile(from: sheet, to: edited)
        #expect(deleted.live == nil && deleted.standbyStep == nil && deleted.standby == sheet.cues[1].id)
    }

    @Test("A step that an edit takes away gives way to its cue")
    func editedAway() {
        let sheet = Show(cues: [anagramCue("1", [Self.rats], advance: .eachStep), titleCue("2")])
        var p = Playhead(show: sheet)
        p.standBy(sheet.cues[0].id, step: 1, in: sheet)
        var edited = sheet
        if case .anagram(var c) = edited.cues[0].content {
            c.overrides.advance = .byItself
            edited.cues[0].content = .anagram(c)
        }
        p.reconcile(from: sheet, to: edited)
        #expect(p.standby == sheet.cues[0].id && p.standbyStep == nil)
    }

    @Test("A cue the show continues into has its steps too")
    func continuedInto() {
        let sheet = Show(cues: [titleCue("1", continues: .after(ms: 0)), anagramCue("2", [Self.rats], advance: .eachAnagram)])
        var p = Playhead(show: sheet)
        _ = p.go(in: sheet)
        #expect(p.continueAfter(sheet.cues[0].id, in: sheet)?.automatic == true)
        #expect(p.standby == sheet.cues[1].id && p.standbyStep == 0)
    }
}
