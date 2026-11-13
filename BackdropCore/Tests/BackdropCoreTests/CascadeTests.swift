import Foundation
import Testing
@testable import BackdropCore

@Suite("Cascade cues")
struct CascadeTests {
    func cascade(_ text: String = "ACCESS GRANTED", _ settings: CascadeSettings = .init()) -> Cue {
        Cue(number: "12", content: .cascade(CascadeContent(text: text, settings: settings)))
    }

    func plan(_ text: String = "ACCESS GRANTED", _ settings: CascadeSettings = .init(), seed: UInt32 = 7) -> CascadeCuePlan {
        var random = SeededRandom(seed: seed)
        return CascadeCuePlan(CascadeContent(text: text, settings: settings), aspect: 16.0 / 9, random: &random)
    }

    @Test("A cascade round trips through show.json, and raises the version beyond any other cue")
    func roundTrip() throws {
        var cue = cascade("WAKE UP\nNEO", CascadeSettings(clockMs: 60, holdTicks: 20, advance: .eachStep, columns: 64, density: 80, streak: 20))
        if case .cascade(var c) = cue.content { c.colour = RGB(0xFF, 0xB0, 0x00); c.goLine = "He opens his eyes"; cue.content = .cascade(c) }
        let show = Show(title: "T", cues: [cue])
        #expect(show.version == 12 && Show.formatVersion >= 12)
        let back = try JSONDecoder().decode(Show.self, from: try JSONEncoder().encode(show))
        #expect(back.cues == [cue])
        #expect(Show(title: "T", cues: [Cue(content: .conversation(ConversationContent()))]).version == 11)
    }

