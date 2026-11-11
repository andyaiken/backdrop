import Foundation
import Testing
@testable import BackdropCore

private func layer(_ name: String, withPrevious: Bool = false, life: LayerLife = .stays, cue: String = "", exit: String = "") -> ImageLayer {
    ImageLayer(src: "media/\(name).png", name: name, cuePoint: cue, exitCuePoint: exit, withPrevious: withPrevious, life: life)
}

private func layered(_ layers: [ImageLayer], settings: LayeredSettings = .init()) -> Cue {
    Cue(number: "9", content: .layered(LayeredContent(text: "Last Supper", base: "media/base.png", layers: layers, settings: settings)))
}

private func content(_ cue: Cue) -> LayeredContent {
    guard case .layered(let c) = cue.content else { fatalError() }
    return c
}

@Suite("Layered image cues: the model")
struct LayeredModelTests {
    @Test("A layered cue round trips through show.json, and only it raises the version")
    func roundTrip() throws {
        var rich = layer("hands", life: .untilNextGo, exit: "no hands")
        rich.level = 60
        rich.blend = .screen
        rich.fadeMs = 1200
        rich.highlight = LayerHighlight(context: LayerContext.dim)
        rich.frame = PictureRect(x: 0.2, y: 0.3, width: 0.3, height: 0.2)
        let cue = layered([layer("table"), rich, layer("chalice", withPrevious: true)],
                          settings: LayeredSettings(advance: .eachStep, baseLevel: 30, context: .spotlight, camera: .push, zoom: 2))
        let show = Show(title: "T", cues: [cue])
        #expect(show.version == 7 && Show.formatVersion >= 7)
        let back = try JSONDecoder().decode(Show.self, from: try JSONEncoder().encode(show))
        #expect(back.cues == [cue])
        #expect(Show(title: "T", cues: [Cue(content: .blank(BlankContent()))]).version < 7)
    }

    @Test("show.json reads by hand: kind, src for the base, and a layers array")
    func readable() throws {
        let json = #"{"kind":"layered","num":"3","text":"X","src":"media/b.png","layers":[{"src":"media/a.png","life":"untilNextGo"}]}"#
        let cue = try JSONDecoder().decode(Cue.self, from: Data(json.utf8))
        #expect(cue.kind == .layered && cue.kind.name == "layered image" && cue.text == "X" && cue.sub == "")
        #expect(content(cue).base == "media/b.png" && content(cue).layers.first?.life == .untilNextGo)
        let text = String(decoding: try JSONEncoder().encode(layered([layer("a")])), as: UTF8.self)
        #expect(text.contains("\"kind\":\"layered\"") && !text.contains("withPrevious") && !text.contains("blend"))
    }

    @Test("Decoding clamps what is out of range")
    func clamps() throws {
        let json = #"{"kind":"layered","layers":[{"src":"a","level":500,"fadeMs":1}],"settings":{"baseLevel":900,"zoom":99}}"#
        let c = content(try JSONDecoder().decode(Cue.self, from: Data(json.utf8)))
        #expect(c.layers[0].level == 100 && c.layers[0].fadeMs == 100)
        #expect(c.settings.baseLevel == 100 && c.settings.zoom == SettingRange.mapZoom.upperBound)
    }

    @Test("mediaPaths covers the base and every layer, so Remove Unused Media keeps them")
    func mediaPaths() {
        let cue = layered([layer("a"), layer("b"), ImageLayer(src: "")])
        #expect(cue.mediaPaths == ["media/base.png", "media/a.png", "media/b.png"])
        #expect(Cue(content: .layered(LayeredContent())).mediaPaths.isEmpty)
    }
}

@Suite("Layered image cues: the step list")
struct LayeredStepTests {
    func names(_ c: LayeredContent) -> [String] { c.steps.map(\.name) }

