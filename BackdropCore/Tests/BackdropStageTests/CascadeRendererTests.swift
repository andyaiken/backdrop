import AppKit
import BackdropCore
import CoreText
import QuartzCore
import Testing
@testable import BackdropStage

@Suite("Cascade renderer", .serialized)
@MainActor
struct CascadeRendererTests {
    let renderer = CascadeRenderer(random: SeededRandom(seed: 3))
    let runner: StageRunner
    let live = surface(width: 640, height: 360)

    init() {
        runner = StageRunner(renderers: [.cascade: renderer])
        runner.attach(live)
    }

    func cue(_ text: String = "WAKE UP", colour: RGB = CascadeContent.green, _ settings: CascadeSettings = .init()) -> Cue {
        Cue(number: "1", content: .cascade(CascadeContent(text: text, colour: colour, settings: settings)))
    }

    /// Seconds into a cue, at its clock, `ticks` frames after the hold.
    func time(_ ticks: Int, _ settings: CascadeSettings = .init()) -> Double {
        Double(settings.holdTicks + ticks) * Double(settings.clockMs) / 1000
    }

    /// The share of pixels that aren't black, in a box.
    func lit(_ shot: Bitmap, in box: CGRect? = nil) -> Double {
        let box = box ?? CGRect(x: 0, y: 0, width: shot.width, height: shot.height)
        var count = 0, all = 0
        for y in stride(from: Int(box.minY), to: Int(box.maxY), by: 2) {
            for x in stride(from: Int(box.minX), to: Int(box.maxX), by: 2) {
                all += 1
                if !shot.isBlack(x: x, y: y) { count += 1 }
            }
        }
        return Double(count) / Double(max(all, 1))
    }

    @Test("Every glyph the rain falls in is Hiragino Sans's own")
    func rainFontCovers() throws {
        let font = try #require(NSFont(name: CascadeRenderer.rainFontName, size: 40)) as CTFont
        let coverage = StageFont.coverage(of: CascadeContent.glyphs, in: font)
        #expect(coverage.missing.isEmpty, "No glyph for \(coverage.missing)")
    }

    @Test("Rain falls in the cue's colour, over the whole picture")
    func rain() {
        runner.load(cue(""), show: ShowSettings(), presentation: .run, at: 0)
        _ = runner.tick(at: time(150))
        let shot = render(live)
        shot.save("cascade-rain")
        let share = lit(shot)
        #expect(share > 0.04 && share < 0.6, "rain, not a wall of it: \(share)")
        // Rain in the top, middle and bottom thirds alike.
        for third in 0..<3 {
            #expect(lit(shot, in: CGRect(x: 0, y: third * 120, width: 640, height: 120)) > 0.02, "third \(third)")
        }
        // Green, mostly.
        var green = 0, other = 0
        for y in stride(from: 0, to: 360, by: 3) {
            for x in stride(from: 0, to: 640, by: 3) where !shot.isBlack(x: x, y: y) {
                let p = shot.pixel(x: x, y: y)
                if p.g > p.r && p.g > p.b { green += 1 } else { other += 1 }
            }
        }
        #expect(green > other * 4, "\(green) green, \(other) not")
        #expect(runner.isRunning, "rain alone never settles")
    }

    @Test("The rain is drawn in any colour")
    func colour() {
        runner.load(cue("", colour: RGB(0xFF, 0x90, 0x00)), show: ShowSettings(), presentation: .run, at: 0)
        _ = runner.tick(at: time(150))
        let shot = render(live)
        shot.save("cascade-amber")
        var amber = 0, other = 0
        for y in stride(from: 0, to: 360, by: 3) {
            for x in stride(from: 0, to: 640, by: 3) where !shot.isBlack(x: x, y: y) {
                let p = shot.pixel(x: x, y: y)
                if p.r >= p.g && p.g >= p.b { amber += 1 } else { other += 1 }
            }
        }
        #expect(amber > other * 4, "\(amber) amber, \(other) not")
    }

    @Test("The message comes out of the rain and settles alone, in the middle")
    func message() throws {
        let c = cue("WAKE UP\nNEO", CascadeSettings(density: 90))
        runner.load(c, show: ShowSettings(), presentation: .run, at: 0)
        _ = runner.tick(at: time(-1))
        render(live).save("cascade-before")
        _ = runner.tick(at: time(16))
        render(live).save("cascade-partway")
        var settled: UUID?
        var t = time(0)
        while settled == nil, t < 60 {
            t += 0.044
            settled = runner.tick(at: t) ?? settled
        }
        #expect(settled == c.id)
        let shot = render(live)
        shot.save("cascade-message")
        // The words in the middle, and nothing round them.
        #expect(lit(shot, in: CGRect(x: 220, y: 140, width: 200, height: 80)) > 0.05)
        #expect(lit(shot, in: CGRect(x: 0, y: 0, width: 640, height: 100)) == 0)
        #expect(lit(shot, in: CGRect(x: 0, y: 260, width: 640, height: 100)) == 0)
        #expect(lit(shot, in: CGRect(x: 0, y: 0, width: 150, height: 360)) == 0)
        let frame = try #require(renderer.current)
        #expect(frame.isSettled && frame.glyphs.isEmpty && String(frame.letters.map(\.character)) == "WAKEUPNEO")
    }

