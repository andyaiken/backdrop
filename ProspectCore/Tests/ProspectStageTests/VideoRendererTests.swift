import AVFoundation
import ProspectCore
import QuartzCore
import Testing
@testable import ProspectStage

/// Short clips written for the tests: solid colour, H.264, no audio.
@MainActor
enum TestClips {
    static let folder: URL = {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ProspectVideo-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try! Data("not a film".utf8).write(to: folder.appendingPathComponent("broken.mov"))
        return folder
    }()

    private static var made: Set<String> = []

    /// - Parameters:
    ///   - transform: What the file asks a player to do with the picture.
    ///   - topHalf: A second colour over the top half, so which way up the
    ///     picture ends is something a test can see.
    ///   - firstFrame: A colour for frame 0 alone, to tell the frame playing
    ///     now apart from the one the poster was made from.
    static func clip(_ name: String, seconds: Double, red: UInt8 = 200, green: UInt8 = 40, blue: UInt8 = 40,
                     transform: CGAffineTransform = .identity,
                     topHalf: (r: UInt8, g: UInt8, b: UInt8)? = nil,
                     firstFrame: (r: UInt8, g: UInt8, b: UInt8)? = nil) async throws -> String {
        let url = folder.appendingPathComponent(name)
        if made.contains(name) { return name }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 90,
        ])
        input.expectsMediaDataInRealTime = false
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 90,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let fps: Int32 = 30
        for i in 0..<Int(seconds * Double(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let pixels = buffer!
            CVPixelBufferLockBaseAddress(pixels, [])
            let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
            let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
            for y in 0..<90 {
                for x in 0..<160 {
                    var (r, g, b) = (red, green, blue)
                    if let topHalf, y < 45 { (r, g, b) = topHalf }
                    if i == 0, let firstFrame { (r, g, b) = firstFrame }
                    let p = base + y * rowBytes + x * 4
                    p[0] = b; p[1] = g; p[2] = r; p[3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
        }
        input.markAsFinished()
        nonisolated(unsafe) let finishing = writer
        await finishing.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        made.insert(name)
        return name
    }
}

/// Polls until `condition` holds, for things AVFoundation does in its own time.
@MainActor
func eventually(within seconds: Double = 5, _ condition: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

/// Draws `image` at a known size and hands back a reader for its pixels.
func pixels(of image: CGImage, width: Int, height: Int) -> (Int, Int) -> (r: Int, g: Int, b: Int) {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let rowBytes = ctx.bytesPerRow
    let bytes = [UInt8](UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self),
                                            count: rowBytes * height))
    return { x, y in
        let i = y * rowBytes + x * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }
}

func videoCue(_ src: String, atEnd: VideoEnd = .hold, number: String = "7") -> Cue {
    Cue(number: number, content: .video(VideoContent(text: "CRYPTEX", sub: "REVEAL", src: src, atEnd: atEnd)))
}

@Suite("Video renderer", .serialized)
@MainActor
struct VideoRendererTests {
    let renderer = VideoRenderer(media: { TestClips.folder.appendingPathComponent($0) })
    let live = surface(width: 640, height: 360)
    let preview = surface(width: 320, height: 180, role: .preview)

    init() {
        for s in [live, preview] {
            renderer.mount(on: s)
            renderer.setVisible(true, on: s)
        }
    }

    func armed(_ cue: Cue) async -> Bool {
        renderer.preload(cue, defaults: ShowSettings())
        return await eventually { renderer.armState(for: cue.id) == .armed }
    }

    func readout() -> String {
        text(of: renderer.tree(for: preview)!.readout.runs)
    }

    @Test("Arming loads, prerolls and decodes a poster before GO; audio is muted")
    func arming() async throws {
        let cue = videoCue(try await TestClips.clip("arm.mov", seconds: 0.5))
        renderer.preload(cue, defaults: ShowSettings())
        #expect(renderer.armState(for: cue.id) == .arming)
        #expect(await eventually { renderer.armState(for: cue.id) == .armed })
        renderer.prepare(cue, defaults: ShowSettings())
        let clip = try #require(renderer.current)
        #expect(clip.poster != nil)
        #expect(clip.player.isMuted && clip.player.volume == 0)
        #expect(clip.player.rate == 0, "armed means waiting at the start, not playing")
    }

    @Test("The projector gets the picture; the preview gets a poster and the time")
    func liveAndPreviewDiffer() async throws {
        let cue = videoCue(try await TestClips.clip("split.mov", seconds: 1))
        #expect(await armed(cue))
        renderer.prepare(cue, defaults: ShowSettings())
        _ = renderer.frame(0)
        let liveTree = try #require(renderer.tree(for: live)), previewTree = try #require(renderer.tree(for: preview))
        #expect(liveTree.players[cue.id]?.opacity == 1)
        #expect(liveTree.players[cue.id]?.player === renderer.current?.player)
        #expect(previewTree.players.isEmpty, "no moving picture in the preview")
        #expect(previewTree.poster.contents != nil)
        #expect(readout().contains("LEFT") && readout().hasSuffix("THEN HOLDS"))
        #expect(await eventually { renderer.current!.player.rate > 0 })
    }

    @Test("A crossfade out of a clip takes the clip\u{2019}s own frame, on black in the picture\u{2019}s shape")
    func snapshotForACrossfade() async throws {
        let cue = videoCue(try await TestClips.clip("snap.mov", seconds: 1, red: 200, green: 40, blue: 40))
        #expect(await armed(cue))
        renderer.prepare(cue, defaults: ShowSettings())
        _ = renderer.frame(0)
        #expect(await eventually { renderer.current!.player.rate > 0 })
        // A 160 x 90 clip on a 400 x 400 stage: 16:9 across the middle, black above and below.
        let image = try #require(renderer.snapshot(size: CGSize(width: 400, height: 400)))
        #expect(image.width == 400 && image.height == 400)
        let ctx = CGContext(data: nil, width: 400, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 400, height: 400))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) { let i = (y * ctx.bytesPerRow) + x * 4; return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2])) }
        let centre = pixel(200, 200), top = pixel(200, 20)
        #expect(centre.0 > 150 && centre.1 < 90, "the clip\u{2019}s red in the middle: \(centre)")
        #expect(top == (0, 0, 0), "black above the picture")
        // With nothing on stage there is nothing to hand over.
        let empty = VideoRenderer(media: { _ in nil })
        #expect(empty.snapshot(size: CGSize(width: 100, height: 100)) == nil)
    }

    @Test("A crossfade takes the frame on stage now, not the clip\u{2019}s first")
    func snapshotIsTheFrameOnStage() async throws {
        // Green for frame 0 and red from then on: a clip that has been
        // running for a moment must not hand over its poster.
        let src = try await TestClips.clip("moving.mov", seconds: 1.5, firstFrame: (40, 200, 40))
        let cue = videoCue(src)
        #expect(await armed(cue))
        renderer.prepare(cue, defaults: ShowSettings())
        _ = renderer.frame(0)
        #expect(await eventually { renderer.current!.player.currentTime().seconds > 0.3 })
        let image = try #require(renderer.snapshot(size: CGSize(width: 400, height: 400)))
        let centre = pixels(of: image, width: 400, height: 400)(200, 200)
        #expect(centre.r > centre.g, "the frame playing now, which is red: \(centre)")
        // And the poster really is the green first frame, so that meant something.
        let poster = try #require(renderer.current?.poster)
        let first = pixels(of: poster, width: 160, height: 90)(80, 45)
        #expect(first.g > first.r, "the poster is the first frame: \(first)")
    }

    @Test("A clip the file asks to be turned is handed over turned")
    func snapshotTurnsThePicture() async throws {
        // 160 x 90 with a green top half, turned a quarter by the file: on
        // stage it stands 90 x 160, with the green down one side.
        let src = try await TestClips.clip("turned.mov", seconds: 1.5,
                                           transform: CGAffineTransform(rotationAngle: .pi / 2),
                                           topHalf: (40, 200, 40))
        let cue = videoCue(src)
        #expect(await armed(cue))
        renderer.prepare(cue, defaults: ShowSettings())
        _ = renderer.frame(0)
        #expect(await eventually { renderer.current!.player.currentTime().seconds > 0.3 })

        // The poster is AVFoundation turning the same picture itself, so
        // which way round a quarter turn goes isn't worked out twice here.
        let poster = try #require(renderer.current?.poster)
        #expect(poster.width < poster.height, "the file asks for a picture on its end")
        let upright = pixels(of: poster, width: 90, height: 160)
        let greenToTheRight = upright(70, 80).g > upright(20, 80).g

        let image = try #require(renderer.snapshot(size: CGSize(width: 400, height: 400)))
        let shot = pixels(of: image, width: 400, height: 400)
        // 90 x 160 on a 400 x 400 stage: the full height, black down the sides.
        let top = shot(200, 4)
        #expect(top.r + top.g + top.b > 0, "a standing picture fills the height: \(top)")
        #expect(shot(8, 200) == (0, 0, 0), "black down the sides")
        let right = shot(300, 200), left = shot(100, 200)
        #expect((right.g > right.r) == greenToTheRight,
                "turned the way AVFoundation turns it \u{2014} left \(left), right \(right)")
        #expect((left.g > left.r) != greenToTheRight,
                "and the other colour down the other side \u{2014} left \(left), right \(right)")
    }

    @Test("Hold: settles on reaching the end, frozen on the last frame")
    func hold() async throws {
        let cue = videoCue(try await TestClips.clip("hold.mov", seconds: 0.4))
        #expect(await armed(cue))
        renderer.prepare(cue, defaults: ShowSettings())
        #expect(!renderer.frame(0))
        #expect(await eventually { renderer.frame(1) })
        #expect(renderer.tree(for: live)?.players[cue.id]?.opacity == 1, "still showing")
        #expect(readout() == "ENDED \u{2014} HOLDING LAST FRAME")
    }

    @Test("Black: settles at the end and cuts to black")
    func black() async throws {
        let cue = videoCue(try await TestClips.clip("black.mov", seconds: 0.4), atEnd: .black)
        #expect(await armed(cue))
        renderer.prepare(cue, defaults: ShowSettings())
        _ = renderer.frame(0)
        #expect(await eventually { renderer.frame(1) })
        #expect(renderer.tree(for: live)?.players[cue.id]?.opacity == 0)
        #expect(readout() == "ENDED \u{2014} BLACK")
    }

    @Test("Loop: keeps playing past the end and never settles")
    func loop() async throws {
        let cue = videoCue(try await TestClips.clip("loop.mov", seconds: 0.3), atEnd: .loop)
        #expect(await armed(cue))
        renderer.prepare(cue, defaults: ShowSettings())
        _ = renderer.frame(0)
        try await Task.sleep(for: .milliseconds(800))
        #expect(!renderer.frame(1))
        #expect(renderer.current!.player.rate > 0)
        #expect(readout().hasSuffix("LOOPING"))
    }

    @Test("A missing clip goes to black, settles at once, and says so")
    func missingClip() async {
        var messages: [String] = []
        renderer.onProblem = { messages.append($0) }
        let cue = videoCue("media/gone.mov")
        renderer.preload(cue, defaults: ShowSettings())
        guard case .failed = renderer.armState(for: cue.id) else {
            Issue.record("should fail straight away")
            return
        }
        renderer.prepare(cue, defaults: ShowSettings())
        #expect(renderer.frame(0), "settled, so the show can still continue")
        #expect(renderer.tree(for: live)?.players[cue.id]?.opacity == 0)
        // Once when it was armed, and again as it fires.
        let message = "Cue 7\u{2019}s clip, gone.mov, is missing from the show, so it will go to black."
        #expect(messages == [message, message])
        #expect(readout() == "NO CLIP \u{2014} BLACK")
    }

    @Test("A file that won't play is reported too")
    func brokenClip() async {
        var messages: [String] = []
        renderer.onProblem = { messages.append($0) }
        let cue = videoCue("broken.mov")
        renderer.preload(cue, defaults: ShowSettings())
        #expect(await eventually {
            if case .failed = renderer.armState(for: cue.id) { return true }
            return false
        })
        #expect(messages.first?.contains("couldn\u{2019}t be played") == true)
    }

    @Test("Another cue stops the clip; it goes back to the start, still armed")
    func clearRearms() async throws {
        let cue = videoCue(try await TestClips.clip("again.mov", seconds: 1))
        #expect(await armed(cue))
        renderer.prepare(cue, defaults: ShowSettings())
        _ = renderer.frame(0)
        #expect(await eventually { renderer.current!.elapsed.seconds > 0.1 })
        let player = renderer.current!.player
        renderer.clear(live)
        #expect(player.rate == 0)
        #expect(renderer.armState(for: cue.id) == .armed)
        #expect(await eventually { player.currentTime().seconds < 0.05 })
        #expect(renderer.tree(for: live)?.players[cue.id]?.opacity == 0)
    }

    @Test("Resuming puts a held clip on its last frame, and a black one black")
    func resume() async throws {
        let held = videoCue(try await TestClips.clip("resume.mov", seconds: 0.5))
        #expect(await armed(held))
        renderer.prepare(held, defaults: ShowSettings())
        #expect(renderer.frame(StageRunner.settledFrame))
        #expect(renderer.current!.player.rate == 0)

        let blackCue = videoCue("resume.mov", atEnd: .black, number: "8")
        #expect(await armed(blackCue))
        renderer.clear(live)
        renderer.prepare(blackCue, defaults: ShowSettings())
        #expect(renderer.frame(StageRunner.settledFrame))
        #expect(renderer.tree(for: live)?.players[blackCue.id]?.opacity == 0)
    }

    @Test("Only a handful of players are kept")
    func eviction() async throws {
        let name = try await TestClips.clip("many.mov", seconds: 0.3)
        for n in 1...7 { renderer.preload(videoCue(name, number: "\(n)"), defaults: ShowSettings()) }
        #expect(renderer.tree(for: live)!.players.count <= VideoRenderer.keep)
    }

    @Test func clockFormat() {
        #expect(VideoRenderer.clock(0) == "0:00")
        #expect(VideoRenderer.clock(75.9) == "1:15")
        #expect(VideoRenderer.clock(600) == "10:00")
    }

    @Test("The preview, as the operator sees it")
    func previewSnapshot() async throws {
        let cue = videoCue(try await TestClips.clip("look.mov", seconds: 2, red: 40, green: 90, blue: 160))
        #expect(await armed(cue))
        renderer.prepare(cue, defaults: ShowSettings())
        _ = renderer.frame(0)
        try await Task.sleep(for: .milliseconds(600))
        _ = renderer.frame(1)
        render(preview).save("video-preview")
        #expect(readout().hasPrefix("0:00") || readout().hasPrefix("0:01"))
    }
}
