#if DEBUG
import AppKit
import ProspectCore
import ProspectStage
import QuartzCore

/// Debug builds only: renders the console offscreen to PNGs and quits, so its
/// layout can be looked at without driving the screen.
///
///     Prospect.app/Contents/MacOS/Prospect -ProspectSnapshot /some/folder
@MainActor
enum Snapshots {
    static func run(to directory: String) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        var show = sheet()
        // A video cue with no clip after cue 1, to show the standby panel's
        // armed line when it stands by.
        show.cues.insert(Cue(number: "1.5", content: .video(VideoContent(text: "CRYPTEX", sub: "REVEAL", src: "media/cryptex.mov"))), at: 1)
        // Two transitions of their own: a snap into the first blank, and a
        // slower fade into the second picture.
        show.cues[3].transition = Transition(style: .snap)
        show.cues[5].transition = Transition(fadeMs: 1200)
        // And a timed continue, on the cue the editor shows.
        show.cues[4].continueMode = .after(ms: 5000)
        show.cues[7].continueMode = .whenFinished
        // The first picture goes in a golden spiral, so the frame caught
        // mid-reveal shows its shape.
        if case .image(var first) = show.cues[2].content {
            first.settings.order = .spiral
            show.cues[2].content = .image(first)
        }
        show.cues[5].continueMode = .whenFinished(waitMs: 2000)
        let document = ShowDocument(show: show, warnings: [])
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        guard let controller = document.controller, let console = document.console else { exit(1) }
        console.window?.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 860), display: false)
        controller.enterShowMode()
        let start = CACurrentMediaTime()

        // Cue 1 fired and settled, the video standing by.
        controller.go()
        for i in 1...720 { controller.tick(at: start + Double(i) / 60) }
        save(console, "console-show", to: directory)
        // The wordmark partway through decrypting, as when the window opens,
        // then home again.
        console.holdWordmark(atFrame: 14)
        save(console, "console-wordmark", to: directory)
        console.holdWordmark(atFrame: 1000)

        // Past the video, which goes to black at once.
        controller.go()
        controller.tick(at: start + 13)

        // Cue 2, an image cue with no picture, so its label on black:
        // mid-flip, then settled. It
        // goes up once the video has faded out, and its picture decodes in the
        // background, so the run loop gets a moment.
        let fired = CACurrentMediaTime()
        controller.go()
        controller.tick(at: fired + 0.6)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        controller.tick(at: fired + 0.5 + 0.044 * 70)
        save(console, "console-image-turning", to: directory)
        controller.tick(at: fired + 30)
        save(console, "console-image", to: directory)

        // Edit mode: guides, a pulled-in projection area, and the editor on a
        // title cue, then on an image cue.
        controller.enterEditMode()
        controller.showsGuides = true
        controller.setGeometry(Geometry(width: 90, height: 86, across: 2, down: -3))
        controller.standBy(controller.show.cues[4].id)
        save(console, "console-edit", to: directory)
        controller.standBy(controller.show.cues[5].id)
        save(console, "console-edit-image", to: directory)

        // The settings tabs: the image cue with two values of its own, then
        // the show's settings.
        let image = controller.show.cues[5].id
        controller.setSetting(.grid, to: .number(20), for: image)
        controller.setSetting(.order, to: .order(.spiral), for: image)
        controller.setSetting(.reveal, to: .reveal(.sharpen), for: image)
        console.showInspectorTab(1)
        save(console, "console-cue-settings", to: directory)
        // Wide enough that the inspector stands beside the preview.
        console.window?.setFrame(NSRect(x: 0, y: 0, width: 1700, height: 980), display: false)
        console.showInspectorTab(1)
        save(console, "console-wide-cue-settings", to: directory)
        console.showInspectorTab(0)
        save(console, "console-wide-cue", to: directory)
        console.window?.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 860), display: false)
        // A decryption cue whose letters are on dials.
        let decryption = controller.show.cues[4].id
        controller.setSetting(.letters, to: .letters(.dials), for: decryption)
        controller.standBy(decryption)
        console.showInspectorTab(1)
        save(console, "console-cue-settings-decryption", to: directory)

        // A cue just added: every field empty, and flagged.
        console.showInspectorTab(0)
        controller.addCue(.title)
        save(console, "console-new-cue", to: directory)

        // An anagram cue in the editor.
        if let anagram = controller.addCue(.anagram) {
            controller.updateCue(anagram, "Change Anagrams") { cue in
                cue.content = .anagram(AnagramContent(anagrams: [
                    Anagram(text: "O, Draconian devil!", working: ["Dracula? No.", "LEONARDO"], answer: "Leonardo da Vinci!"),
                    Anagram(text: "Oh, lame saint!", answer: "The Mona Lisa!"),
                ]))
            }
            save(console, "console-edit-anagram", to: directory)
            // Its settings, set in a hand.
            controller.setSetting(.font, to: .font("Noteworthy"), for: anagram)
            console.showInspectorTab(1)
            save(console, "console-cue-settings-anagram", to: directory)

            // In show mode, each anagram on GO: the first solved, through
            // its working, and the second standing by in the cue's place.
            controller.setSetting(.advance, to: .advance(.eachAnagram), for: anagram)
            controller.setSetting(.font, to: .font(""), for: anagram)
            // Each GO with its own cue point, the second typed in the Cue tab
            // with that GO standing by.
            controller.updateCue(anagram, "Change GO Cue Point") { cue in
                cue.setCuePoint("SOPHIE: \u{201C}It\u{2019}s an anagram.\u{201D}", ofGoPoint: 0)
                cue.setCuePoint("LANGDON: \u{201C}The Mona Lisa\u{2026}\u{201D}", ofGoPoint: 1)
            }
            console.showInspectorTab(0)
            controller.standBy(anagram, step: 1)
            save(console, "console-edit-go-cue-point", to: directory)
            controller.enterShowMode()
            controller.standBy(anagram)
            let fired = CACurrentMediaTime()
            controller.go()
            controller.tick(at: fired + 1)
            controller.go()
            for i in 1...1200 { controller.tick(at: fired + 1 + Double(i) / 60) }
            save(console, "console-show-anagram-waiting", to: directory)

        }

        // A morph through three drawn faces, five points matched into the
        // second, in the Cue tab and in its points window.
        controller.enterEditMode()
        console.showInspectorTab(0)
        if let morph = controller.addCue(.morph) {
            controller.updateCue(morph, "Change Label") { $0.text = "LEONARDO" }
            let faces = [(name: "first.png", wide: 0.30, eyes: 0.40), (name: "second.png", wide: 0.36, eyes: 0.46),
                         (name: "third.png", wide: 0.42, eyes: 0.50)]
            for (i, face) in faces.enumerated() {
                let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(face.name)
                try? Self.face(wide: face.wide, eyes: face.eyes, warm: i == 1).write(to: url)
                document.importMedia(from: url, into: morph, slot: .add)
            }
            let pairs = [(0.40, 0.40, 0.38, 0.46), (0.60, 0.40, 0.62, 0.46), (0.50, 0.62, 0.50, 0.68), (0.50, 0.20, 0.50, 0.22),
                         (0.50, 0.80, 0.50, 0.84)].map { MorphPair(from: PicturePoint(x: $0.0, y: $0.1), to: PicturePoint(x: $0.2, y: $0.3)) }
            controller.updateCue(morph, "Add Point") { cue in
                if case .morph(var c) = cue.content { c.pictures[1].pairs = pairs; c.pictures[2].morphMs = 1500; cue.content = .morph(c) }
            }
            // The strip's thumbnails are made in the background.
            console.refresh()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            save(console, "console-edit-morph", to: directory)
            console.showPoints(for: morph)
            for window in NSApp.windows where window.title.hasPrefix("Morph Points") {
                if let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.layoutSubtreeIfNeeded()
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: directory).appendingPathComponent("morph-points.png"))
                }
            }
        }

        // A map cue on a drawn street map: a start, a stop reached by road
        // through a corner, and one by a jump, with coordinates. In the Cue
        // tab, and in its route window.
        if let map = controller.addCue(.map) {
            controller.updateCue(map, "Change Header") { $0.text = "OPERATION NIGHTJAR \u{2014} LIVE TRACK" }
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("streets.png")
            try? Self.streets().write(to: url)
            document.importMedia(from: url, into: map)
            func at(_ x: Double, _ y: Double) -> PicturePoint { PicturePoint(x: x, y: y) }
            controller.updateCue(map, "Set Route") { cue in
                guard case .map(var c) = cue.content else { return }
                c.route = [
                    RoutePoint(at: at(0.2, 0.3), stop: MapStop(status: "PARKED", place: "SOHO SQUARE")),
                    RoutePoint(at: at(0.5, 0.3)),
                    RoutePoint(at: at(0.5, 0.6), stop: MapStop(travelMs: 6000, place: "KING\u{2019}S CROSS")),
                    RoutePoint(at: at(0.8, 0.75), stop: MapStop(arrival: .jump, status: "STOPPED", place: "CANARY WHARF")),
                ]
                c.reference = MapReference(a: MapAnchor(at: at(0.1, 0.1), latitude: 51.53, longitude: -0.16),
                                           b: MapAnchor(at: at(0.9, 0.9), latitude: 51.49, longitude: -0.06))
                cue.content = .map(c)
            }
            console.refresh()
            RunLoop.main.run(until: Date().addingTimeInterval(1.0))
            console.refresh()
            save(console, "console-edit-map", to: directory)
            // The stage itself, full size, partway along the road: following
            // the dot, and held still.
            var still = controller.show[map]
            if var cue = still { SettingKey.camera.set(.camera(.still), in: &cue); still = cue }
            for (cue, name) in [(controller.show[map], "map-stage"), (still, "map-stage-still")] {
                guard let cue else { continue }
                let stage = SurfaceLayer(role: .live)
                stage.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
                stage.contentsScale = 1
                stage.updateInset()
                let renderer = MapRenderer(media: { [weak document] in document?.mediaURL($0) })
                renderer.mount(on: stage)
                renderer.setVisible(true, on: stage)
                var ready = false
                renderer.onReady = { ready = true }
                renderer.prepare(cue, show: controller.show.settings)
                let deadline = Date().addingTimeInterval(10)
                while !ready, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
                // 4.2 s into the drive, just as the dot lights.
                _ = renderer.paint(at: 4200.0 / Double(cue.timing.clockMs))
                func display(_ layer: CALayer) {
                    layer.displayIfNeeded()
                    layer.sublayers?.forEach(display)
                }
                display(stage)
                if let ctx = CGContext(data: nil, width: 1920, height: 1080, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    stage.render(in: ctx)
                    if let image = ctx.makeImage() {
                        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                            .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
                    }
                }
            }
            console.showRoute(for: map)
            for window in NSApp.windows where window.title.hasPrefix("Map Route") {
                window.contentView?.layoutSubtreeIfNeeded()
                if let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: directory).appendingPathComponent("map-route.png"))
                }
            }
        }

        // Prospect › Settings.
        // Its content is SwiftUI, which sizes itself as it lays out, so it
        // is laid out before it is measured.
        let preferences = PreferencesWindowController()
        preferences.window?.contentView?.layoutSubtreeIfNeeded()
        if let view = preferences.window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("settings.png"))
        }

        exit(0)
    }

    /// A printed street map, light, 2400 x 1500: a grid of streets of two
    /// widths, a river across the bottom, and a park.
    private static func streets() -> Data {
        let w = 2400, h = 1500
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.96, green: 0.94, blue: 0.89, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0.78, green: 0.86, blue: 0.74, alpha: 1))
        ctx.fill(CGRect(x: 1500, y: 900, width: 300, height: 260))
        ctx.setStrokeColor(CGColor(red: 0.55, green: 0.70, blue: 0.85, alpha: 1))
        ctx.setLineWidth(70)
        ctx.move(to: CGPoint(x: 0, y: 260))
        ctx.addCurve(to: CGPoint(x: CGFloat(w), y: 180), control1: CGPoint(x: 800, y: 500), control2: CGPoint(x: 1600, y: 0))
        ctx.strokePath()
        ctx.setStrokeColor(CGColor(gray: 0.35, alpha: 1))
        for (i, x) in stride(from: 120, to: w, by: 240).enumerated() {
            ctx.setLineWidth(i % 3 == 0 ? 16 : 7)
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x + (i % 2 == 0 ? 60 : -40), y: h))
            ctx.strokePath()
        }
        for (i, y) in stride(from: 150, to: h, by: 225).enumerated() {
            ctx.setLineWidth(i % 2 == 0 ? 16 : 7)
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: w, y: y + (i % 3 == 0 ? 50 : -30)))
            ctx.strokePath()
        }
        return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    }

    /// A simple drawn face for a morph: a head, two eyes and a mouth.
    private static func face(wide: Double, eyes: Double, warm: Bool) -> Data {
        let w = 800, h = 1000
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Core Graphics measures from the bottom; the face is set out from the top.
        func y(_ fromTop: Double) -> CGFloat { CGFloat(1 - fromTop) * CGFloat(h) }
        ctx.setFillColor(warm ? CGColor(red: 0.30, green: 0.22, blue: 0.14, alpha: 1) : CGColor(red: 0.12, green: 0.16, blue: 0.24, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(warm ? CGColor(red: 0.86, green: 0.70, blue: 0.52, alpha: 1) : CGColor(red: 0.78, green: 0.74, blue: 0.68, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: CGFloat(0.5 - wide) * CGFloat(w), y: y(0.84), width: CGFloat(wide * 2) * CGFloat(w), height: y(0.2) - y(0.84)))
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        for x in [0.5 - wide / 3, 0.5 + wide / 3] {
            ctx.fillEllipse(in: CGRect(x: CGFloat(x) * CGFloat(w) - 30, y: y(eyes) - 20, width: 60, height: 40))
        }
        ctx.fill(CGRect(x: CGFloat(w) * 0.42, y: y(eyes + 0.24) - 8, width: CGFloat(w) * 0.16, height: 16))
        return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:]) ?? Data()
    }

    /// A short show to photograph: three places, each a decryption, its
    /// picture (none yet, so its label on black), and a blank.
    private static func sheet() -> Show {
        let places = [("THE LOUVRE", "PARIS", "VITRUVIAN"),
                      ("SAINT-SULPICE", "PARIS", "ROSELINE"),
                      ("CHATEAU VILLETTE", "VERSAILLES", "SANGREAL")]
        var cues: [Cue] = []
        for (place, city, key) in places {
            cues.append(Cue(number: "\(cues.count + 1)", content: .title(TitleContent(text: place, sub: city, key: key))))
            cues.append(Cue(number: "\(cues.count + 1)", content: .image(ImageContent(text: place))))
            cues.append(Cue(number: "\(cues.count + 1)", content: .blank(BlankContent())))
        }
        return Show(title: "The Da Vinci Code", cues: cues)
    }

    private static func save(_ console: ConsoleWindowController, _ name: String, to directory: String) {
        guard let view = console.window?.contentView else { return }
        console.refresh()
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        // Drawn as the window's own appearance, or the dynamic colours
        // resolve against whatever was last current and the console comes
        // out light-on-light.
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: rep)
        }

        // Layer-hosting views aren't drawn by cacheDisplay, so the preview's
        // surface is rendered into its place.
        if let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext {
            let preview = console.preview
            let frame = preview.convert(preview.bounds, to: view)
            func display(_ layer: CALayer) {
                layer.displayIfNeeded()
                layer.sublayers?.forEach(display)
            }
            display(preview.surface)
            context.saveGState()
            // The view is flipped; Core Animation draws from the bottom.
            context.translateBy(x: frame.minX, y: view.bounds.height - frame.maxY)
            preview.surface.render(in: context)
            context.restoreGState()
        }
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
