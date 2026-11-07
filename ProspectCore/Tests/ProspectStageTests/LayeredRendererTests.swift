import AppKit
import ProspectCore
import QuartzCore
import Testing
@testable import ProspectStage

/// A 400 x 200 grey base, and three full-frame layers with transparency
/// round their part: red top left, green bottom right, blue top right.
private let media: URL = {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ProspectLayeredTests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    func write(_ name: String, width: Int = 400, height: Int = 200, fill: (CGContext) -> Void) {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        fill(ctx)
        try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
            .write(to: folder.appendingPathComponent(name))
    }
    write("base.png") { ctx in
        ctx.setFillColor(gray: 0.5, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
    }
    // A bitmap context measures from the bottom.
    write("square.png", width: 200, height: 200) { ctx in ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200)) }
    write("red.png") { ctx in ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 100, width: 200, height: 100)) }
    write("green.png") { ctx in ctx.setFillColor(red: 0, green: 1, blue: 0, alpha: 1); ctx.fill(CGRect(x: 200, y: 0, width: 200, height: 100)) }
    write("blue.png") { ctx in ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1); ctx.fill(CGRect(x: 200, y: 100, width: 200, height: 100)) }
    return folder
}()

private func layer(_ file: String, withPrevious: Bool = false, life: LayerLife = .stays) -> ImageLayer {
    ImageLayer(src: file, name: (file as NSString).deletingPathExtension, withPrevious: withPrevious, life: life)
}

private func cue(_ layers: [ImageLayer], base: String = "base.png", settings: LayeredSettings = .init()) -> Cue {
    Cue(number: "4", content: .layered(LayeredContent(text: "Last Supper", base: base, layers: layers, settings: settings)))
}

@Suite("Layered renderer")
@MainActor
struct LayeredRendererTests {
    let renderer = LayeredRenderer(media: { media.appendingPathComponent($0) })
    let live = surface(width: 960, height: 540)
    var onGo = LayeredSettings(advance: .eachStep, layerMs: 400)

    init() {
        renderer.mount(on: live)
        renderer.setVisible(true, on: live)
    }