    @Test("show.json reads by hand, and a missing or unknown setting is the default")
    func lenient() throws {
        let json = #"{"kind":"cascade","num":"4","text":"HELLO","colour":"red","settings":{"advance":"sideways","columns":500,"streak":1}}"#
        let cue = try JSONDecoder().decode(Cue.self, from: Data(json.utf8))
        guard case .cascade(let c) = cue.content else { Issue.record("not a cascade"); return }
        #expect(c.text == "HELLO" && c.colour == RGB(255, 0, 0))
        #expect(c.settings.advance == .byItself)
        #expect(c.settings.columns == SettingRange.cascadeColumns.upperBound && c.settings.streak == SettingRange.cascadeStreak.lowerBound, "clamped")
        let bare = try JSONDecoder().decode(Cue.self, from: Data(#"{"kind":"cascade"}"#.utf8))
        #expect(bare.content == .cascade(CascadeContent()))
        #expect(CascadeContent().colour == CascadeContent.green)
    }

    @Test("Its message is the cue's text, and it is in the Add Cue menus")
    func labels() {
        var cue = cascade()
        #expect(cue.text == "ACCESS GRANTED" && cue.sub == "")
        cue.text = "DENIED"
        #expect(cue.content == .cascade(CascadeContent(text: "DENIED")))
        #expect(Cue.Kind.cascade.heading == "Cascade")
        #expect(Cue.Kind.others.contains(.cascade))
        #expect(cue.finishes && !cue.neverFinishes && !cue.timing.isInstant)
    }

    @Test("Rain with no message never finishes, so a continue when finished is flagged")
    func rainAlone() {
        var cue = cascade("  \n ")
        #expect(!cue.finishes && cue.neverFinishes)
        cue.continueMode = .whenFinished
        let show = Show(title: "T", cues: [cue, cascade()])
        #expect(show.issues.contains(.neverFinishes(cue: cue.id)))
        #expect(plan("").parts == [0] && !plan("").hasMessage)
    }

    @Test("The message's lines lose blank lines at either end and spaces at the end")
    func lines() {
        let c = CascadeContent(text: "\n  WAKE UP  \n\nNEO \n\n")
        #expect(c.lines == ["  WAKE UP", "", "NEO"])
        #expect(c.summary == "  WAKE UP / NEO")
        #expect(c.hasMessage && !CascadeContent(text: " \n\t").hasMessage)
    }

    @Test("A message on GO is one GO, with a cue point of its own; by itself it is none")
    func goPoints() {
        var cue = cascade("WAKE UP\nNEO", CascadeSettings(advance: .eachStep))
        #expect(cue.goPoints() == [GoPoint(unit: .message, text: "WAKE UP / NEO")])
        cue.setCuePoint("  He opens his eyes ", ofGoPoint: 0)
        #expect(cue.goPoints() == [GoPoint(unit: .message, text: "WAKE UP / NEO", cuePoint: "He opens his eyes")])
        #expect(cue.hasGoCuePoints)
        // No GO to give a cue point to.
        var alone = cascade("WAKE UP")
        alone.setCuePoint("Never", ofGoPoint: 0)
        #expect(alone.goPoints().isEmpty && !alone.hasGoCuePoints)
        #expect(cascade("", CascadeSettings(advance: .eachStep)).goPoints().isEmpty, "rain alone has nothing to wait for")
        #expect(plan("HI", CascadeSettings(advance: .eachStep)).parts.count == 2)
        #expect(plan("HI").parts.count == 1)
    }

    @Test("Its settings are set and read through the setting keys, Advance with two choices")
    func settingKeys() {
        var cue = cascade()
        for key in SettingKey.cascade { #expect(key.applies(to: .cascade) && key.value(in: cue) != nil, "\(key)") }
        #expect(!SettingKey.wave.applies(to: .cascade) && !SettingKey.pause.applies(to: .cascade))
        SettingKey.columns.set(.number(33), in: &cue)
        SettingKey.density.set(.number(42), in: &cue)
        SettingKey.streak.set(.number(30), in: &cue)
        SettingKey.advance.set(.advance(.eachStep), in: &cue)
        guard case .cascade(let c) = cue.content else { Issue.record("not a cascade"); return }
        #expect(c.settings.columns == 34 && c.settings.density == 40 && c.settings.streak == 30, "snapped to their steps")
        #expect(SettingKey.advance.choices(for: .cascade).map(\.label) == ["By itself", "Message on GO"])
        #expect(SettingKey.advance.format(.advance(.eachStep), for: .cascade) == "message on GO")
        #expect(SettingKey.density.format(.number(40)) == "40%" && SettingKey.streak.format(.number(30)) == "30 glyphs")
    }

    @Test("The printed sheet gives the message, and the settings it runs with")
    func sheet() {
        let show = Show(title: "T", cues: [cascade("WAKE UP\nNEO", CascadeSettings(advance: .eachStep))])
        let dsm = CueSheet(show: show, title: "T", layout: .dsm)
        #expect(dsm.rows.map(\.content) == [["WAKE UP", "NEO"], ["WAKE UP / NEO"]])
        #expect(dsm.rows[1].type == "GO 1")
        let op = CueSheet(show: show, title: "T", layout: .operatorSettings)
        let names = op.rows[0].settings.map(\.name)
        #expect(names.starts(with: ["Clock", "Hold", "Advance", "Columns", "Density", "Streak", "Colour", "Message"]))
        #expect(op.rows[0].settings.first { $0.name == "Colour" }?.value == "#00FF41")
    }

    @Test("The grid widens to fit the longest line, and the message sits in the middle")
    func layout() {
        let p = plan("WAKE UP\nNEO", CascadeSettings(columns: 16))
        #expect(p.columns == 16 && p.rows == Int((16 / (16.0 / 9) / CascadeCuePlan.cellShape).rounded()))
        let wide = plan(String(repeating: "X", count: 40), CascadeSettings(columns: 16))
        #expect(wide.columns == 44)
        let q = plan("WAKE UP\nNEO")
        #expect(String(q.letters.map(\.character)) == "WAKEUPNEO", "no letter for a space")
        let rows = Set(q.letters.map(\.row)).sorted()
        #expect(rows.count == 2 && rows[1] - rows[0] == 2, "a blank row between the lines")
        #expect(abs((rows[0] + rows[1]) - (q.rows - 1)) <= 1, "centred down the picture")
        let first = q.letters.filter { $0.row == rows[0] }.map(\.column)
        #expect(first == [20, 21, 22, 23, 25, 26], "centred across it")
    }

    @Test("The rain falls in from the top, then fills the picture")
    func rainFalls() {
        let p = plan("")
        let timeline = GoTimeline(parts: p.parts)
        let hold = CascadeSettings().holdTicks
        let first = p.frame(-hold, timeline: timeline)
        #expect(first.glyphs.allSatisfy { $0.row == 0 }, "nothing but heads on the top row the moment it fires")
        let later = p.frame(200, timeline: timeline)
        #expect(Set(later.glyphs.map(\.row)).count == p.rows, "a glyph on every row")
        #expect(later.glyphs.contains { $0.head } && later.glyphs.contains { !$0.head })
        #expect(later.letters.isEmpty && !later.isSettled)
        #expect(!p.frame(1_000_000, timeline: timeline).isSettled, "rain alone never settles")
        // Steady, it is full from the first frame.
        #expect(Set(p.frame(-hold, timeline: timeline, steady: true).glyphs.map(\.row)).count == p.rows)
    }

    @Test("Every glyph is on the grid and lit, and a frame is the same however it is reached")
    func deterministic() {
        let p = plan("WAKE UP")
        let timeline = GoTimeline(parts: p.parts)
        for f in [-30, 0, 15, 40, 90] {
            let frame = p.frame(f, timeline: timeline)
            #expect(frame == p.frame(f, timeline: timeline))
            for g in frame.glyphs {
                #expect((0..<p.columns).contains(g.column) && (0..<p.rows).contains(g.row))
                #expect(g.level > 0 && g.level <= 1 && CascadeContent.glyphs.indices.contains(g.glyph))
                #expect(!g.mirrored || g.glyph < CascadeContent.katakanaCount, "digits are never mirrored")
            }
        }
        // Another seed, other rain.
        #expect(plan("WAKE UP", seed: 8).frame(40, timeline: timeline) != p.frame(40, timeline: timeline))
        #expect(CascadeContent.glyphs.count == 66 && CascadeContent.glyphs.first == "\u{FF66}" && CascadeContent.glyphs.last == "9")
    }

    @Test("By itself, the message comes after the hold, a letter at a time, and settles alone")
    func resolvesByItself() {
        let p = plan("ACCESS GRANTED")
        let timeline = GoTimeline(parts: p.parts)
        #expect(p.frame(-1, timeline: timeline).letters.isEmpty, "nothing during the hold")
        let partway = p.frame(p.rows / 2 + 6, timeline: timeline)
        #expect(!partway.letters.isEmpty && partway.letters.count < p.letters.count, "some letters, not all: \(partway.letters.count)")
        let done = p.frame(p.resolveTicks, timeline: timeline)
        #expect(done.isSettled && done.glyphs.isEmpty)
        #expect(String(done.letters.map(\.character)) == "ACCESSGRANTED" && done.letters.allSatisfy { $0.cooled == 1 })
        #expect(!p.frame(p.resolveTicks - 1, timeline: timeline).isSettled)
        // A letter appears white and cools.
        let fresh = partway.letters.min { $0.cooled < $1.cooled }!
        #expect(fresh.cooled < 1)
    }

    @Test("The rain stops starting streaks once the message starts, and clears")
    func rainClears() {
        let p = plan("HI", CascadeSettings(density: 100))
        let timeline = GoTimeline(parts: p.parts)
        let before = p.frame(-1, timeline: timeline).glyphs.count
        let after = p.frame(CascadeCuePlan.drainTicks + 1, timeline: timeline)
        // Only the streaks that leave the letters are left.
        let columns = Set(p.letters.map(\.column))
        #expect(after.glyphs.allSatisfy { columns.contains($0.column) }, "only the message's streaks")
        #expect(after.glyphs.count < before)
    }

    @Test("On GO, the rain runs until GO, and the message comes from then")
    func resolvesOnGO() {
        let p = plan("HI", CascadeSettings(advance: .eachStep))
        var timeline = GoTimeline(parts: p.parts)
        #expect(p.frame(500, timeline: timeline).letters.isEmpty && !p.frame(500, timeline: timeline).isSettled)
        timeline.carryOn(at: 500)
        #expect(p.frame(500, timeline: timeline).letters.isEmpty)
        let done = p.frame(500 + p.resolveTicks, timeline: timeline)
        #expect(done.isSettled && done.letters.count == 2)
        // Straight to the message, from another cue's GO.
        var jumped = GoTimeline(parts: p.parts)
        jumped.jump(toPart: 1, at: 10)
        #expect(p.frame(10 + p.resolveTicks, timeline: jumped).isSettled)
        // Put up finished.
        var finished = GoTimeline(parts: p.parts)
        finished.carryOnToEnd()
        #expect(p.frame(1_000_000, timeline: finished) == CascadeFrame(glyphs: [], letters: done.letters, isSettled: true))
    }

    @Test("A long message keeps to the picture: lines that won't fit are left off")
    func tooManyLines() {
        let p = plan(Array(repeating: "LINE", count: 40).joined(separator: "\n"), CascadeSettings(columns: 16))
        #expect(p.letters.allSatisfy { (0..<p.rows).contains($0.row) && (0..<p.columns).contains($0.column) })
        #expect(Set(p.letters.map(\.row)).count == p.rows, "a line on every row once they are packed")
    }
}
