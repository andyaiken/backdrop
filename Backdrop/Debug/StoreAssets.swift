#if DEBUG
import AppKit
import BackdropCore
import BackdropStage
import QuartzCore

/// Debug builds only: writes what the App Store listing needs and quits.
/// A short demo show of original material, as a `.backdrop` package a
/// reviewer can open, and screenshots of the console at 1280 x 800 points.
///
///     Backdrop.app/Contents/MacOS/Backdrop -BackdropStoreAssets /tmp/storeassets
@MainActor
enum StoreAssets {
    static func run(to directory: String) {
        let folder = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Pictures, drawn here, so the show carries nothing from anywhere else.
        let pictures = [("dusk.png", Self.lighthouse(sky: [(0.98, 0.62, 0.35), (0.55, 0.30, 0.45), (0.10, 0.10, 0.25)], beam: false)),
                        ("night.png", Self.lighthouse(sky: [(0.12, 0.16, 0.30), (0.05, 0.07, 0.16), (0.01, 0.01, 0.05)], beam: true)),
                        ("storm.png", Self.lighthouse(sky: [(0.35, 0.38, 0.42), (0.20, 0.22, 0.28), (0.06, 0.07, 0.10)], beam: true))]
        var urls: [URL] = []
        for (name, data) in pictures {
            let url = folder.appendingPathComponent(name)
            try? data.write(to: url)
            urls.append(url)
        }

        var cues: [Cue] = [
            Cue(number: "1", line: "House to half. Lights fade on the keeper's cottage.",
                content: .title(TitleContent(text: "THE LAST LIGHT", sub: "A play in two acts", key: "LANTERN"))),
            Cue(number: "2", line: "MARA: \u{201C}Another evening, and the sea is quiet.\u{201D}", content: .image(ImageContent(text: "Dusk"))),
            Cue(number: "3", line: "The lamp is lit.", content: .image(ImageContent(text: "Night"))),
            Cue(number: "4", line: "Thunder. A door slams offstage.", content: .image(ImageContent(text: "Storm"))),
            Cue(number: "5", line: "TOM: \u{201C}The combination, Mara. Quickly.\u{201D}",
                content: .keypad(KeypadContent(text: "Safe", script: "4417\nGOOD"))),
            Cue(number: "6", line: "MARA: \u{201C}Morning.\u{201D}",
                content: .text(TextContent(text: "Six weeks later"))),
            Cue(number: "7", content: .blank(BlankContent())),
        ]
        let show = Show(title: "The Last Light", cues: cues)
        let ids = cues.map(\.id)
        cues.removeAll()

        let document = ShowDocument(show: show, warnings: [])
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        guard let controller = document.controller, let console = document.console, let window = console.window else { exit(1) }
        console.booth = { BoothConditions() }
        window.setContentSize(NSSize(width: 1280, height: 800))
        controller.enterEditMode()

        // The three pictures go in their cues.
        for (id, url) in zip([ids[1], ids[2], ids[3]], urls) {
            document.importMedia(from: url, into: id)
        }

        // The package a reviewer opens. Written from the document, which
        // holds the media it imported.
        do {
            let wrapper = try document.fileWrapper(ofType: ShowDocument.typeName)
            let url = folder.appendingPathComponent("The Last Light.backdrop")
            try? FileManager.default.removeItem(at: url)
            try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        } catch {
            try? "FAIL: \(error)".write(to: folder.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
            exit(1)
        }

        // Edit mode, on the title cue and then the image.
        controller.standBy(ids[0])
        console.showInspectorTab(0)
        settle(console)
        save(console, "1-edit-title", to: folder)
        controller.standBy(ids[1])
        settle(console)
        save(console, "2-edit-image", to: folder)
        controller.standBy(ids[4])
        settle(console)
        save(console, "3-edit-keypad", to: folder)

        // Show mode. Each cue is stood by, then fired, and given time to
        // settle, so a picture has decoded before it is photographed.
        controller.enterShowMode()
        var clock = CACurrentMediaTime()
        func fire(_ id: UUID, seconds: Double, saving name: String?, midway: String? = nil) {
            controller.standBy(id)
            controller.go()
            controller.tick(at: clock + 0.6)
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            if let midway {
                controller.tick(at: clock + 0.5 + 0.044 * 60)
                save(console, midway, to: folder)
            }
            controller.tick(at: clock + seconds)
            if let name { save(console, name, to: folder) }
            clock += seconds + 1
        }
        fire(ids[0], seconds: 10, saving: "4-show-title")
        fire(ids[1], seconds: 30, saving: "6-show-image", midway: "5-show-turning")
        fire(ids[3], seconds: 30, saving: "7-show-storm")
        controller.standBy(ids[4])
        controller.go()
        for i in 1...300 { controller.tick(at: clock + Double(i) / 60) }
        save(console, "8-show-keypad", to: folder)

        try? "OK".write(to: folder.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        exit(0)
    }

    /// Thumbnails and the preview are made in the background.
    private static func settle(_ console: ConsoleWindowController) {
        console.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        console.refresh()
    }

    /// A lighthouse on a rock at the edge of the sea, 1920 x 1080: a sky of
    /// three colours from the top, a sea, and a beam when the lamp is lit.
    private static func lighthouse(sky: [(Double, Double, Double)], beam: Bool) -> Data {
        let w = 1920, h = 1080
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let colours = sky.map { CGColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) } as CFArray
        // Core Graphics measures from the bottom: the sky's first colour is at the horizon.
        let gradient = CGGradient(colorsSpace: space, colors: colours, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 420), end: CGPoint(x: 0, y: CGFloat(h)), options: [.drawsAfterEndLocation])
        // The sea.
        let first = sky[0]
        ctx.setFillColor(CGColor(red: first.0 * 0.25, green: first.1 * 0.3, blue: first.2 * 0.5 + 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: 420))
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
        ctx.setLineWidth(3)
        for row in 0..<9 {
            let y = CGFloat(30 + row * 42)
            ctx.move(to: CGPoint(x: 0, y: y))
            for x in stride(from: 0, through: w, by: 80) {
                ctx.addQuadCurve(to: CGPoint(x: CGFloat(x + 80), y: y), control: CGPoint(x: CGFloat(x + 40), y: y + CGFloat(8 + row)))
            }
            ctx.strokePath()
        }
        // The rock.
        ctx.setFillColor(CGColor(gray: 0.06, alpha: 1))
        ctx.move(to: CGPoint(x: 1000, y: 330))
        ctx.addLine(to: CGPoint(x: 1560, y: 330))
        ctx.addLine(to: CGPoint(x: 1700, y: 380))
        ctx.addLine(to: CGPoint(x: 1480, y: 470))
        ctx.addLine(to: CGPoint(x: 1120, y: 470))
        ctx.addLine(to: CGPoint(x: 900, y: 380))
        ctx.closePath()
        ctx.fillPath()
        // The tower, in bands.
        let baseY: CGFloat = 450, topY: CGFloat = 860
        let tower = CGMutablePath()
        tower.move(to: CGPoint(x: 1180, y: baseY))
        tower.addLine(to: CGPoint(x: 1440, y: baseY))
        tower.addLine(to: CGPoint(x: 1380, y: topY))
        tower.addLine(to: CGPoint(x: 1240, y: topY))
        tower.closeSubpath()
        ctx.saveGState()
        ctx.addPath(tower)
        ctx.clip()
        for band in 0..<6 {
            let y0 = baseY + CGFloat(band) * (topY - baseY) / 6
            ctx.setFillColor(band % 2 == 0 ? CGColor(gray: 0.92, alpha: 1) : CGColor(red: 0.75, green: 0.15, blue: 0.12, alpha: 1))
            ctx.fill(CGRect(x: 1100, y: y0, width: 440, height: (topY - baseY) / 6))
        }
        ctx.restoreGState()
        // The gallery, the lantern and the roof.
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 1215, y: topY, width: 210, height: 22))
        let lit = beam ? CGColor(red: 1, green: 0.92, blue: 0.55, alpha: 1) : CGColor(red: 0.45, green: 0.4, blue: 0.3, alpha: 1)
        ctx.setFillColor(lit)
        ctx.fill(CGRect(x: 1250, y: topY + 22, width: 140, height: 90))
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.move(to: CGPoint(x: 1235, y: topY + 112))
        ctx.addLine(to: CGPoint(x: 1405, y: topY + 112))
        ctx.addLine(to: CGPoint(x: 1320, y: topY + 175))
        ctx.closePath()
        ctx.fillPath()
        if beam {
            ctx.saveGState()
            let glow = CGGradient(colorsSpace: space, colors: [CGColor(red: 1, green: 0.95, blue: 0.6, alpha: 0.55),
                                                              CGColor(red: 1, green: 0.95, blue: 0.6, alpha: 0)] as CFArray, locations: [0, 1])!
            ctx.move(to: CGPoint(x: 1250, y: topY + 70))
            ctx.addLine(to: CGPoint(x: 0, y: topY + 260))
            ctx.addLine(to: CGPoint(x: 0, y: topY - 120))
            ctx.closePath()
            ctx.clip()
            ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 1250, y: topY + 70), startRadius: 0,
                                   endCenter: CGPoint(x: 1250, y: topY + 70), endRadius: 1300, options: [])
            ctx.restoreGState()
        }
        return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    }

    /// The console, as `Snapshots` draws it, at twice its size in points.
    private static func save(_ console: ConsoleWindowController, _ name: String, to folder: URL) {
        guard let view = console.window?.contentView else { return }
        console.refresh()
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        if let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext {
            let preview = console.preview
            let frame = preview.convert(preview.bounds, to: view)
            func display(_ layer: CALayer) {
                layer.displayIfNeeded()
                layer.sublayers?.forEach(display)
            }
            display(preview.surface)
            context.saveGState()
            context.translateBy(x: frame.minX, y: view.bounds.height - frame.maxY)
            preview.surface.render(in: context)
            context.restoreGState()
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name + ".png"))
    }
}
#endif