    /// Prepares the cue with these settings in place of its own.
    func prepare(_ cue: Cue, settings: LayeredSettings) async {
        var cue = cue
        if case .layered(var content) = cue.content {
            content.settings = settings
            cue.content = .layered(content)
        }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            renderer.onReady = { [renderer] in
                renderer.onReady = nil
                done.resume()
            }
            renderer.prepare(cue, show: ShowSettings())
        }
    }

    var tree: LayeredRenderer.Tree { renderer.tree(for: live)! }
    var opacities: [Float] { tree.layers.map(\.opacity) }

    /// The picture's rect on the 960 x 540 surface, 90% of it keeping the 2:1 shape.
    func pixel(_ bitmap: Bitmap, atPicture x: Double, _ y: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
        let rect = tree.picture.frame
        // The surface measures from the bottom; bitmaps from the top.
        let top = live.inset.bounds.height - rect.maxY
        return bitmap.pixel(x: Int(rect.minX + rect.width * x), y: Int(top + rect.height * y))
    }

    @Test("It opens on the base alone, at the cue's base level, waiting for the first GO")
    func opening() async {
        await prepare(cue([layer("red.png"), layer("green.png")]), settings: onGo)
        #expect(!renderer.frame(-3))
        #expect(close(tree.base.opacity, 0.25) && opacities == [0, 0])
        #expect(renderer.isWaiting(at: 0), "step one waits for GO")
        #expect(tree.picture.frame.width == 864 && tree.picture.frame.height == 432, "90% of the stage, the picture's shape")
    }

    func close(_ a: Float, _ b: Float) -> Bool { abs(a - b) < 0.001 }

    @Test("Each GO brings its layer on, animating up to its level")
    func goBringsLayerOn() async {
        var red = layer("red.png")
        red.level = 60
        await prepare(cue([red, layer("green.png")]), settings: onGo)
        _ = renderer.frame(0)
        renderer.carryOn(at: 10)
        _ = renderer.frame(10)
        #expect(close(opacities[0], 0.6) && opacities[1] == 0, "the model is at its level; the animation carries it there")
        #expect(tree.layers[0].animation(forKey: "opacity") != nil)
        #expect(!renderer.frame(10 + 9), "400 ms is ten frames at 44 ms, and another step still waits")
        #expect(!renderer.isWaiting(at: 19) && renderer.isWaiting(at: 20))
        renderer.carryOn(at: 30)
        #expect(!renderer.frame(30))
        #expect(close(opacities[1], 1))
        #expect(renderer.frame(40), "the last step has landed")
    }

    @Test("A false step takes the layer off again, quicker than it came")
    func falseStep() async {
        await prepare(cue([layer("red.png"), layer("green.png", life: .untilNextGo), layer("blue.png")]), settings: onGo)
        _ = renderer.frame(0)
        for (n, f) in [10, 30, 50, 70].enumerated() {
            renderer.carryOn(at: f)
            _ = renderer.frame(f)
            switch n {
            case 1: #expect(close(opacities[1], 1))
            case 2:
                #expect(opacities[1] == 0 && close(opacities[0], 1), "gone on its own beat")
                let leave = tree.layers[1].animation(forKey: "opacity") as? CABasicAnimation
                #expect(leave?.toValue as? Float == 0 && abs((leave?.duration ?? 0) - 0.2) < 1e-9, "half the 0.4 s it took to arrive")
            case 3: #expect(close(opacities[2], 1) && opacities[1] == 0)
            default: break
            }
        }
    }

    @Test("A jump lands on the picture before that step with nothing animating, then the step runs")
    func jump() async {
        await prepare(cue([layer("red.png"), layer("green.png"), layer("blue.png")]), settings: onGo)
        _ = renderer.frame(0)
        renderer.carryOn(at: 10)
        _ = renderer.frame(10)
        renderer.goTo(2, at: 40)
        _ = renderer.frame(40)
        #expect(close(opacities[0], 1) && close(opacities[1], 1) && close(opacities[2], 1))
        #expect(tree.layers[0].animation(forKey: "opacity") == nil && tree.layers[1].animation(forKey: "opacity") == nil)
        #expect(tree.layers[2].animation(forKey: "opacity") != nil, "the step it landed on runs")
        // Back to the first step: the others are gone outright.
        renderer.goTo(0, at: 60)
        _ = renderer.frame(60)
        #expect(close(opacities[0], 1) && opacities[1] == 0 && opacities[2] == 0)
    }

    @Test("A cue put up finished shows the whole picture, settled")
    func settled() async {
        await prepare(cue([layer("red.png"), layer("green.png", life: .untilNextGo)]), settings: onGo)
        renderer.carryOnToEnd()
        #expect(renderer.frame(1_000_000))
        #expect(close(opacities[0], 1) && opacities[1] == 0 && tree.layers[0].animation(forKey: "opacity") == nil)
        let bitmap = render(live)
        let red = pixel(bitmap, atPicture: 0.25, 0.25), green = pixel(bitmap, atPicture: 0.75, 0.75)
        #expect(red.r > 200 && red.g < 60 && red.b < 60, "the red part is up")
        #expect(abs(Int(green.r) - 32) < 8 && abs(Int(green.g) - 32) < 8, "the withdrawn green is gone, leaving the faint base: \\(green)")
    }

    @Test("A cue put up finished before its pictures load still settles when they arrive")
    func settledBeforeLoading() async {
        let c = cue([layer("red.png")])
        renderer.prepare(c, show: ShowSettings())
        renderer.carryOnToEnd()
        _ = renderer.frame(1_000_000)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            renderer.onReady = { done.resume() }
        }
        #expect(close(opacities[0], 1))
    }

    @Test("Moving on by itself, every step runs a pause after the one before")
    func byItself() async {
        var defaults = LayeredSettings()
        defaults.layerMs = 440
        defaults.pauseTicks = 10
        defaults.holdTicks = 0
        await prepare(cue([layer("red.png"), layer("green.png")]), settings: defaults)
        #expect(!renderer.isWaiting(at: 0))
        _ = renderer.frame(0)
        #expect(close(opacities[0], 1) && opacities[1] == 0)
        _ = renderer.frame(19)
        #expect(opacities[1] == 0, "ten frames to land, ten to pause")
        #expect(!renderer.frame(19))
        _ = renderer.frame(20)
        #expect(close(opacities[1], 1))
        #expect(renderer.frame(30))
    }

    @Test("A layer whose file is missing is reported and skipped, but its step still happens")
    func missing() async {
        var problems: [String] = []
        renderer.onProblem = { problems.append($0) }
        let c = cue([layer("red.png"), layer("gone.png"), layer("blue.png")], settings: onGo)
        await prepare(c, settings: onGo)
        #expect(problems.count == 1 && problems[0].contains("gone.png"))
        #expect(c.goPoints().count == 3)
        _ = renderer.frame(0)
        for f in [10, 30, 50] { renderer.carryOn(at: f); _ = renderer.frame(f) }
        #expect(close(opacities[0], 1) && close(opacities[2], 1) && tree.layers[1].isHidden)
        #expect(renderer.frame(60))
    }

    @Test("A layer that isn\u{2019}t the base\u{2019}s shape is reported, and still plays")
    func shapeMismatch() async {
        var problems: [String] = []
        renderer.onProblem = { problems.append($0) }
        await prepare(cue([layer("red.png"), layer("square.png")]), settings: onGo)
        #expect(problems.count == 1 && problems[0].contains("layer 2") && problems[0].contains("square.png".replacingOccurrences(of: ".png", with: "")))
        _ = renderer.frame(0)
        renderer.carryOn(at: 10); _ = renderer.frame(10)
        renderer.carryOn(at: 30); _ = renderer.frame(30)
        #expect(close(opacities[1], 1), "it still arrives")
        problems = []
        await prepare(cue([layer("red.png"), layer("green.png")]), settings: onGo)
        #expect(problems.isEmpty, "the right shape says nothing")
    }

    @Test("Blend, base level and layer level reach the layers")
    func properties() async {
        var green = layer("green.png")
        green.blend = .screen
        var dark = onGo
        dark.baseLevel = 0
        await prepare(cue([layer("red.png"), green]), settings: dark)
        _ = renderer.frame(-1)
        #expect(tree.base.opacity == 0)
        #expect(tree.layers[0].compositingFilter == nil && tree.layers[1].compositingFilter as? String == "screenBlendMode")
    }

    @Test("A cue with no base is black under its layers")
    func noBase() async {
        await prepare(cue([layer("red.png")], base: ""), settings: onGo)
        _ = renderer.frame(-1)
        #expect(tree.base.contents == nil)
        #expect(tree.picture.frame.width > 0, "the layer sets the shape")
    }

    @Test("Each context treatment animates the layers already standing")
    func contexts() async {
        for context in [LayerContext.dim, .desaturate] {
            var defaults = onGo
            defaults.context = context
            defaults.contextTicks = 10
            await prepare(cue([layer("red.png"), layer("green.png")]), settings: defaults)
            _ = renderer.frame(0)
            renderer.carryOn(at: 10)
            _ = renderer.frame(10)
            #expect(tree.base.animation(forKey: "context") == nil, "nothing was standing at the first step")
            renderer.carryOn(at: 30)
            _ = renderer.frame(30)
            #expect(tree.layers[0].animation(forKey: "context") != nil, "\\(context): the first layer is treated while the second arrives")
            #expect(tree.layers[1].animation(forKey: "context") == nil, "and the arriving layer is not")
        }
        var spot = onGo
        spot.context = .spotlight
        await prepare(cue([layer("red.png"), layer("green.png")]), settings: spot)
        _ = renderer.frame(0)
        renderer.carryOn(at: 10); _ = renderer.frame(10)
        renderer.carryOn(at: 30); _ = renderer.frame(30)
        #expect(tree.spotlight.animation(forKey: "context") != nil)
        #expect(tree.spotlight.startPoint.x > 0.5 && tree.spotlight.startPoint.y < 0.5, "centred on the green part, bottom right")
    }

    @Test("An outline entrance draws the part's alpha edge as a brass line")
    func outline() async {
        var defaults = onGo
        defaults.entrance = .outline
        await prepare(cue([layer("red.png")]), settings: defaults)
        _ = renderer.frame(0)
        renderer.carryOn(at: 10); _ = renderer.frame(10)
        #expect(tree.edges[0].contents != nil && tree.edges[0].animation(forKey: "outline") != nil)
    }

    @Test("Settle scales about the part's own centre, and bloom overshoots its level")
    func entrances() async {
        var defaults = onGo
        defaults.entrance = .settle
        await prepare(cue([layer("red.png")]), settings: defaults)
        _ = renderer.frame(0)
        renderer.carryOn(at: 10); _ = renderer.frame(10)
        #expect(tree.layers[0].animation(forKey: "settle") != nil)
        #expect(abs(tree.layers[0].anchorPoint.x - 0.25) < 0.02 && abs(tree.layers[0].anchorPoint.y - 0.75) < 0.02, "about the top left part")
        var bloom = onGo
        bloom.entrance = .bloom
        await prepare(cue([layer("red.png")]), settings: bloom)
        _ = renderer.frame(0)
        renderer.carryOn(at: 10); _ = renderer.frame(10)
        let k = tree.layers[0].animation(forKey: "opacity") as? CAKeyframeAnimation
        #expect((k?.values?.compactMap { $0 as? Float }.max() ?? 0) > 1 - 0.0001 && k?.values?.count == 3)
    }

    @Test("A pushing camera frames each part, pulling back through the whole picture, and settles on it")
    func camera() async {
        var defaults = onGo
        defaults.camera = .push
        defaults.zoom = 4
        defaults.cameraMs = 880
        await prepare(cue([layer("red.png"), layer("green.png")]), settings: defaults)
        _ = renderer.frame(0)
        #expect(CATransform3DIsIdentity(tree.zoomer.transform), "the whole picture to begin with")
        renderer.carryOn(at: 10); _ = renderer.frame(10)
        // Red is the top left quarter: framed at 2 : 1 of 0.58 of the picture.
        let to = tree.zoomer.transform
        #expect(abs(to.m11 - 1 / 0.58) < 0.01 && to.m11 == to.m22 && to.m41 == 0, "scaled in on the top left")
        let move = tree.zoomer.animation(forKey: "camera") as? CAKeyframeAnimation
        #expect(move?.values?.count == 3 && abs((move?.duration ?? 0) - 0.88) < 1e-9, "from the whole, by way of the whole, to the part")
        renderer.carryOn(at: 30); _ = renderer.frame(30)
        #expect(tree.zoomer.transform.m41 < to.m41, "the green part is bottom right, so the picture slides left")
        #expect(renderer.frame(60))
        #expect(CATransform3DIsIdentity(tree.zoomer.transform), "pulled back out for the end of the cue")
        // A jump sets the frame outright, with no move.
        renderer.goTo(0, at: 80); _ = renderer.frame(80)
        #expect(abs(tree.zoomer.transform.m11 - 1 / 0.58) < 0.01)
        #expect(tree.zoomer.animation(forKey: "camera") != nil, "the step it landed on moves in")
    }

    @Test("A still camera never moves, and a travelling one goes straight")
    func stillAndTravel() async {
        await prepare(cue([layer("red.png")]), settings: onGo)
        _ = renderer.frame(0)
        renderer.carryOn(at: 10); _ = renderer.frame(10)
        #expect(CATransform3DIsIdentity(tree.zoomer.transform) && tree.zoomer.animation(forKey: "camera") == nil)
        var defaults = onGo
        defaults.camera = .travel
        await prepare(cue([layer("red.png")]), settings: defaults)
        _ = renderer.frame(0)
        renderer.carryOn(at: 10); _ = renderer.frame(10)
        #expect((tree.zoomer.animation(forKey: "camera") as? CAKeyframeAnimation)?.values?.count == 2)
    }

    @Test("Pictures decode at the cue's own push depth and no deeper")
    func pushDepth() async {
        await prepare(cue([layer("red.png")]), settings: onGo)
        let flat = renderer.maxPixels
        var defaults = onGo
        defaults.camera = .push
        defaults.zoom = 2
        await prepare(cue([layer("red.png")]), settings: defaults)
        #expect(renderer.maxPixels > flat && renderer.maxPixels <= 8192)
    }

    // MARK: Snapshots
    //
    // The picture at the moments that matter, read back as the projector would
    // show it. PROSPECT_SNAPSHOTS=<folder> writes each as a PNG to look at.

    func isRed(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.r > 200 && p.g < 60 && p.b < 60 }
    func isGreen(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.g > 200 && p.r < 60 && p.b < 60 }
    func isBase(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { abs(Int(p.r) - 32) < 8 && abs(Int(p.g) - 32) < 8 && abs(Int(p.b) - 33) < 8 }

    @Test("Snapshots: the opening state, a mid-cue state, the settled picture, a jump to a late step, and a false step gone")
    func snapshots() async {
        let layers = [layer("red.png"), layer("green.png", life: .untilNextGo), layer("red.png")]
        await prepare(cue(layers), settings: onGo)
        let topLeft = (0.25, 0.25), bottomRight = (0.75, 0.75)
        _ = renderer.frame(0)
        let opening = render(live)
        opening.save("layered-1-opening")
        #expect(isBase(pixel(opening, atPicture: topLeft.0, topLeft.1)) && isBase(pixel(opening, atPicture: bottomRight.0, bottomRight.1)),
                "the faint base alone")
        #expect(opening.isBlack(x: 5, y: 5), "and black round the picture")

        renderer.carryOn(at: 10); _ = renderer.frame(10)
        let first = render(live)
        first.save("layered-2-first-part")
        #expect(isRed(pixel(first, atPicture: topLeft.0, topLeft.1)) && isBase(pixel(first, atPicture: bottomRight.0, bottomRight.1)))

        renderer.carryOn(at: 30); _ = renderer.frame(30)
        let second = render(live)
        second.save("layered-3-second-part")
        #expect(isRed(pixel(second, atPicture: topLeft.0, topLeft.1)) && isGreen(pixel(second, atPicture: bottomRight.0, bottomRight.1)))

        renderer.carryOn(at: 50); _ = renderer.frame(50)
        let gone = render(live)
        gone.save("layered-4-false-step-gone")
        #expect(isRed(pixel(gone, atPicture: topLeft.0, topLeft.1)) && isBase(pixel(gone, atPicture: bottomRight.0, bottomRight.1)),
                "the withdrawn green is gone, the red stays")

        renderer.goTo(1, at: 100); _ = renderer.frame(100)
        let jumped = render(live)
        jumped.save("layered-5-jump-to-second")
        #expect(isRed(pixel(jumped, atPicture: topLeft.0, topLeft.1)) && isGreen(pixel(jumped, atPicture: bottomRight.0, bottomRight.1)),
                "straight to the picture as it stands at that step")
        renderer.goTo(0, at: 120); _ = renderer.frame(120)
        #expect(isBase(pixel(render(live), atPicture: bottomRight.0, bottomRight.1)), "and back again")

        renderer.carryOnToEnd(); _ = renderer.frame(1_000_000)
        let settled = render(live)
        settled.save("layered-6-settled")
        #expect(isRed(pixel(settled, atPicture: topLeft.0, topLeft.1)) && isBase(pixel(settled, atPicture: bottomRight.0, bottomRight.1)))
    }

    @Test("Snapshot: pushed in on a part, the part fills the picture")
    func pushedIn() async {
        var defaults = onGo
        defaults.camera = .push
        defaults.zoom = 4
        await prepare(cue([layer("red.png"), layer("green.png")]), settings: defaults)
        _ = renderer.frame(0)
        renderer.carryOn(at: 10); _ = renderer.frame(10)
        let pushed = render(live)
        pushed.save("layered-7-pushed-in")
        // The red quarter is framed with padding, so it covers the picture
        // but for the margin; its centre is red, and the far corner is not.
        #expect(isRed(pixel(pushed, atPicture: 0.4, 0.4)) && isRed(pixel(pushed, atPicture: 0.05, 0.05)))
        #expect(!isRed(pixel(pushed, atPicture: 0.95, 0.95)), "the margin shows what is round the part")
        // At rest, once finished, the whole picture again.
        renderer.carryOn(at: 30); _ = renderer.frame(30)
        _ = renderer.frame(60)
        let rest = render(live)
        rest.save("layered-8-settled-out")
        #expect(isRed(pixel(rest, atPicture: 0.25, 0.25)) && isGreen(pixel(rest, atPicture: 0.75, 0.75)))
    }

    @Test("A late-mounted surface shows the current picture straight away")
    func lateSurface() async {
        await prepare(cue([layer("red.png"), layer("green.png")]), settings: onGo)
        _ = renderer.frame(0)
        renderer.carryOn(at: 10); _ = renderer.frame(10)
        let second = surface(width: 480, height: 270, role: .preview)
        renderer.mount(on: second)
        let t = renderer.tree(for: second)!
        #expect(close(t.layers[0].opacity, 1) && t.layers[1].opacity == 0 && t.picture.frame.width > 0)
    }
}