    @Test("A plain cue has a step for each layer")
    func plain() {
        let c = content(layered([layer("table"), layer("jesus"), layer("hands")]))
        #expect(names(c) == ["table", "jesus", "hands"])
        #expect(c.steps.map(\.arriving) == [[0], [1], [2]] && c.steps.allSatisfy { $0.leaving.isEmpty })
        #expect((-1...3).map { c.layers(after: $0) } == [[], [0], [0, 1], [0, 1, 2], [0, 1, 2]])
    }

    @Test("withPrevious puts two layers on one step")
    func withPrevious() {
        let c = content(layered([layer("table"), layer("hands"), layer("line", withPrevious: true), layer("M")]))
        #expect(names(c) == ["table", "hands + line", "M"])
        #expect(c.steps.map(\.arriving) == [[0], [1, 2], [3]])
        #expect(c.layers(after: 1) == [0, 1, 2])
    }

    @Test("A layer until the next layer leaves as the next arrives, on one GO")
    func untilNextLayer() {
        let c = content(layered([layer("table"), layer("chalice", life: .untilNextLayer), layer("robe"), layer("hands")]))
        #expect(names(c) == ["table", "chalice", "robe (chalice goes)", "hands"])
        #expect(c.steps[2].leaving == [1] && c.steps[2].arriving == [2])
        #expect(c.steps.map(\.sheetName) == ["table", "chalice", "robe (\u{2715} chalice)", "hands"])
        #expect(c.layers(after: 1) == [0, 1] && c.layers(after: 2) == [0, 2] && c.layers(after: 3) == [0, 2, 3])
    }

    @Test("A layer until the next GO goes on a step of its own, with its own cue point")
    func untilNextGo() {
        let c = content(layered([layer("table"), layer("chalice", life: .untilNextGo, exit: "there is no chalice"), layer("robe")]))
        #expect(names(c) == ["table", "chalice", "chalice goes", "robe"])
        #expect(c.steps[2].isWithdrawal && c.steps[2].cuePoint == "there is no chalice")
        #expect(c.steps[2].sheetName == "\u{2715} chalice")
        #expect(c.layers(after: 1) == [0, 1] && c.layers(after: 2) == [0] && c.layers(after: 3) == [0, 2])
    }

    @Test("Until the next layer, on the last layer, gets a final step of its own rather than standing for ever")
    func lastLayerEdge() {
        let c = content(layered([layer("table"), layer("chalice", life: .untilNextLayer, exit: "no chalice")]))
        #expect(names(c) == ["table", "chalice", "chalice goes"])
        #expect(c.steps[2].cuePoint == "no chalice" && c.layers(after: 2) == [0])
        // Two such layers leave together.
        let two = content(layered([layer("a", life: .untilNextLayer), layer("b", withPrevious: true, life: .untilNextLayer)]))
        #expect(two.steps.last?.leaving == [0, 1] && two.layers(after: two.steps.count - 1).isEmpty)
    }

    @Test("A false step between withPrevious groups")
    func falseStepAmongGroups() {
        let c = content(layered([
            layer("a"), layer("b", withPrevious: true),
            layer("x", life: .untilNextGo), layer("y", withPrevious: true),
            layer("z"),
        ]))
        #expect(names(c) == ["a + b", "x + y", "x goes", "z"])
        #expect((0..<4).map { c.layers(after: $0) } == [[0, 1], [0, 1, 2, 3], [0, 1, 3], [0, 1, 3, 4]])
    }

    @Test("The standing set depends on the step alone, forwards or backwards")
    func pathIndependent() {
        let c = content(layered([layer("t"), layer("c", life: .untilNextGo), layer("r", life: .untilNextLayer), layer("h"), layer("m", life: .untilNextLayer)]))
        let forwards = (-1..<c.steps.count).map { c.layers(after: $0) }
        let backwards = (-1..<c.steps.count).reversed().map { c.layers(after: $0) }.reversed()
        #expect(forwards == Array(backwards))
        #expect(c.layers(after: 99) == c.layers(after: c.steps.count - 1))
    }

