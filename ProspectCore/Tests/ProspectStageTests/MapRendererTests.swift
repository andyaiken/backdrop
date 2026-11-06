import AppKit
import ProspectCore
import QuartzCore
import Testing
@testable import ProspectStage

/// A printed street map, 1000 x 500: white, with one black road across it a
/// quarter of the way down.
private let maps: URL = {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("prospect-map-\(ProcessInfo.processInfo.processIdentifier)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let ctx = CGContext(data: nil, width: 1000, height: 500, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 1000, height: 500))
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    // Core Graphics counts up from the bottom: a quarter down is 375 up.
    ctx.fill(CGRect(x: 0, y: 365, width: 1000, height: 20))
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: folder.appendingPathComponent("streets.png"))
    return folder
}()

@Suite("Map renderer", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct MapRendererTests {
    let renderer = MapRenderer(media: { path in
        let url = maps.appendingPathComponent((path as NSString).lastPathComponent)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    })
    let live = surface(width: 960, height: 540)

    init() {
        live.updateInset()
        renderer.mount(on: live)
        renderer.setVisible(true, on: live)
    }

    func p(_ x: Double, _ y: Double) -> PicturePoint { PicturePoint(x: x, y: y) }

    /// Along the road, and then a jump below it. Zoom 1, so the map is the
    /// stage's width across: 960 x 480.
    func cue(advance: AnagramAdvance = .byItself, src: String = "media/streets.png", zoom: Int = 1, camera: MapCamera? = nil) -> Cue {
        Cue(number: "12", content: .map(MapContent(text: "OPERATION NIGHTJAR", src: src, route: [
            RoutePoint(at: p(0.1, 0.25), stop: MapStop(place: "SOHO")),
            RoutePoint(at: p(0.9, 0.25), stop: MapStop(travelMs: 4000, place: "BOW")),
            RoutePoint(at: p(0.5, 0.75), stop: MapStop(arrival: .jump, place: "DOCKS")),
        ], reference: MapReference(a: MapAnchor(at: p(0, 0), latitude: 52, longitude: -1), b: MapAnchor(at: p(1, 1), latitude: 51, longitude: 0)),
           overrides: MapOverrides(clockMs: 100, holdTicks: 10, advance: advance, pauseTicks: 10, camera: camera, zoom: zoom))))
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

    func green(_ px: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { px.g > 120 && px.g > px.r + 40 }
    func red(_ px: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { px.r > 150 && px.r > px.g + 80 }

    @Test("A light map turns to bright green lines on black, the right way up, the dot lit at the middle")
    func treatedAndPlaced() async throws {
        await prepare(cue())
        _ = renderer.paint(at: -10)
        let bitmap = render(live)
        bitmap.save("map-start")
        // The road runs through the dot, left to right; the middle of the
        // map, a quarter of its height below, is dark.
        #expect(green(bitmap.pixel(x: 700, y: 270)), "\(bitmap.pixel(x: 700, y: 270))")
        #expect(bitmap.pixel(x: 700, y: 390).g < 60, "\(bitmap.pixel(x: 700, y: 390))")
        #expect(red(bitmap.pixel(x: 480, y: 270)), "the dot, lighting as the cue starts: \(bitmap.pixel(x: 480, y: 270))")
        // West of the map's edge is black: the start is 96 points in.
        #expect(bitmap.isBlack(x: 200, y: 270) || bitmap.pixel(x: 200, y: 270).g < 8)
    }

    @Test("The map slides under the dot, which stays at the middle; the text types itself out")
    func slides() async throws {
        await prepare(cue())
        _ = renderer.paint(at: 20)
        let state = try #require(renderer.state)
        #expect(state.view == state.dot && state.dot.x > 0.4 && state.dot.x < 0.6)
        #expect(state.status.text == MapCuePlan.Words.moving)
        let tree = try #require(renderer.tree(for: live))
        #expect(text(of: tree.header.runs).hasPrefix("OPERATION NIGHTJAR"))
        #expect(text(of: tree.coordinates.runs) == MapReference.format(latitude: 52 - 0.25, longitude: -1 + state.dot.x))
        let bitmap = render(live)
        bitmap.save("map-travelling")
        #expect(green(bitmap.pixel(x: 700, y: 270)), "the road ahead")
        #expect(red(bitmap.pixel(x: 300, y: 270)), "the trail behind, over the road: \(bitmap.pixel(x: 300, y: 270))")
        #expect(!red(bitmap.pixel(x: 60, y: 270)), "and not before the start")
        #expect(!renderer.paint(at: 39) && renderer.paint(at: 50 + 34))
    }

    @Test("Held still, the map stays put, framed round the route, and the dot moves across it")
    func still() async throws {
        await prepare(cue(zoom: 3, camera: .still))
        _ = renderer.paint(at: -10)
        // The route spans the map, so all of it shows: 960 x 480 on the
        // stage, the start a tenth across and a quarter down.
        var bitmap = render(live)
        bitmap.save("map-still")
        #expect(red(bitmap.pixel(x: 96, y: 150)), "the dot at the start: \(bitmap.pixel(x: 96, y: 150))")
        #expect(!red(bitmap.pixel(x: 480, y: 270)))
        let tree = try #require(renderer.tree(for: live))
        let frame = tree.map.frame
        _ = renderer.paint(at: 30)
        #expect(tree.map.frame == frame, "the map hasn't moved")
        bitmap = render(live)
        #expect(red(bitmap.pixel(x: 96 + 500, y: 150)) || red(bitmap.pixel(x: 96 + 520, y: 150)), "the trail behind the dot, across the map")
    }

    @Test("A jump hides the dot and dashes the coordinates, then cuts to the new place")
    func jump() async throws {
        await prepare(cue())
        _ = renderer.paint(at: 52)
        let tree = try #require(renderer.tree(for: live))
        #expect(tree.dot.isHidden && text(of: tree.coordinates.runs) == MapReference.lost)
        #expect(tree.trail.allSatisfy { $0.path == nil })
        _ = renderer.paint(at: 76)
        #expect(!tree.dot.isHidden && renderer.state?.view == p(0.5, 0.75))
        render(live).save("map-acquired")
        #expect(text(of: tree.status.runs).hasPrefix("SIGNAL ACQUIRED"))
    }

    @Test("Each stop on GO: the dot waits, and the runner rests, until GO")
    func waits() async throws {
        let runner = StageRunner(renderers: [.map: renderer])
        runner.attach(surface(width: 960, height: 540))
        let cue = cue(advance: .eachStep)
        await prepare(cue)
        runner.load(cue, defaults: ShowSettings(), presentation: .run, at: 0)
        _ = runner.tick(at: 2)
        #expect(!runner.isRunning && renderer.state?.dot == p(0.1, 0.25))
        runner.carryOn(at: 2)
        _ = runner.tick(at: 4)
        #expect(runner.isRunning && (renderer.state?.dot.x ?? 0) > 0.1)
    }

    @Test("A missing map says so and the dot still runs; one too small for its zoom says how large it wants to be")
    func problems() async throws {
        var said: [String] = []
        renderer.onProblem = { said.append($0) }
        renderer.prepare(cue(src: "media/gone.png"), defaults: ShowSettings())
        #expect(said == ["Cue 12\u{2019}s map, gone.png, is missing from the show, so its dot moves over black."])
        #expect(renderer.paint(at: 1000))
        said = []
        await prepare(cue(zoom: 3))
        #expect(said == ["Cue 12\u{2019}s map is 1000 pixels across. At Zoom 3\u{00D7} it wants about 2880 to stay sharp on the projector."])
    }
}
