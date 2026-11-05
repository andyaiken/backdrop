import AppKit
import ProspectCore
import QuartzCore
import Testing
@testable import ProspectStage

/// Two 400 x 200 pictures, each a white dot on black: the first with its dot
/// left of centre, the second right of it.
private let media: URL = {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("prospect-morph-\(ProcessInfo.processInfo.processIdentifier)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for (name, x) in [("left.png", 100), ("right.png", 300)] {
        let ctx = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: x - 20, y: 80, width: 40, height: 40))
        try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
            .write(to: folder.appendingPathComponent(name))
    }
    return folder
}()

@Suite("Morph renderer", .timeLimit(.minutes(1)))
@MainActor
struct MorphRendererTests {
    let renderer = MorphRenderer(media: { path in
        let url = media.appendingPathComponent((path as NSString).lastPathComponent)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }, onScreen: false)
    let live = surface(width: 960, height: 540)

    init() {
        live.updateInset()
        renderer.mount(on: live)
        renderer.setVisible(true, on: live)
    }

    /// The dot's middle on each picture: a quarter and three quarters across.
    func dotCue(pairs: [MorphPair]? = nil) -> Cue {
        let pair = MorphPair(from: PicturePoint(x: 0.25, y: 0.5), to: PicturePoint(x: 0.75, y: 0.5))
        return Cue(number: "9", content: .morph(MorphContent(text: "DOT", src: "media/left.png", into: "media/right.png", pairs: pairs ?? [pair])))
    }

    func prepare(_ cue: Cue) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            renderer.onReady = {
                renderer.onReady = nil
                done.resume()
            }
            renderer.prepare(cue, defaults: ShowSettings())
        }
    }

    /// Brightness along the picture's middle, at a quarter, half and three
    /// quarters across: the picture sits at x 48 to 912 on this stage.
    func samples() throws -> (left: UInt8, middle: UInt8, right: UInt8) {
        let image = try #require(renderer.image(size: CGSize(width: 960, height: 540)))
        let ctx = CGContext(data: nil, width: 960, height: 540, bitsPerComponent: 8, bytesPerRow: 960 * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 960, height: 540))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        func at(_ x: Int) -> UInt8 { data[(270 * 960 + x) * 4] }
        return (at(264), at(480), at(696))
    }

    @Test("Halfway, the dot is one dot in the middle, not two dissolving where they started")
    func morphsRatherThanDissolves() async throws {
        await prepare(dotCue())
        _ = renderer.paint(at: -10)
        let start = try samples()
        #expect(start.left > 200 && start.middle < 30 && start.right < 30, "the first picture: \(start)")
        // 1500 ms into a 3 s morph, at the default 44 ms clock.
        _ = renderer.paint(at: 1500.0 / 44)
        #expect(abs(renderer.progress - 0.5) < 1e-9)
        let halfway = try samples()
        #expect(halfway.middle > 200 && halfway.left < 30 && halfway.right < 30, "one dot, travelled: \(halfway)")
        #expect(renderer.paint(at: 3000.0 / 44), "settled at the end of the morph")
        let end = try samples()
        #expect(end.right > 200 && end.left < 30 && end.middle < 30, "the second picture: \(end)")
    }

    @Test("Without points, the same two pictures simply dissolve: two faint dots halfway")
    func dissolveWithoutPoints() async throws {
        await prepare(dotCue(pairs: []))
        _ = renderer.paint(at: 1500.0 / 44)
        let halfway = try samples()
        #expect((90...165).contains(halfway.left) && (90...165).contains(halfway.right) && halfway.middle < 30, "\(halfway)")
    }

    @Test("It moves between the clock's frames, and holds still through the hold")
    func smooth() async throws {
        await prepare(dotCue())
        _ = renderer.paint(at: -20.5)
        #expect(renderer.progress == 0)
        _ = renderer.paint(at: 10.25)
        let a = renderer.progress
        _ = renderer.paint(at: 10.75)
        #expect(renderer.progress > a, "within one frame of the clock")
        #expect(!renderer.paint(at: 60))
    }

    @Test("The runner asks it to paint on every refresh, not just on the clock's frames")
    func runnerPaintsBetweenFrames() async throws {
        let runner = StageRunner(renderers: [.morph: renderer])
        runner.attach(surface(width: 960, height: 540))
        let cue = dotCue()
        await prepare(cue)
        runner.load(cue, defaults: ShowSettings(), presentation: .run, at: 0)
        let hold = 44 * 0.044
        _ = runner.tick(at: hold + 0.5)
        let a = renderer.progress
        _ = runner.tick(at: hold + 0.51)
        #expect(renderer.progress > a, "10 ms on, inside one 44 ms frame")
    }

    @Test("A missing picture shows the label on black, and says so")
    func missingPicture() async throws {
        var said: [String] = []
        renderer.onProblem = { said.append($0) }
        await prepare(Cue(number: "9", content: .morph(MorphContent(text: "DOT", src: "", into: "media/gone.png"))))
        #expect(said == ["Cue 9\u{2019}s second picture, gone.png, is missing from the show, so it is showing its label on black."])
        #expect(renderer.plan?.isReady == true)
    }

    @Test("Each picture sits where an image cue would put it: 90% of the stage, its own shape")
    func placement() {
        #expect(MorphRenderer.placement(aspect: 2, in: CGSize(width: 960, height: 540)) == CGRect(x: 48, y: 54, width: 864, height: 432))
        #expect(MorphRenderer.placement(aspect: 0.75, in: CGSize(width: 960, height: 540)) == CGRect(x: 298, y: 27, width: 365, height: 487))
    }
}