    @Test("No layers, no steps")
    func empty() {
        let c = LayeredContent()
        #expect(c.steps.isEmpty && c.layers(after: 0).isEmpty && c.goPoints(eachStepOnGO: true).isEmpty)
    }
}

@Suite("Layered image cues: GOs and cue points")
struct LayeredGoTests {
    /// A cue that waits for GO before each step.
    func onGo(_ cue: Cue) -> Cue {
        var cue = cue
        SettingKey.advance.set(.advance(.eachStep), in: &cue)
        return cue
    }

    @Test("A cue that moves on by itself has no GO points; on GO, one for each step")
    func goPoints() {
        let plain = layered([layer("table", cue: "Look at the table"), layer("chalice", life: .untilNextGo, exit: "No chalice"), layer("robe")])
        #expect(plain.goPoints().isEmpty)
        let cue = onGo(plain)
        let points = cue.goPoints()
        #expect(points.map(\.text) == ["table", "chalice", "chalice goes", "robe"] && points.allSatisfy { $0.unit == .layer })
        #expect(points.map(\.cuePoint) == ["Look at the table", "", "No chalice", ""])
        #expect(cue.hasGoCuePoints)
        #expect(!layered([layer("a")]).hasGoCuePoints)
    }

    @Test("A cue point set on a step lands on the layer that arrives, or on the one that goes")
    func setCuePoint() {
        var cue = onGo(layered([layer("table"), layer("hands", withPrevious: true), layer("chalice", life: .untilNextGo), layer("robe")]))
        // Steps: table + hands, chalice, chalice goes, robe.
        cue.setCuePoint("  The table  ", ofGoPoint: 0)
        cue.setCuePoint("There is no chalice", ofGoPoint: 2)
        cue.setCuePoint("Robe", ofGoPoint: 3)
        let c = content(cue)
        #expect(c.layers.map(\.cuePoint) == ["The table", "", "", "Robe"])
        #expect(c.layers[2].exitCuePoint == "There is no chalice")
        cue.setCuePoint("", ofGoPoint: 2)
        #expect(content(cue).layers[2].exitCuePoint.isEmpty)
        // On its own it has no GOs to set.
        var byItself = layered([layer("a")])
        byItself.setCuePoint("x", ofGoPoint: 0)
        #expect(content(byItself).layers[0].cuePoint.isEmpty)
    }

    @Test("Layers move and go in single operations")
    func reorder() {
        var c = content(layered([layer("a"), layer("b"), layer("c")]))
        c.moveLayer(from: 0, to: 2)
        #expect(c.layers.map(\.name) == ["b", "c", "a"])
        c.removeLayer(at: 1)
        #expect(c.layers.map(\.name) == ["b", "a"])
    }
}

@Suite("Layered image cues: settings")
struct LayeredSettingsTests {
    @Test("A cue's settings start at the built-in values, and each can be changed")
    func values() {
        let c = LayeredSettings(baseLevel: 40, entrance: .settle, zoom: 2)
        #expect(c.layerMs == 800 && c.baseLevel == 40 && c.entrance == .settle && c.zoom == 2)
        #expect(c.context == .desaturate && c.camera == .still && !c.eachStepOnGO)
        #expect(LayeredSettings(advance: .eachStep).eachStepOnGO)
    }

