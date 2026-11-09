import BackdropCore
import QuartzCore
import Testing
@testable import BackdropStage

func feedCue(_ settings: FeedSettings = FeedSettings(device: PatternCamera.deviceID, deviceName: "Test pattern"),
             number: String = "5") -> Cue {
    Cue(number: number, content: .feed(FeedContent(text: "ACTOR", settings: settings)))
}

/// The test card is red on the left, blue on the right, green in the top
/// left corner and white in the bottom right.
@Suite("Feed renderer", .serialized)
@MainActor
struct FeedRendererTests {
    let camera = PatternCamera()
    let renderer: FeedRenderer
    let runner: StageRunner
    let live = surface(width: 320, height: 180)
    let preview = surface(width: 160, height: 90, role: .preview)
    var problems = ProblemLog()

    final class ProblemLog { var messages: [String] = [] }

    init() {
        renderer = FeedRenderer(camera: camera)
        runner = StageRunner(renderers: [.feed: renderer, .blank: BlankRenderer()])
        runner.attach(live)
        runner.attach(preview)
        let log = problems
        renderer.onProblem = { log.messages.append($0) }
    }

    func fire(_ cue: Cue) {
        runner.load(cue, show: ShowSettings(), presentation: .run, at: 0)
    }

    func settings(mirror: Bool = false, rotation: FeedRotation = .none, fit: FeedFit = .fit, onLoss: FeedLoss = .black) -> FeedSettings {
        FeedSettings(device: PatternCamera.deviceID, deviceName: "Test pattern", mirror: mirror, rotation: rotation, fit: fit, onLoss: onLoss)
    }

    func isRed(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.r > 200 && p.g < 50 && p.b < 50 }
    func isBlue(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.b > 200 && p.r < 50 && p.g < 50 }
    func isGreen(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.g > 200 && p.r < 50 && p.b < 50 }
    func isWhite(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.r > 200 && p.g > 200 && p.b > 200 }

    @Test("A feed shows the camera's picture the right way up, and is armed")
    func showsThePicture() {
        let cue = feedCue(settings())
        fire(cue)
        let shot = render(live)
        #expect(isGreen(shot.pixel(x: 10, y: 10)), "top left")
        #expect(isWhite(shot.pixel(x: 310, y: 170)), "bottom right")
        #expect(isRed(shot.pixel(x: 100, y: 90)) && isBlue(shot.pixel(x: 250, y: 90)))
        #expect(renderer.armState(for: cue.id) == .armed)
        #expect(!runner.isRunning || runner.tick(at: 1) == nil, "a feed never settles by itself")
    }

    @Test("Mirror flips it left to right")
    func mirrors() {
        fire(feedCue(settings(mirror: true)))
        let shot = render(live)
        #expect(isGreen(shot.pixel(x: 310, y: 10)) && isWhite(shot.pixel(x: 10, y: 170)))
        #expect(isBlue(shot.pixel(x: 100, y: 90)) && isRed(shot.pixel(x: 250, y: 90)))
    }

    @Test("Turning is clockwise, and a quarter turn fits the narrower shape inside")
    func turns() {
        fire(feedCue(settings(rotation: .quarter)))
        var shot = render(live)
        // 9 by 16 now, in the middle of the frame, with black either side.
        #expect(shot.isBlack(x: 10, y: 90) && shot.isBlack(x: 310, y: 90))
        #expect(isGreen(shot.pixel(x: 200, y: 10)), "the top left has gone to the top right")
        #expect(isWhite(shot.pixel(x: 120, y: 170)), "the bottom right to the bottom left")
        #expect(isRed(shot.pixel(x: 160, y: 50)) && isBlue(shot.pixel(x: 160, y: 130)), "red from the left to the top")

        fire(feedCue(settings(rotation: .half)))
        shot = render(live)
        #expect(isGreen(shot.pixel(x: 310, y: 170)) && isWhite(shot.pixel(x: 10, y: 10)))

        fire(feedCue(settings(rotation: .threeQuarters)))
        shot = render(live)
        #expect(isGreen(shot.pixel(x: 120, y: 170)), "anticlockwise: the top left goes to the bottom left")
    }

    @Test("Mirroring is of the picture, before it is turned")
    func mirrorsThenTurns() {
        fire(feedCue(settings(mirror: true, rotation: .quarter)))
        let shot = render(live)
        // Mirrored the green corner is top right, and a clockwise quarter turn puts that bottom right.
        #expect(isGreen(shot.pixel(x: 200, y: 170)))
    }

    @Test("Fit keeps all of the picture; fill crops it to the area")
    func fitsAndFills() {
        let square = surface(width: 320, height: 320)
        runner.attach(square)
        fire(feedCue(settings(fit: .fit)))
        var shot = render(square)
        #expect(shot.isBlack(x: 100, y: 10), "bars above and below")
        #expect(isRed(shot.pixel(x: 100, y: 160)))
        fire(feedCue(settings(fit: .fill)))
        shot = render(square)
        #expect(isRed(shot.pixel(x: 100, y: 10)) && isBlue(shot.pixel(x: 250, y: 310)), "the area is filled")
    }

    @Test("The console preview shows the picture and says it is live")
    func previewReads() {
        fire(feedCue(settings()))
        let shot = render(preview)
        #expect(isRed(shot.pixel(x: 50, y: 40)))
        let tree = renderer.tree(for: preview)
        #expect(text(of: tree?.readout.runs ?? []) == "LIVE \u{2014} TEST PATTERN")
    }

