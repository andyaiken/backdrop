import BackdropCore
import QuartzCore
import Testing
@testable import BackdropStage

@Suite("Message renderer", .serialized)
@MainActor
struct SMSRendererTests {
    let runner = StageRunner(renderers: [.sms: SMSRenderer()])
    let live = surface(width: 640, height: 360)

    init() { runner.attach(live) }

    func fire(_ settings: SMSSettings, text: String = "Are you coming tonight?", from: String = "Mum") {
        let cue = Cue(number: "1", content: .sms(SMSContent(text: text, sub: from, settings: settings)))
        runner.load(cue, show: ShowSettings(), presentation: .run, at: 0)
    }

    /// The share of pixels that differ from the screen colour.
    func coverage(_ shot: Bitmap, screen: (r: UInt8, g: UInt8, b: UInt8)) -> Double {
        var count = 0
        for y in stride(from: 0, to: shot.height, by: 2) {
            for x in stride(from: 0, to: shot.width, by: 2) {
                let p = shot.pixel(x: x, y: y)
                if p.r != screen.r || p.g != screen.g || p.b != screen.b { count += 1 }
            }
        }
        return Double(count) / Double((shot.width / 2) * (shot.height / 2))
    }

    @Test("A message settles on a bubble in its place, and the arrival finishes")
    func settles() {
        fire(SMSSettings())
        _ = runner.tick(at: 10)
        let shot = render(live)
        shot.save("sms-blue-received")
        let c = coverage(shot, screen: (0, 0, 0))
        #expect(c > 0.01 && c < 0.4, "a bubble, not the whole screen: \(c)")
        // Received, so on the left; the right is empty.
        #expect(shot.isBlack(x: 600, y: 180))
    }

    @Test("Green bubbles are blue bubbles in green: the same shape, the sent bubble green")
    func greenBubbles() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 80)
        #expect(MessageLook.bubblePath(rect, style: .greenBubbles, sent: true, fontSize: 30)
                == MessageLook.bubblePath(rect, style: .blueBubbles, sent: true, fontSize: 30), "the same outline, tail and all")
        fire(SMSSettings(style: .greenBubbles, sent: true))
        _ = runner.tick(at: 10)
        let shot = render(live)
        shot.save("sms-green-sent")
        #expect(shot.isBlack(x: 40, y: 180))
        let p = shot.pixel(x: 560, y: 180)
        #expect(p.g > 150 && p.r < 90 && p.b < 120, "green bubble: \(p)")
        // Received, it is grey, as a blue bubbles message received is.
        fire(SMSSettings(style: .greenBubbles))
        _ = runner.tick(at: 10)
        let received = render(live).pixel(x: 100, y: 180)
        fire(SMSSettings(style: .blueBubbles))
        _ = runner.tick(at: 10)
        let blue = render(live).pixel(x: 100, y: 180)
        #expect(received == blue, "\(received) and \(blue)")
    }

    @Test("A sent message is on the right, in blue")
    func sent() {
        fire(SMSSettings(sent: true))
        _ = runner.tick(at: 10)
        let shot = render(live)
        shot.save("sms-blue-sent")
        #expect(shot.isBlack(x: 40, y: 180))
        let p = shot.pixel(x: 560, y: 180)
        #expect(p.b > 200 && p.r < 60, "blue bubble")
    }

    @Test("The pop starts off the screen's size and opens in, then rests at its size")
    func pop() {
        fire(SMSSettings(entrance: .pop, entranceMs: 1000))
        _ = runner.tick(at: 0.05)
        let early = render(live)
        early.save("sms-pop-early")
        _ = runner.tick(at: 10)
        let late = render(live)
        late.save("sms-pop-late")
        #expect(coverage(early, screen: (0, 0, 0)) != coverage(late, screen: (0, 0, 0)))
    }

    @Test("A cut is there at once; a light generic message is on white")
    func cutAndLight() {
        fire(SMSSettings(style: .generic, entrance: .cut, dark: false))
        _ = runner.tick(at: 0)
        let shot = render(live)
        shot.save("sms-generic-light")
        let p = shot.pixel(x: 600, y: 20)
        #expect(p.r == 255 && p.g == 255 && p.b == 255)
        #expect(coverage(shot, screen: (255, 255, 255)) > 0.01)
    }
}