    @Test("A cue's settings are written in full, and a short file fills in the rest")
    func coding() throws {
        var cue = layered([])
        SettingKey.baseLevel.set(.number(0), in: &cue)
        SettingKey.push.set(.push(.push), in: &cue)
        let back = try JSONDecoder().decode(Cue.self, from: try JSONEncoder().encode(cue))
        #expect(content(back).settings.baseLevel == 0 && content(back).settings.camera == .push && content(back).settings.layerMs == 800)
        let json = Data(#"{ "kind": "layered", "num": "1", "settings": { "baseLevel": 10 } }"#.utf8)
        let short = content(try JSONDecoder().decode(Cue.self, from: json)).settings
        #expect(short == LayeredSettings(baseLevel: 10))
    }

    @Test("The new keys read, choose and set like the others")
    func keys() {
        #expect(SettingKey.layered.allSatisfy { $0.applies(to: .layered) })
        #expect(SettingKey.layered.allSatisfy { !$0.applies(to: .image) || SettingKey.image.contains($0) })
        #expect(SettingKey.baseLevel.format(.number(25)) == "25%" && SettingKey.baseLevel.format(.number(0)) == "black")
        #expect(SettingKey.layerTime.format(.number(800)) == "0.8 s")
        #expect(SettingKey.context.format(.context(.desaturate)) == "desaturate")
        #expect(SettingKey.push.choice(at: 1) == .push(.push) && SettingKey.push.choiceIndex(of: .push(.travel)) == 2)
        #expect(SettingKey.entrance.choiceIndex(of: .entrance(.bloom)) == 3)
        #expect(SettingKey.advance.choices(for: .layered).map(\.label) == ["By itself", "Each step on GO"])
        #expect(SettingKey.advance.format(.advance(.eachStep), for: .layered) == "each step on GO")
        #expect(SettingKey.advance.help.contains("layered image"))
        #expect(SettingKey.pause.help.contains("layered image"))
        #expect(SettingKey.zoom.help.contains("layered image"))
        #expect(SettingKey.groups.contains { $0.name == "Layered image cues" && $0.keys.contains(.push) })

        var cue = layered([])
        SettingKey.baseLevel.set(.number(33), in: &cue)
        SettingKey.context.set(.context(.dim), in: &cue)
        SettingKey.push.set(.push(.travel), in: &cue)
        SettingKey.zoom.set(.number(2), in: &cue)
        #expect(content(cue).settings == LayeredSettings(baseLevel: 35, context: .dim, camera: .travel, zoom: 2), "snapped to its step of 5")
        #expect(SettingKey.baseLevel.value(in: cue) == .number(35))

        SettingKey.strength.set(.number(80), in: &cue)
        SettingKey.length.set(.number(10), in: &cue)
        SettingKey.move.set(.number(2000), in: &cue)
        SettingKey.entrance.set(.entrance(.bloom), in: &cue)
        let s = content(cue).settings
        #expect(s.contextLevel == 80 && s.contextTicks == 10 && s.cameraMs == 2000 && s.entrance == .bloom)
    }
}

@Suite("Layered image cues: the sheet")
struct LayeredSheetTests {
    @Test("The cue's lines are its name and its steps joined by arrows, a withdrawal marked")
    func lines() {
        let cue = layered([layer("the table"), layer("Jesus"), layer("the chalice", life: .untilNextGo), layer("John")])
        let show = Show(title: "T", cues: [cue])
        let sheet = CueSheet(show: show, title: "T", layout: .dsm)
        #expect(sheet.rows[0].content == ["Last Supper", "the table \u{2192} Jesus \u{2192} the chalice \u{2192} \u{2715} the chalice \u{2192} John"])
        #expect(sheet.rows[0].type == "Layered Image")
    }

    @Test("Each GO has a row of its own in the DSM's book when the cue waits for GO")
    func goRows() {
        let show = Show(title: "T", cues: [layered([layer("a", cue: "line a"), layer("b")], settings: LayeredSettings(advance: .eachStep))])
        let rows = CueSheet(show: show, title: "T", layout: .dsm).rows
        #expect(rows.count == 3 && rows[1].go == 1 && rows[1].cuePoint == "line a" && rows[2].content == ["b"])
    }

