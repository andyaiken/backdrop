import Foundation
import Testing
@testable import ProspectCore

@Suite("Setting keys")
struct SettingKeyTests {
    @Test("Every setting reads and writes the cue's own value")
    func values() {
        var cue = Cue(content: .image(ImageContent(text: "GALLERY")))
        let values: [SettingKey: SettingValue] = [
            .clock: .number(30), .wave: .number(5), .hold: .number(10),
            .grid: .number(20), .flip: .number(600), .order: .order(.random),
        ]
        for (key, value) in values { key.set(value, in: &cue) }
        for (key, value) in values { #expect(key.value(in: cue) == value, "\(key)") }
        guard case .image(let c) = cue.content else { return }
        #expect(c.settings.clockMs == 30 && c.settings.gridColumns == 20 && c.settings.order == .random)
    }

    @Test("Values snap to the slider's range and step")
    func snapping() {
        #expect(SettingKey.clock.snapped(.number(31)) == .number(32), "18, 20 ... 30, 32")
        #expect(SettingKey.clock.snapped(.number(500)) == .number(110))
        #expect(SettingKey.flip.snapped(.number(400)) == .number(390), "150, 180 ... 390, 420")
        #expect(SettingKey.grid.snapped(.number(2)) == .number(4))
        #expect(SettingKey.histogram.snapped(.flag(true)) == .flag(true))
    }

    @Test("A title cue sets its timing and title settings")
    func titleSettings() {
        var cue = Cue(content: .title(TitleContent(text: "THE LOUVRE")))
        #expect(SettingKey.hold.value(in: cue) == .number(44))

        SettingKey.hold.set(.number(4), in: &cue)
        SettingKey.sceneLine.set(.flag(false), in: &cue)
        SettingKey.grid.set(.number(20), in: &cue)
        #expect(SettingKey.hold.value(in: cue) == .number(4))
        #expect(SettingKey.sceneLine.value(in: cue) == .flag(false))
        #expect(SettingKey.grid.value(in: cue) == nil, "a title has no grid")
        guard case .title(let c) = cue.content else { return }
        #expect(c.settings == TitleSettings(holdTicks: 4, sceneLine: false))
    }

    @Test("An image cue sets its timing and grid settings")
    func imageSettings() {
        var cue = Cue(content: .image(ImageContent(text: "GALLERY")))
        SettingKey.order.set(.order(.random), in: &cue)
        SettingKey.flip.set(.number(605), in: &cue)
        SettingKey.histogram.set(.flag(false), in: &cue)
        guard case .image(let c) = cue.content else { return }
        #expect(c.settings == ImageSettings(flipMs: 600, order: .random), "snapped, and no histogram on an image")
    }

    @Test("Which settings apply to which cues")
    func applicability() {
        #expect(SettingKey.allCases.filter { $0.applies(to: .title) } == [.clock, .wave, .hold, .histogram, .sceneLine, .letters, .bars, .transition, .fade])
        #expect(SettingKey.allCases.filter { $0.applies(to: .image) } == [.clock, .wave, .hold, .grid, .flip, .order, .reveal, .transition, .fade])
        #expect(SettingKey.allCases.filter { $0.applies(to: .video) } == [.transition, .fade], "every cue has a transition in")
        #expect(SettingKey.allCases.filter { $0.applies(to: .blank) } == [.transition, .fade])
        #expect(SettingKey.groups.flatMap(\.keys) == SettingKey.allCases.filter { $0 != .textScale }, "the cue panels show every cue setting once")
    }

    @Test("Values read as the console writes them")
    func formatting() {
        #expect(SettingKey.clock.format(.number(44)) == "44 ms")
        #expect(SettingKey.hold.format(.number(0)) == "none")
        #expect(SettingKey.textScale.format(.number(100)) == "100%")
        #expect(SettingKey.grid.format(.number(12)) == "12 wide")
        #expect(SettingKey.histogram.format(.flag(true)) == "on")
        #expect(SettingKey.order.format(.order(.diagonal)) == "wave")
        #expect(SettingKey.order.format(.order(.spiral)) == "golden spiral")
        #expect(SettingKey.order.choice(at: 2) == .order(.spiral) && SettingKey.order.choiceIndex(of: .order(.spiral)) == 2)
        #expect(SettingKey.order.format(.order(.quarters)) == "quarters" && SettingKey.order.choice(at: 3) == .order(.quarters))
    }

    @Test("Every setting explains itself, and a hold says how long it lasts")
    func explanations() {
        #expect(SettingKey.allCases.allSatisfy { !$0.help.isEmpty })
        #expect(SettingKey.timingExplanation.contains("Clock") && SettingKey.timingExplanation.contains("hold")
                && SettingKey.timingExplanation.contains("wave"))
        #expect(SettingKey.holdLength(holdTicks: 44, clockMs: 44) == "1.9 s")
        #expect(SettingKey.holdLength(holdTicks: 10, clockMs: 100) == "1.0 s")
        #expect(SettingKey.holdLength(holdTicks: 0, clockMs: 44) == nil, "no hold, nothing to time")
    }

    @Test("Letters: cycling or dials, set on any decryption cue")
    func letters() throws {
        #expect(TitleSettings().letters == .cycle)
        #expect(SettingKey.letters.format(.letters(.dials)) == "dials")
        #expect(SettingKey.letters.choice(at: 1) == .letters(.dials) && SettingKey.letters.choiceIndex(of: .letters(.dials)) == 1)
        var cue = Cue(content: .title(TitleContent(text: "ROSSLYN")))
        SettingKey.letters.set(.letters(.dials), in: &cue)
        guard case .title(let content) = cue.content else { return }
        #expect(content.settings.letters == .dials)
        let back = try JSONDecoder().decode(Cue.self, from: JSONEncoder().encode(cue))
        #expect(SettingKey.letters.value(in: back) == .letters(.dials))
        #expect(!SettingKey.letters.applies(to: .image) && !SettingKey.letters.applies(to: .anagram))
    }

    @Test("Reveal: just show it, sharpen from one colour, or flip from black; set on any image cue")
    func revealBy() throws {
        #expect(ImageSettings().reveal == .flip)
        #expect(SettingKey.reveal.format(.reveal(.sharpen)) == "sharpen from one colour")
        #expect(SettingKey.reveal.format(.reveal(.flip)) == "flip from black" && SettingKey.reveal.format(.reveal(.show)) == "just show it")
        #expect([0, 1, 2].compactMap { SettingKey.reveal.choice(at: $0) } == [.reveal(.show), .reveal(.sharpen), .reveal(.flip)])
        var cue = Cue(content: .image(ImageContent(text: "GALLERY")))
        SettingKey.reveal.set(.reveal(.sharpen), in: &cue)
        guard case .image(let content) = cue.content else { return }
        #expect(content.settings.reveal == .sharpen)
        let back = try JSONDecoder().decode(Cue.self, from: try JSONEncoder().encode(cue))
        #expect(SettingKey.reveal.value(in: back) == .reveal(.sharpen))
        #expect(!SettingKey.reveal.applies(to: .title))
    }
}