    @Test("On GO, the rain falls until GO, then the message comes")
    func onGO() {
        let settings = CascadeSettings(advance: .eachStep)
        let c = cue("HI", settings)
        runner.load(c, show: ShowSettings(), presentation: .run, at: 0)
        // Well past where it would have come by itself.
        var t = 0.0
        while t < 20 {
            t += 0.044
            #expect(runner.tick(at: t) == nil)
        }
        #expect(runner.isRunning, "still raining, so still ticking")
        #expect(renderer.current?.letters.isEmpty == true)
        runner.carryOn(at: t)
        var settled: UUID?
        while settled == nil, t < 60 {
            t += 0.044
            settled = runner.tick(at: t) ?? settled
        }
        #expect(settled == c.id && renderer.current?.letters.count == 2)
    }

    @Test("Rain put up finished keeps falling; a message put up finished is still")
    func putUpFinished() {
        runner.redraw(cue(""), show: ShowSettings(), at: 0)
        #expect(runner.needsTicks && runner.isRunning)
        let full = render(live)
        #expect(lit(full) > 0.04, "already raining")
        _ = runner.tick(at: 0.5)
        let first = renderer.current
        _ = runner.tick(at: 1)
        #expect(renderer.current != first, "and falling")
        #expect(lit(render(live)) > 0.04, "full from the start, not falling in from the top")

        runner.redraw(cue("WAKE UP"), show: ShowSettings(), at: 2)
        #expect(!runner.needsTicks && !runner.isRunning)
        #expect(renderer.current?.isSettled == true && renderer.current?.letters.count == 6)
    }

    @Test("Rain after a message fills the picture: the letters leave nothing behind that moves it")
    func rainAfterMessage() {
        // The same surface draws both, as the console's preview does when a
        // message is cleared and the cue run again.
        live.contentsScale = 2
        runner.redraw(cue("WAKE UP\nNEO"), show: ShowSettings(), at: 0)
        runner.load(cue(""), show: ShowSettings(), presentation: .run, at: 1)
        _ = runner.tick(at: 1 + time(150))
        let shot = render(live)
        shot.save("cascade-rain-after-message")
        #expect(lit(shot, in: CGRect(x: 0, y: 260, width: 640, height: 100)) > 0.02, "rain at the bottom too")
        #expect(lit(shot, in: CGRect(x: 0, y: 0, width: 200, height: 360)) > 0.02, "and at the left")
    }

    @Test("Rain stays inside the projection area: nothing lands on the set round it")
    func staysInside() {
        let pulledIn = surface(width: 640, height: 360)
        pulledIn.contentsScale = 2
        runner.attach(pulledIn)
        // The show's projection area, which the runner gives every surface.
        runner.geometry = Geometry(width: 80, height: 70, across: 4, down: -6)
        #expect(abs(pulledIn.inset.frame.width - 512) < 0.5 && abs(pulledIn.inset.frame.height - 252) < 0.5)
        runner.load(cue("", CascadeSettings(density: 100, streak: 40)), show: ShowSettings(), presentation: .run, at: 0)
        _ = runner.tick(at: time(300))
        let shot = render(pulledIn)
        shot.save("cascade-pulled-in")
        let inset = pulledIn.inset.frame
        // Layers count up from the bottom; the bitmap from the top.
        let top = Int(360 - inset.maxY), bottom = Int(360 - inset.minY)
        #expect(lit(shot, in: CGRect(x: Int(inset.minX), y: top, width: Int(inset.width), height: bottom - top)) > 0.1)
        for y in stride(from: 0, to: 360, by: 2) {
            for x in stride(from: 0, to: 640, by: 2) where !(Int(inset.minX)...Int(inset.maxX)).contains(x) || !(top...bottom).contains(y) {
                if !shot.isBlack(x: x, y: y) { Issue.record("lit outside the area at \(x), \(y)"); return }
            }
        }
        runner.detach(pulledIn)
    }

    @Test("Every surface shows the same rain")
    func surfacesAgree() {
        let preview = surface(width: 640, height: 360, role: .preview)
        runner.attach(preview)
        runner.load(cue(""), show: ShowSettings(), presentation: .run, at: 0)
        _ = runner.tick(at: time(90))
        let a = render(live), b = render(preview)
        var differ = 0
        for y in stride(from: 0, to: 360, by: 2) {
            for x in stride(from: 0, to: 640, by: 2) where a.pixel(x: x, y: y) != b.pixel(x: x, y: y) { differ += 1 }
        }
        #expect(differ == 0)
        runner.detach(preview)
    }

    @Test("Drawing a frame of rain across a big projector is quick enough to keep up")
    func quick() {
        let big = surface(width: 1920, height: 1080)
        let renderer = CascadeRenderer(random: SeededRandom(seed: 3))
        let runner = StageRunner(renderers: [.cascade: renderer])
        runner.attach(big)
        runner.redraw(cue("", CascadeSettings(columns: 120, density: 100, streak: 40)), show: ShowSettings(), at: 0)
        let start = CACurrentMediaTime()
        for f in 0..<20 { _ = renderer.frame(f) }
        let each = (CACurrentMediaTime() - start) / 20
        render(big).save("cascade-dense")
        // A frame lasts 44 ms at the usual clock; a debug build gets slack.
        #expect(each < 0.044, "\(Int(each * 1000)) ms a frame")
    }
}