    @Test("A crossfade out of the feed is given the picture as the audience sees it")
    func snapshotMatches() {
        fire(feedCue(settings(mirror: true, rotation: .half)))
        let image = renderer.snapshot(size: CGSize(width: 320, height: 180))
        #expect(image != nil)
        let at = pixels(of: image!, width: 320, height: 180)
        // The same picture the layers draw, point for point: mirrored then
        // turned a half, so the green corner is at the bottom left.
        let shot = render(live)
        for (x, y) in [(10, 10), (10, 170), (310, 10), (310, 170), (100, 90), (250, 90)] {
            let a = at(x, y), b = shot.pixel(x: x, y: y)
            #expect(abs(a.r - Int(b.r)) < 8 && abs(a.g - Int(b.g)) < 8 && abs(a.b - Int(b.b)) < 8, "at \(x), \(y)")
        }
        #expect(isGreen(shot.pixel(x: 10, y: 170)))
        #expect(renderer.snapshot(size: .zero) == nil)
    }

    @Test("A lost feed goes to black, says so, and comes back by itself")
    func lossAndRecovery() {
        let cue = feedCue(settings(onLoss: .black))
        fire(cue)
        let session = camera.sessions.last!
        session.stalled = true
        renderer.refresh()
        guard case .failed(let message) = renderer.armState(for: cue.id) else { Issue.record("not lost"); return }
        #expect(message.contains("Test pattern"))
        #expect(render(live).isBlack(x: 100, y: 90))
        #expect(problems.messages.last?.contains("Cue 5") == true && problems.messages.last?.contains("black") == true)
        #expect(text(of: renderer.tree(for: preview)?.readout.runs ?? []) == "NO SIGNAL \u{2014} BLACK")
        #expect(renderer.snapshot(size: CGSize(width: 320, height: 180)) == nil)

        session.stalled = false
        renderer.refresh()
        #expect(renderer.armState(for: cue.id) == .armed)
        #expect(isRed(render(live).pixel(x: 100, y: 90)))
    }

    @Test("A lost feed can hold the last picture instead")
    func holdsTheLastPicture() {
        let cue = feedCue(settings(onLoss: .hold))
        fire(cue)
        camera.sessions.last!.stalled = true
        renderer.refresh()
        #expect(isRed(render(live).pixel(x: 100, y: 90)), "still the last picture")
        #expect(renderer.snapshot(size: CGSize(width: 320, height: 180)) != nil)
        #expect(text(of: renderer.tree(for: preview)?.readout.runs ?? []) == "NO SIGNAL \u{2014} HOLDING LAST PICTURE")
    }

    @Test("A camera that isn't there is a failed cue that goes to black, and is tried again when one appears")
    func missingThenFound() {
        camera.present = false
        let cue = feedCue(settings())
        fire(cue)
        guard case .failed(let message) = renderer.armState(for: cue.id) else { Issue.record("should fail"); return }
        #expect(message == "Test pattern isn\u{2019}t connected.")
        #expect(render(live).isBlack(x: 100, y: 90))
        #expect(problems.messages.count == 1)

        camera.present = true
        #expect(renderer.armState(for: cue.id) == .armed, "the cable went back in")
        #expect(isRed(render(live).pixel(x: 100, y: 90)))
    }

    @Test("A cue with no camera chosen goes to black")
    func noCameraChosen() {
        let cue = feedCue(FeedSettings())
        fire(cue)
        #expect({ if case .failed = renderer.armState(for: cue.id) { true } else { false } }())
        #expect(render(live).isBlack(x: 100, y: 90))
    }

    @Test("Changing how a feed is turned doesn't restart the camera")
    func editsKeepTheCamera() {
        var cue = feedCue(settings())
        fire(cue)
        let first = camera.sessions.count
        cue.content = .feed(FeedContent(text: "ACTOR", settings: settings(mirror: true)))
        runner.redraw(cue, show: ShowSettings(), at: 0)
        #expect(camera.sessions.count == first && !camera.sessions.last!.isStopped)
        #expect(isGreen(render(live).pixel(x: 310, y: 10)), "the edit shows at once")
    }

    @Test("A camera nothing needs is let go when another cue takes the stage, and one standing by is kept")
    func releasesCameras() async throws {
        let on = feedCue(settings(), number: "5")
        fire(on)
        let first = camera.sessions.last!
        let next = feedCue(settings(), number: "6")
        renderer.preload(next, show: ShowSettings())
        let second = camera.sessions.last!
        #expect(first !== second && !first.isStopped && !second.isStopped, "the one on stage and the one standing by")

        fire(Cue(number: "7", content: .blank(BlankContent())))
        try await Task.sleep(for: .milliseconds(50))
        #expect(first.isStopped, "off stage and not standing by")
        #expect(!second.isStopped, "still wanted")
    }
}

@Suite("The next cue's preview")
@MainActor
struct NextPreviewTests {
    @Test("The up-next preview shows a live feed from the camera the stage uses")
    func nextShowsTheFeed() {
        let camera = PatternCamera()
        let controller = ShowController(show: Show(cues: [feedCue(FeedSettings(device: PatternCamera.deviceID, deviceName: "Test pattern"))]),
                                        renderers: [.feed: FeedRenderer(camera: camera)])
        #expect(controller.nextRunner.kinds.contains(.feed))
    }
}

@Suite("Capture cameras")
@MainActor
struct CaptureCameraTests {
    @Test("Listing this Mac's cameras works without asking permission, and names each one")
    func lists() {
        let devices = CaptureCamera().devices()
        #expect(devices.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
    }
}