@Suite("Layer pixels")
struct LayerImageTests {
    func image(_ draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx)
        return ctx.makeImage()!
    }

    @Test("The opaque bounds of a layer are read from its alpha, from the top left")
    func bounds() {
        // A bitmap measures from the bottom: this is x 100 to 200, y 40 to 80 from the top.
        let img = image { ctx in
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            ctx.fill(CGRect(x: 100, y: 120, width: 100, height: 40))
        }
        let r = LayerImages.opaqueBounds(of: img)!
        #expect(abs(r.x - 0.25) < 0.02 && abs(r.y - 0.2) < 0.02 && abs(r.width - 0.25) < 0.02 && abs(r.height - 0.2) < 0.02)
        #expect(LayerImages.opaqueBounds(of: image { _ in }) == nil, "a layer with nothing in it has no bounds")
        let full = LayerImages.opaqueBounds(of: image { $0.setFillColor(gray: 1, alpha: 1); $0.fill(CGRect(x: 0, y: 0, width: 400, height: 200)) })!
        #expect(full.x == 0 && full.y == 0 && full.width == 1 && full.height == 1)
    }

    @Test("A stray faint mark doesn't pull the bounds out to the corner")
    func faintIgnored() {
        let img = image { ctx in
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            ctx.fill(CGRect(x: 100, y: 100, width: 50, height: 50))
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.02)
            ctx.fill(CGRect(x: 380, y: 0, width: 20, height: 20))
        }
        #expect(LayerImages.opaqueBounds(of: img)!.width < 0.2)
    }

    @Test("The edge of a layer's alpha is drawn in the colour, on transparency")
    func edge() throws {
        let img = image { ctx in
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            ctx.fill(CGRect(x: 100, y: 50, width: 200, height: 100))
        }
        let edge = try #require(LayerImages.edge(of: img, colour: CGColor(red: 0.8, green: 0.6, blue: 0.2, alpha: 1)))
        #expect(edge.width == 400 && edge.height == 200)
        let b = LayerImages.opaqueBounds(of: edge)
        #expect(b != nil && abs(b!.x - 0.25) < 0.05 && abs(b!.width - 0.5) < 0.1, "a ring round the part")
        // The middle of the part is clear.
        let ctx = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(edge, in: CGRect(x: 0, y: 0, width: 400, height: 200))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        #expect(data[(100 * 400 + 200) * 4 + 3] < 10)
    }
}