extension SMSRendererTests {
    @Test("The zoom comes in small, grows past full size, and settles at it")
    func zoomShape() {
        fire(SMSSettings(entrance: .pop, entranceMs: 1000))
        var widths: [Double] = []
        for t in stride(from: 0.0, through: 1.2, by: 0.1) {
            _ = runner.tick(at: t)
            let shot = render(live)
            widths.append(coverage(shot, screen: (0, 0, 0)))
            shot.save("sms-zoom-\(Int(t * 10))")
        }
        let settled = widths.last!
        #expect(widths[1] < settled, "small near the start")
        #expect(widths.dropFirst(2).max()! > settled, "a little over full size on the way")
    }
}

@Suite("Conversation renderer", .serialized)
@MainActor
struct ConversationRendererTests {
    let runner = StageRunner(renderers: [.conversation: ConversationRenderer()])
    let live = surface(width: 640, height: 360)

    init() { runner.attach(live) }

    static let script = "< Are you coming tonight?\n> Yes, leaving now\n< Great, bring wine\nGO\n< Where are you?\n> Outside the door now"

    func fire(_ settings: ConversationSettings = .init(), script: String = ConversationRendererTests.script) {
        let cue = Cue(number: "1", content: .conversation(ConversationContent(text: "Chat", sub: "Mum", script: script, settings: settings)))
        runner.load(cue, show: ShowSettings(), presentation: .run, at: 0)
    }

    func lit(_ shot: Bitmap) -> Int {
        var count = 0
        for y in stride(from: 0, to: shot.height, by: 3) {
            for x in stride(from: 0, to: shot.width, by: 3) where !shot.isBlack(x: x, y: y) { count += 1 }
        }
        return count
    }

    @Test("The thread builds up message by message, then waits for GO")
    func buildsAndWaits() {
        fire()
        var counts: [Int] = []
        for (i, t) in [0.5, 1.5, 3.0, 6.0, 12.0].enumerated() {
            _ = runner.tick(at: t)
            let shot = render(live)
            shot.save("conversation-1-\(i)")
            counts.append(lit(shot))
        }
        #expect(counts.sorted() == counts, "more on screen as it goes: \(counts)")
        #expect(counts.last! > counts.first!)
        // Stopped at the GO: more time changes nothing.
        _ = runner.tick(at: 30)
        #expect(lit(render(live)) == counts.last!)
    }

    @Test("GO brings on the next stage")
    func goReleases() {
        fire()
        _ = runner.tick(at: 12)
        let before = lit(render(live))
        runner.carryOn(at: 12)
        for t in stride(from: 12.0, through: 24.0, by: 1.0) { _ = runner.tick(at: t) }
        let after = render(live)
        after.save("conversation-2-after-go")
        #expect(lit(after) > before)
    }

    @Test("With typing off, bubbles arrive without dots or a bar")
    func noTyping() {
        fire(ConversationSettings(style: .generic, dark: false, showTyping: false, pauseTicks: 4))
        _ = runner.tick(at: 12)
        let shot = render(live)
        shot.save("conversation-3-generic-light")
        let p = shot.pixel(x: 600, y: 20)
        #expect(p.r == 255 && p.g == 255 && p.b == 255)
    }

    @Test("Put up finished, the whole first run is there at once")
    func finished() {
        let cue = Cue(number: "1", content: .conversation(ConversationContent(text: "Chat", sub: "Mum", script: Self.script)))
        runner.load(cue, show: ShowSettings(), presentation: .settled, at: 0)
        let shot = render(live)
        shot.save("conversation-4-settled")
        #expect(lit(shot) > 500)
    }
}

extension ConversationRendererTests {
    @Test("A sent message is typed into the compose bar before it lifts into the thread")
    func composeBar() {
        fire()
        _ = runner.tick(at: 3.8)
        let shot = render(live)
        shot.save("conversation-5-composing")
        // Inside the bar at the bottom there is text, and the thread holds only the received message.
        var inBar = 0
        for x in stride(from: 50, to: 400, by: 2) where !shot.isBlack(x: x, y: 326) { inBar += 1 }
        #expect(inBar > 5, "typed text in the bar")
        #expect(shot.isBlack(x: 560, y: 150), "nothing sent in the thread yet")
    }
}