    @Test("The operator's sheet lists a line per layer and the settings, with a false step shown")
    func settingsBlock() {
        var hands = layer("hands", cue: "")
        hands.level = 60
        hands.blend = .screen
        let cue = layered([layer("table"), hands, layer("chalice", life: .untilNextGo)], settings: LayeredSettings(baseLevel: 30))
        let rows = CueSheet(show: Show(title: "T", cues: [cue]), title: "T", layout: .operatorSettings).rows
        let settings = rows[0].settings
        #expect(settings.first { $0.name == "Base picture" }?.value == "30%")
        #expect(settings.first { $0.name == "Base" }?.value == "base.png")
        #expect(settings.first { $0.name == "Layer 2" }?.value == "hands \u{00B7} hands.png \u{00B7} 60% \u{00B7} screen")
        #expect(settings.first { $0.name == "Layer 3" }?.value.hasSuffix("goes on its own GO") == true)
    }

    @Test("A layered cue with no layers, or a layer with no picture, is flagged")
    func issues() {
        var show = Show(title: "T", cues: [layered([]), layered([ImageLayer(), layer("ok")])])
        show.cues[1].number = "10"
        let issues = show.issues
        #expect(issues.contains(.layeredWithoutLayers(cue: show.cues[0].id)))
        #expect(issues.contains(.layerWithoutPicture(cue: show.cues[1].id, layer: 0)))
        #expect(!issues.contains(.layerWithoutPicture(cue: show.cues[1].id, layer: 1)))
        #expect(show.message(for: .layerWithoutPicture(cue: show.cues[1].id, layer: 0)).contains("Layer 1"))
    }
}

@Suite("Layered image cues: the frame")
struct LayeredFramingTests {
    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> PictureRect { PictureRect(x: x, y: y, width: w, height: h) }
    func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    @Test("A frame is padded, square in shares, and kept on the picture")
    func fitting() {
        let f = LayeredFraming.frame(framing: rect(0.4, 0.4, 0.2, 0.1), zoom: 8)
        #expect(close(f.width, 0.2 * 1.16) && f.width == f.height, "padded by 8% a side, sized by the longer side")
        #expect(close(f.x + f.width / 2, 0.5) && close(f.y + f.height / 2, 0.45))
        let corner = LayeredFraming.frame(framing: rect(0, 0, 0.1, 0.1), zoom: 8)
        #expect(corner.x == 0 && corner.y == 0, "pushed back onto the picture")
        let far = LayeredFraming.frame(framing: rect(0.95, 0.9, 0.05, 0.1), zoom: 8)
        #expect(close(far.x + far.width, 1) && close(far.y + far.height, 1))
    }

    @Test("The zoom caps how close the frame comes")
    func cap() {
        #expect(LayeredFraming.frame(framing: rect(0.5, 0.5, 0.01, 0.01), zoom: 2).width == 0.5)
        #expect(LayeredFraming.frame(framing: rect(0.5, 0.5, 0.01, 0.01), zoom: 4).width == 0.25)
        #expect(LayeredFraming.frame(framing: rect(0, 0, 1, 1), zoom: 2) == LayeredFraming.whole, "a part spanning the picture barely moves it")
    }