@Suite("Morph colours", .timeLimit(.minutes(1)))
@MainActor
struct MorphColourTests {
    func picture(_ rgb: (UInt8, UInt8, UInt8), width: Int, height: Int, info: CGBitmapInfo) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: CGFloat(rgb.0) / 255, green: CGFloat(rgb.1) / 255, blue: CGFloat(rgb.2) / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    func middle(_ image: CGImage) -> (UInt8, UInt8, UInt8) {
        let w = image.width, h = image.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let d = ctx.data!.assumingMemoryBound(to: UInt8.self), i = (h / 2 * w + w / 2) * 4
        return (d[i], d[i + 1], d[i + 2])
    }

    @Test("A picture's colours come through as they are, whatever its byte order, shown large or small")
    func colours() throws {
        let tan: (UInt8, UInt8, UInt8) = (219, 179, 133), navy: (UInt8, UInt8, UInt8) = (31, 41, 61)
        let orders: [CGBitmapInfo] = [
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
        ]
        let preview = MorphPreview()
        for info in orders {
            preview.setPictures(first: picture(tan, width: 2048, height: 1024, info: info),
                                second: picture(navy, width: 2048, height: 1024, info: info))
            for size in [CGSize(width: 960, height: 540), CGSize(width: 320, height: 180)] {
                let start = middle(try #require(preview.image(pairs: [], at: 0, size: size)))
                let end = middle(try #require(preview.image(pairs: [], at: 1, size: size)))
                #expect(abs(Int(start.0) - 219) <= 2 && abs(Int(start.1) - 179) <= 2 && abs(Int(start.2) - 133) <= 2, "\(info) at \(size): \(start)")
                #expect(abs(Int(end.0) - 31) <= 2 && abs(Int(end.1) - 41) <= 2 && abs(Int(end.2) - 61) <= 2, "\(info) at \(size): \(end)")
            }
        }
    }
}

@Suite("Face points")
struct FacePointsTests {
    func near(_ p: PicturePoint, _ x: Double, _ y: Double) -> Bool { abs(p.x - x) < 1e-12 && abs(p.y - y) < 1e-12 }

    @Test("A landmark across its face's box, both from the bottom left, becomes a place on the picture from the top left")
    func conversion() {
        let box = CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.4)
        #expect(near(FacePoints.picturePoint(CGPoint(x: 0, y: 0), inFace: box), 0.25, 0.8), "the box's bottom left")
        #expect(near(FacePoints.picturePoint(CGPoint(x: 1, y: 1), inFace: box), 0.75, 0.4), "its top right")
        #expect(near(FacePoints.picturePoint(CGPoint(x: 0.5, y: 0.5), inFace: box), 0.5, 0.6))
    }

    @Test("Three points above the brow carry the top of the head, kept on the picture")
    func head() {
        let box = CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.4)
        let points = FacePoints.headPoints(of: box)
        #expect(points.count == 3)
        #expect(near(points[0], 0.5, 0.26), "the crown, above the box's top at 0.4")
        #expect(points.allSatisfy { $0.y < 0.4 })
        #expect(FacePoints.headPoints(of: CGRect(x: 0, y: 0.5, width: 1, height: 0.5)).allSatisfy { $0 == $0.clamped })
    }

    @Test("Two faces' points pair up feature for feature")
    func pairing() {
        let a = [PicturePoint(x: 0.1, y: 0.1), PicturePoint(x: 0.2, y: 0.2)], b = [PicturePoint(x: 0.3, y: 0.3), PicturePoint(x: 0.4, y: 0.4)]
        #expect(FacePoints.pairs(a, b) == [MorphPair(from: a[0], to: b[0]), MorphPair(from: a[1], to: b[1])])
    }
}

@Suite("Morph loading", .timeLimit(.minutes(1)))
@MainActor
struct MorphLoadingTests {
    @Test("A morph whose pictures haven't arrived never says it has finished")
    func notFinishedWhileLoading() {
        let renderer = MorphRenderer(media: { _ in nil }, onScreen: false)
        renderer.mount(on: surface(width: 960, height: 540))
        renderer.prepare(Cue(content: .morph(MorphContent(text: "SLOW", src: "media/a.png", into: "media/b.png"))), defaults: ShowSettings())
        #expect(renderer.paint(at: 10_000) == false, "the pictures load on another thread, so aren't here yet")
    }
}