extension SMSRendererTests {
    @Test("A green rectangles message is on its green and wallpaper colours, sent or received")
    func greenRectangles() {
        fire(SMSSettings(style: .greenRectangles, entrance: .cut, dark: true, sent: true))
        _ = runner.tick(at: 0)
        let sent = render(live)
        sent.save("sms-rectangles-sent-dark")
        let screen = sent.pixel(x: 5, y: 5)
        #expect(screen.r == 0x0B && screen.g == 0x14 && screen.b == 0x1A)
        let bubble = sent.pixel(x: 560, y: 180)
        #expect(bubble.g > bubble.r && bubble.g > bubble.b && bubble.g > 60, "green bubble")
        fire(SMSSettings(style: .greenRectangles, entrance: .cut, dark: false))
        _ = runner.tick(at: 0)
        let light = render(live)
        light.save("sms-rectangles-received-light")
        let wallpaper = light.pixel(x: 600, y: 20)
        #expect(wallpaper.r == 0xEF && wallpaper.g == 0xEA && wallpaper.b == 0xE2)
    }
}

extension ConversationRendererTests {
    @Test("A green rectangles conversation draws, with the tail on the first of a run")
    func rectanglesConversation() {
        fire(ConversationSettings(style: .greenRectangles, dark: true, showTyping: false, pauseTicks: 4), script: "< one\n< two\n> three\n> four")
        _ = runner.tick(at: 12)
        let shot = render(live)
        shot.save("conversation-6-rectangles")
        #expect(lit(shot) > 500)
    }
}

extension SMSRendererTests {
    /// Pixels in the picture that aren't the screen's black, in the lower half.
    func litBelow(_ shot: Bitmap, y: Int) -> Int {
        var n = 0
        for yy in y..<shot.height { for x in stride(from: 0, to: shot.width, by: 1) where !shot.isBlack(x: x, y: yy) { n += 1 } }
        return n
    }

    @Test("In the text styles a sent message's status is written beneath the bubble")
    func statusLine() {
        fire(SMSSettings(entrance: .cut, sent: true, status: .none))
        _ = runner.tick(at: 0)
        let without = litBelow(render(live), y: 215)
        fire(SMSSettings(entrance: .cut, sent: true, status: .delivered))
        _ = runner.tick(at: 0)
        let shot = render(live)
        shot.save("sms-status-delivered")
        #expect(litBelow(shot, y: 215) > without + 20, "a line of text under the bubble")
        // A message received has none, whatever the setting.
        fire(SMSSettings(entrance: .cut, sent: false, status: .delivered))
        _ = runner.tick(at: 0)
        #expect(litBelow(render(live), y: 215) == without)
    }

    @Test("In green rectangles the status is ticks inside, blue once read")
    func rectanglesTicks() {
        func ticks(_ status: SMSStatus) -> (Bitmap, Int) {
            fire(SMSSettings(style: .greenRectangles, entrance: .cut, sent: true, status: status), text: "On my way")
            _ = runner.tick(at: 0)
            let shot = render(live)
            shot.save("sms-rectangles-\(status.rawValue)")
            var blue = 0
            for y in 0..<shot.height { for x in 300..<shot.width {
                let p = shot.pixel(x: x, y: y)
                if p.b > 180 && Int(p.b) > Int(p.r) + 60 { blue += 1 }
            } }
            return (shot, blue)
        }
        #expect(ticks(.delivered).1 == 0, "grey ticks, not blue")
        #expect(ticks(.read).1 > 10, "blue ticks")
        #expect(ticks(.sending).1 == 0)
    }
}

extension SMSRendererTests {
    func blueTicks(_ shot: Bitmap) -> Int {
        var blue = 0
        for y in 0..<shot.height { for x in 300..<shot.width {
            let p = shot.pixel(x: x, y: y)
            if p.b > 180 && Int(p.b) > Int(p.r) + 60 { blue += 1 }
        } }
        return blue
    }

    @Test("The status waits for GO, then fades to the next one")
    func statusOnGO() {
        fire(SMSSettings(style: .greenRectangles, entrance: .cut, sent: true, status: .delivered, advances: true), text: "On my way")
        _ = runner.tick(at: 1)
        #expect(blueTicks(render(live)) == 0)
        _ = runner.tick(at: 30)
        #expect(blueTicks(render(live)) == 0, "still waiting for GO")
        runner.carryOn(at: 30)
        for t in stride(from: 30.0, through: 31.0, by: 0.05) { _ = runner.tick(at: t) }
        let read = render(live)
        read.save("sms-status-advanced")
        #expect(blueTicks(read) > 10, "read, in blue")
    }

    @Test("Put up finished, a status that moves on with GO shows its last")
    func statusSettled() {
        let cue = Cue(number: "1", content: .sms(SMSContent(text: "On my way", settings: SMSSettings(style: .greenRectangles, entrance: .cut, sent: true, status: .sending, advances: true))))
        runner.load(cue, show: ShowSettings(), presentation: .settled, at: 0)
        #expect(blueTicks(render(live)) > 10)
    }
}