    @Test("The frame at each step follows the part, a withdrawal keeping the one before, forwards and back")
    func perStep() {
        var a = ImageLayer(src: "a")
        a.frame = rect(0.1, 0.1, 0.2, 0.2)
        let c = LayeredContent(layers: [a, ImageLayer(src: "b", life: .untilNextGo), ImageLayer(src: "c"), ImageLayer(src: "d")])
        let bounds: [PictureRect?] = [rect(0.9, 0.9, 0.1, 0.1), rect(0.5, 0.5, 0.2, 0.2), nil, rect(0.6, 0.1, 0.2, 0.2)]
        let frames = c.frames(bounds: bounds, camera: .push, zoom: 4)
        // Steps: a, b, b goes, c, d. The layer's own frame beats its bounds.
        #expect(frames.count == 5)
        #expect(close(frames[0].x + frames[0].width / 2, 0.2))
        #expect(close(frames[1].x + frames[1].width / 2, 0.6))
        #expect(frames[2] == frames[1], "pulls back to whatever the step before framed")
        #expect(frames[3] == frames[2], "a part with no bounds leaves the frame where it was")
        #expect(close(frames[4].x + frames[4].width / 2, 0.7))
        #expect((-1..<5).map { c.frame(after: $0, frames: frames) } == [LayeredFraming.whole] + frames)
        #expect(c.frames(bounds: bounds, camera: .still, zoom: 4).allSatisfy { $0 == LayeredFraming.whole })
    }
}

@Suite("Layered image cues: recorded outputs")
struct LayeredRecordedTests {
    static let steps = (try? Fixtures.load("layered-steps", as: LayeredStepsFixture.self).cases) ?? []

    @Test("The step list for each recorded cue, and the layers standing at every step, forwards and backwards", arguments: steps)
    func recordedSteps(_ recorded: LayeredStepsFixture.Case) {
        let layers = recorded.layers.map {
            ImageLayer(src: "\($0.name).png", name: $0.name, cuePoint: $0.cuePoint, exitCuePoint: $0.exitCuePoint,
                       withPrevious: $0.withPrevious, life: LayerLife(rawValue: $0.life) ?? .stays)
        }
        let content = LayeredContent(layers: layers)
        let steps = content.steps
        #expect(steps.count == recorded.steps.count)
        for (step, want) in zip(steps, recorded.steps) {
            #expect(step.arriving == want.arriving && step.leaving == want.leaving, "\(want.name)")
            #expect(step.name == want.name && step.sheetName == want.sheetName && step.cuePoint == want.cuePoint)
        }
        // Reached forwards from the start, then backwards from the end.
        let range = -1..<steps.count
        #expect(range.map { content.layers(after: $0) } == recorded.standing)
        #expect(range.reversed().map { content.layers(after: $0) } == recorded.standing.reversed())
        // However the steps are reached, the picture at one is the same.
        for k in range { #expect(content.layers(after: k) == recorded.standing[k + 1]) }
    }

    @Test("The sheet for a cue with a false step, in both layouts, as recorded")
    func recordedSheet() throws {
        let recorded = try Fixtures.load("layered-sheet", as: LayeredSheetFixture.self)
        let layers = [
            ImageLayer(src: "media/table.png", name: "the table", cuePoint: "Look at the table"),
            ImageLayer(src: "media/hands.png", name: "the hands", cuePoint: "His hands", level: 60, blend: .screen),
            ImageLayer(src: "media/chalice.png", name: "the chalice", cuePoint: "A chalice", exitCuePoint: "No chalice", life: .untilNextGo),
            ImageLayer(src: "media/john.png", name: "John", life: .untilNextLayer),
            ImageLayer(src: "media/m.png", name: "the M", fadeMs: 1500),
        ]
        let show = Show(title: "Da Vinci", cues: [Cue(number: "9", line: "Sophie looks up", content: .layered(
            LayeredContent(text: "Last Supper", base: "media/base.png", layers: layers,
                           settings: LayeredSettings(advance: .eachStep, baseLevel: 30))))])
        for (layout, want) in [(CueSheet.Layout.dsm, recorded.dsm), (.operatorSettings, recorded.operator)] {
            let rows = CueSheet(show: show, title: "T", layout: layout).rows
            #expect(rows.count == want.count)
            for (row, recordedRow) in zip(rows, want) {
                #expect(row.number == recordedRow.number && row.type == recordedRow.type && row.content == recordedRow.content)
                #expect(row.cuePoint == recordedRow.cuePoint && (row.go ?? 0) == recordedRow.go)
                #expect(row.settings.map { [$0.name, $0.value] } == recordedRow.settings.map { [$0.name, $0.value] })
            }
        }
    }
}