@Suite("Layered cue plan")
struct LayeredCuePlanTests {
    func plan(_ layers: [ImageLayer], on: Bool, _ tweak: (inout LayeredSettings) -> Void = { _ in }) -> LayeredCuePlan {
        var s = LayeredSettings(clockMs: 50, advance: on ? .eachStep : .byItself, pauseTicks: 4, layerMs: 500)
        tweak(&s)
        let content = LayeredContent(layers: layers, settings: s)
        return LayeredCuePlan(content, settings: s)
    }

    @Test("With each step on GO, the base is part 0 and every step a part of its own")
    func onGo() {
        let p = plan([layer("a.png"), layer("b.png", life: .untilNextGo)], on: true)
        #expect(p.steps.map(\.part) == [1, 2, 3] && p.steps.map(\.offset) == [0, 0, 0])
        // Ten frames to arrive; the withdrawal takes half as long.
        #expect(p.parts == [0, 10, 10, 5])
    }

    @Test("Moving on by itself, every step is in the first part, a pause after the one before")
    func byItself() {
        let p = plan([layer("a.png"), layer("b.png")], on: false)
        #expect(p.steps.map(\.part) == [0, 0] && p.steps.map(\.offset) == [0, 14] && p.parts == [24])
    }

    @Test("A layer's own fade time and the briskness of a withdrawal")
    func fades() {
        var slow = layer("a.png")
        slow.fadeMs = 2000
        let p = plan([slow, layer("b.png")], on: true)
        #expect(p.arriveMs(of: 0) == 2000 && p.leaveMs(of: 0) == 1000 && p.arriveMs(of: 1) == 500)
        #expect(p.parts == [0, 40, 10])
    }

    @Test("Steps reached and finished, by frame")
    func reached() {
        let p = plan([layer("a.png"), layer("b.png")], on: true)
        var t = GoTimeline(parts: p.parts)
        #expect(p.reached(at: 5, timeline: t) == -1 && !p.isFinished(at: 5, timeline: t))
        t.carryOn(at: 5)
        #expect(p.reached(at: 4, timeline: t) == -1 && p.reached(at: 5, timeline: t) == 0)
        t.carryOn(at: 20)
        #expect(p.reached(at: 20, timeline: t) == 1 && !p.isFinished(at: 29, timeline: t) && p.isFinished(at: 30, timeline: t))
        #expect(plan([], on: true).isFinished(at: 0, timeline: GoTimeline(parts: [0])))
    }
}
