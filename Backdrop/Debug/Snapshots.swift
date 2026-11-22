#if DEBUG
import AppKit
import BackdropCore
import BackdropStage
import QuartzCore
import SwiftUI

/// Debug builds only: renders the console offscreen to PNGs and quits, so its
/// layout can be looked at without driving the screen.
///
///     Backdrop.app/Contents/MacOS/Backdrop -BackdropSnapshot /some/folder
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
        // A Mac in good order, whatever this one is doing: launched from the
        // command line, Backdrop isn't even the app in front.
        console.booth = { BoothConditions() }
        console.window?.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 860), display: false)
        controller.enterShowMode()
        let start = CACurrentMediaTime()

        // Cue 1 fired and settled, the video standing by.
        controller.go()
        for i in 1...720 { controller.tick(at: start + Double(i) / 60) }
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
        saveVariants(console, "console-edit", to: directory)
        controller.standBy(controller.show.cues[5].id)
        save(console, "console-edit-image", to: directory)
        // The Inspector's other forms: the image cue's transition in, then
        // Stage setup.
        console.cueList.onTransitionClick(controller.show.cues[5].id)
        save(console, "console-edit-transition", to: directory)
        console.showStageSetup()
        save(console, "console-show-settings", to: directory)
        console.cueList.onClick(controller.show.cues[5].id)

        // The image cue with settings of its own.
        let image = controller.show.cues[5].id
        controller.setSetting(.grid, to: .number(20), for: image)
        controller.setSetting(.order, to: .order(.spiral), for: image)
        controller.setSetting(.reveal, to: .reveal(.sharpen), for: image)
        save(console, "console-cue-settings", to: directory)
        // Wide enough that the inspector stands beside the preview.
        console.window?.setFrame(NSRect(x: 0, y: 0, width: 1700, height: 980), display: false)
        save(console, "console-wide-cue", to: directory)
        console.window?.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 860), display: false)
        // A decryption cue whose letters are on dials.
        let decryption = controller.show.cues[4].id
        controller.setSetting(.letters, to: .letters(.dials), for: decryption)
        controller.standBy(decryption)
        save(console, "console-cue-settings-decryption", to: directory)

        // A cue just added: every field empty, and flagged.
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
            save(console, "console-cue-settings-anagram", to: directory)

            // In show mode, each anagram on GO: the first solved, through
            // its working, and the second standing by in the cue's place.
            controller.setSetting(.advance, to: .advance(.eachAnagram), for: anagram)
            controller.setSetting(.font, to: .font(""), for: anagram)
            // Each GO with its own cue point, the second typed in the Inspector
            // with that GO standing by.
            controller.updateCue(anagram, "Change GO Cue Point") { cue in
                cue.setCuePoint("SOPHIE: \u{201C}It\u{2019}s an anagram.\u{201D}", ofGoPoint: 0)
                cue.setCuePoint("LANGDON: \u{201C}The Mona Lisa\u{2026}\u{201D}", ofGoPoint: 1)
            }
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
        // second, in the Inspector and in its points window.
        controller.enterEditMode()
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
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            saveVariants(console, "studio-morph-focus", to: directory)
            console.closeFocusForSnapshot()
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
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            saveVariants(console, "studio-map-focus", to: directory)
            console.closeFocusForSnapshot()
        }

        // A cascade cue in the Inspector, with a message on GO, finished in the
        // preview; then with no message, its rain falling in the preview.
        if let cascade = controller.addCue(.cascade) {
            controller.updateCue(cascade, "Change Message") { $0.text = "WAKE UP\nNEO" }
            controller.setSetting(.advance, to: .advance(.eachStep), for: cascade)
            controller.setSetting(.columns, to: .number(36), for: cascade)
            // Run on stage, and given its GO: the rain, then the message.
            controller.runSelected()
            var start = CACurrentMediaTime()
            for i in 1...120 { controller.tick(at: start + Double(i) / 30) }
            controller.runner.carryOn(at: start + 4)
            for i in 1...300 { controller.tick(at: start + 4 + Double(i) / 30) }
            save(console, "console-edit-cascade", to: directory)
            controller.updateCue(cascade, "Change Message") { $0.text = "" }
            controller.runSelected()
            // In real time: rain never settles, so the console's own display
            // link keeps ticking it too, and a made-up clock would lose.
            start = CACurrentMediaTime()
            while CACurrentMediaTime() < start + 4 {
                controller.tick(at: CACurrentMediaTime())
                RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 30))
            }
            save(console, "console-edit-cascade-rain", to: directory)
        }

        // Backdrop › Settings.
        // Its content is SwiftUI, which sizes itself as it lays out, so it
        // is laid out before it is measured.
        let preferences = PreferencesWindowController()
        preferences.window?.contentView?.layoutSubtreeIfNeeded()
        if let view = preferences.window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("settings.png"))
        }

        booth(to: directory)
        studio(to: directory)
        wordmark(to: directory)
        exit(0)
    }

    /// The Booth, in each of its states, on a short sheet of its own: a title,
    /// an anagram that waits for a GO partway, a video with no clip, a picture
    /// that runs on into the next cue, a text and a blank.
    private static func booth(to directory: String) {
        var steps = AnagramContent(anagrams: [
            Anagram(text: "LISTEN", answer: "SILENT"),
            Anagram(text: "THE EYES", answer: "THEY SEE"),
        ])
        steps.settings.advance = .eachAnagram
        var cues = [
            Cue(number: "1", line: "House to half. Lights fade on the keeper\u{2019}s cottage.",
                content: .title(TitleContent(text: "THE LAST LIGHT", sub: "A play in two acts", key: "LANTERN"))),
            Cue(number: "2", line: "TOM: \u{201C}The combination, Mara. Quickly.\u{201D}", content: .anagram(steps)),
            Cue(number: "3", line: "The clip rolls.", content: .video(VideoContent(text: "CRYPTEX", sub: "REVEAL", src: "media/cryptex.mov"))),
            Cue(number: "4", line: "Thunder. A door slams offstage.", content: .image(ImageContent(text: "Storm"))),
            Cue(number: "5", line: "MARA: \u{201C}Morning.\u{201D}", content: .text(TextContent(text: "Six weeks later"))),
            Cue(number: "6", content: .blank(BlankContent())),
        ]
        cues[3].continueMode = .after(ms: 3000)
        let document = ShowDocument(show: Show(title: "The Last Light", cues: cues), warnings: [])
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        guard let controller = document.controller, let console = document.console else { exit(1) }
        console.booth = { BoothConditions() }
        console.showControl = { ShowControlStatus() }
        console.window?.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 860), display: false)
        controller.enterShowMode()
        let ids = controller.show.cues.map(\.id)
        saveVariants(console, "booth-beginners", to: directory)

        // Cue 1 fired and settled; the anagram, with its step, standing by.
        var clock = CACurrentMediaTime()
        controller.go()
        for i in 1...720 { controller.tick(at: clock + Double(i) / 60) }
        clock += 13
        // Thumbnails are drawn in the background, one at a time.
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        saveVariants(console, "booth-standby", to: directory)
        saveVariants(console, "rail-booth", to: directory)

        // The video standing by, with no clip to arm.
        controller.standBy(ids[2])
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        saveVariants(console, "booth-arming", to: directory)

        // The picture that runs on into cue 5: one GO runs both.
        controller.standBy(ids[3])
        saveVariants(console, "booth-reach", to: directory)
        saveVariants(console, "rail-chain", to: directory)

        controller.toggleBlackout()
        saveVariants(console, "booth-blackout", to: directory)
        controller.toggleBlackout()

        console.booth = { BoothConditions(inBackground: true) }
        saveVariants(console, "booth-stop", to: directory)
        console.booth = { BoothConditions(power: .battery(percent: 64), showDisk: .external("SHOW DRIVE")) }
        saveVariants(console, "booth-caution", to: directory)
        console.booth = { BoothConditions() }

        // Go To, with P12 typed, then after Return finds no such cue; then
        // the key help.
        console.showGoTo()
        for (character, code) in [("P", 35), ("1", 18), ("2", 19)] as [(String, UInt16)] {
            press(character, keyCode: code, in: console)
        }
        saveVariants(console, "booth-goto", to: directory)
        press("\r", keyCode: 36, in: console)
        saveVariants(console, "booth-goto-missing", to: directory)
        press("\u{1B}", keyCode: 53, in: console)
        console.toggleKeyHelp()
        saveVariants(console, "booth-keyhelp", to: directory)
        console.toggleKeyHelp()

        // GO from QLab over OSC, with show control on.
        console.showControl = { ShowControlStatus(mscDevice: 1, oscPort: 53000) }
        controller.standBy(ids[0])
        controller.perform(.go(cue: nil), from: .osc("10.0.0.12"))
        controller.tick(at: clock + 0.1)
        saveVariants(console, "booth-remote", to: directory)
        console.showControl = { ShowControlStatus() }
        controller.say(nil)

        // The end of the sheet.
        controller.standBy(ids[5])
        controller.standByNext()
        saveVariants(console, "booth-end", to: directory)

        // The smallest the window goes.
        controller.standBy(ids[1])
        console.window?.setFrame(NSRect(x: 0, y: 0, width: 900, height: 600 + 28), display: false)
        saveVariants(console, "booth-small", to: directory)

        recovery(cue: controller.show.cues[3], settings: controller.show.settings, to: directory)
        gallery(place: .after(controller.show.cues[3]), to: directory)

        // The rail in the Studio: a row under the pointer, issues, and files
        // dragged in.
        console.window?.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 860), display: false)
        controller.enterEditMode()
        controller.standBy(ids[1])
        console.refresh()
        console.cueList.pretendHovered(ids[3])
        saveVariants(console, "rail-studio-hover", to: directory)
        controller.updateCue(ids[4], "Change Number") { $0.number = "" }
        controller.updateCue(ids[5], "Change Continue") { $0.continueMode = .after(ms: 1000) }
        saveVariants(console, "rail-issues", to: directory)
        console.cueList.pretendDrop(count: 3, before: 2)
        saveVariants(console, "rail-drop-slot", to: directory)
        console.cueList.pretendDrop(count: 0, before: -1)
        railLong(to: directory)
    }

    /// A long sheet, 300 cues, and how long the rail takes to catch up: once
    /// with everything new, and again with nothing changed, which must not
    /// make its rows again.
    private static func railLong(to directory: String) {
        let kinds: [Cue.Kind] = [.title, .image, .text, .blank, .keypad, .anagram]
        var cues: [Cue] = []
        for i in 0..<300 {
            var cue = ShowController.emptyCue(kinds[i % kinds.count])
            cue.number = "\(i + 1)"
            cue.text = "CUE \(i + 1)"
            cue.line = i % 3 == 0 ? "A line for cue \(i + 1), long enough to wrap in the rail." : ""
            if i % 7 == 0 { cue.continueMode = .after(ms: 2000) }
            cues.append(cue)
        }
        let document = ShowDocument(show: Show(title: "Long", cues: cues), warnings: [])
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        guard let controller = document.controller, let console = document.console else { exit(1) }
        console.booth = { BoothConditions() }
        console.showControl = { ShowControlStatus() }
        console.window?.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 860), display: false)
        controller.enterShowMode()
        var start = CACurrentMediaTime()
        console.refresh()
        let first = CACurrentMediaTime() - start
        start = CACurrentMediaTime()
        console.refresh()
        let again = CACurrentMediaTime() - start
        let timing = String(format: "First refresh: %.1f ms\nAgain, nothing changed: %.1f ms\n", first * 1000, again * 1000)
        try? timing.write(to: URL(fileURLWithPath: directory).appendingPathComponent("rail-long.txt"), atomically: true, encoding: .utf8)
        controller.standBy(controller.show.cues[150].id)
        saveVariants(console, "rail-long", to: directory)
    }

    /// The Studio: a cue of each sort on the stage with its timeline, a
    /// transition selected, stage setup, the storyboard, issues, a new cue,
    /// and the smallest window.
    private static func studio(to directory: String) {
        var keypad = KeypadContent(text: "Safe", script: "4417\nGOOD")
        keypad.settings.pauseTicks = 14
        let cues = [
            Cue(number: "1", line: "House to half. Lights fade on the keeper\u{2019}s cottage.",
                content: .title(TitleContent(text: "THE LAST LIGHT", sub: "A play in two acts", key: "LANTERN"))),
            Cue(number: "2", line: "MARA: \u{201C}Another evening, and the sea is quiet.\u{201D}", content: .image(ImageContent(text: "Dusk"))),
            Cue(number: "3", content: .layered(LayeredContent(text: "The cottage"))),
            Cue(number: "5", line: "TOM: \u{201C}The combination, Mara. Quickly.\u{201D}", content: .keypad(keypad)),
            Cue(number: "6", content: .text(TextContent(text: "Six weeks later"))),
        ]
        let document = ShowDocument(show: Show(title: "The Last Light", cues: cues), warnings: [])
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        guard let controller = document.controller, let console = document.console else { exit(1) }
        console.booth = { BoothConditions() }
        console.showControl = { ShowControlStatus() }
        console.window?.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 860), display: false)
        controller.enterEditMode()
        let ids = controller.show.cues.map(\.id)
        if let dusk = GallerySamples.media("dusk.jpg") { document.importMedia(from: dusk, into: ids[1]) }
        func settle() {
            console.refresh()
            RunLoop.main.run(until: Date().addingTimeInterval(1))
        }
        for (id, name) in [(ids[0], "studio-title"), (ids[1], "studio-image"), (ids[2], "studio-layered"), (ids[3], "studio-keypad")] {
            controller.standBy(id)
            settle()
            saveVariants(console, name, to: directory)
        }
        console.cueList.onTransitionClick(ids[1])
        saveVariants(console, "studio-transition", to: directory)
        console.cueList.onClick(ids[1])
        console.setStageSetup(true)
        controller.setGeometry(Geometry(width: 62, height: 62, across: 10, down: -3))
        saveVariants(console, "studio-stage-setup", to: directory)
        console.setStageSetup(false)
        console.showStoryboardForSnapshot(true)
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        saveVariants(console, "studio-storyboard", to: directory)
        console.showStoryboardForSnapshot(false)
        controller.updateCue(ids[4], "Change Number") { $0.number = "" }
        saveVariants(console, "studio-issues", to: directory)
        controller.addCue(.title)
        saveVariants(console, "studio-new-cue", to: directory)
        console.window?.setFrame(NSRect(x: 0, y: 0, width: 900, height: 600 + 28), display: false)
        controller.standBy(ids[0])
        saveVariants(console, "studio-small", to: directory)

        // A show with no cues: the bare stage.
        let empty = ShowDocument(show: Show(title: "New Show"), warnings: [])
        NSDocumentController.shared.addDocument(empty)
        empty.makeWindowControllers()
        guard let blank = empty.controller, let bare = empty.console else { return }
        bare.booth = { BoothConditions() }
        bare.window?.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 860), display: false)
        blank.enterEditMode()
        bare.holdWordmark(atFrame: 14)
        saveVariants(bare, "studio-empty", to: directory)
    }

    /// The cue gallery: every kind, a search, a search that finds nothing,
    /// and every kind again under Reduce Motion. Each preview is run 2.5 s
    /// in, so the cards are caught moving.
    private static func gallery(place: GalleryPlace, to directory: String) {
        for (name, query, still) in [("gallery", "", false), ("gallery-search-safe", "safe", false),
                                     ("gallery-empty-search", "zzz", false), ("gallery-reduce-motion", "", true)] {
            GalleryPreview.forceReduceMotion = still
            let clock = GalleryClock()
            let host = NSHostingView(rootView: CueGallery(place: place, query: query, clock: clock, done: { _ in }))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let start = CACurrentMediaTime()
            for i in 0...150 {
                clock.tickAll(at: start + Double(i) / 60)
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            }
            // Pictures decode in the background; give them a moment, then
            // carry on from where the clock got to.
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            clock.tickAll(at: start + 2.5)
            render(host, name, to: directory)
            clock.stop()
            window.contentView = nil
        }
        GalleryPreview.forceReduceMotion = false
    }

    /// The sheet offered after a crash, on its own.
    private static func recovery(cue: Cue, settings: ShowSettings, to directory: String) {
        var picture: CGImage?
        var done = false
        Task { @MainActor in
            picture = await ShowThumbnail.image(of: cue, settings: settings, width: 1008, media: { _ in nil })
            done = true
        }
        let deadline = Date().addingTimeInterval(5)
        while !done, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let host = NSHostingView(rootView: RecoveryView(number: cue.number, name: CueText.name(cue),
                                                        firedAt: Date(timeIntervalSince1970: 1_700_000_000), picture: picture))
        host.appearance = Booth.appearance
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.effectiveAppearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: rep) }
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("recovery.png"))
    }

    /// A new show, with no cues, in edit mode: the wordmark on its screen in
    /// the preview's place, partway through decrypting, once for each way a
    /// title's letters can find their way home.
    private static func wordmark(to directory: String) {
        let document = ShowDocument(show: Show(), warnings: [])
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        guard let controller = document.controller, let console = document.console else { exit(1) }
        console.booth = { BoothConditions() }
        console.window?.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 860), display: false)
        controller.enterEditMode()
        for letters in TitleLetters.allCases {
            console.holdWordmark(atFrame: 14, letters: letters)
            save(console, "console-wordmark-\(letters.rawValue)", to: directory)
        }
    }

    /// A printed street map, light, 2400 x 1500: a grid of streets of two
    /// widths, a river across the bottom, and a park.
    static func streets() -> Data {
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

    /// A key pressed in the console, as the keyboard sends it, to whatever
    /// has the keyboard there.
    private static func press(_ characters: String, keyCode: UInt16, in console: ConsoleWindowController) {
        guard let window = console.window,
              let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, characters: characters,
                                           charactersIgnoringModifiers: characters.lowercased(), isARepeat: false,
                                           keyCode: keyCode) else { return }
        window.firstResponder?.keyDown(with: event)
    }

    /// A state three times, as on a Mac in light mode, in dark mode, and in
    /// dark mode with Increase Contrast: `name.png`, `name-dark.png` and
    /// `name-hc.png`. The Booth is dark in all three; the Studio follows.
    private static func saveVariants(_ console: ConsoleWindowController, _ name: String, to directory: String) {
        let variants: [(suffix: String, appearance: NSAppearance.Name, contrast: Bool)] = [
            ("", .aqua, false), ("-dark", .darkAqua, false), ("-hc", .accessibilityHighContrastDarkAqua, true),
        ]
        let before = NSApp.appearance
        for variant in variants {
            NSApp.appearance = NSAppearance(named: variant.appearance)
            Booth.forcedContrast = variant.contrast
            save(console, name + variant.suffix, to: directory)
        }
        NSApp.appearance = before
        Booth.forcedContrast = nil
        console.refresh()
    }

    private static func save(_ console: ConsoleWindowController, _ name: String, to directory: String) {
        guard let view = console.window?.contentView else { return }
        console.refresh()
        render(view, name, to: directory)
    }

    /// A view as it stands, with every stage surface in it painted into its
    /// place.
    private static func render(_ view: NSView, _ name: String, to directory: String) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        // Drawn as the window's own appearance, or the dynamic colours
        // resolve against whatever was last current and the console comes
        // out light-on-light.
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: rep)
        }

        // Layer-hosting views aren't drawn by cacheDisplay, so each stage
        // surface showing, the previews' and the wordmark's, is rendered into
        // its place.
        if let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext {
            func display(_ layer: CALayer) {
                layer.displayIfNeeded()
                layer.sublayers?.forEach(display)
            }
            for host in surfaces(in: view) {
                guard let surface = host.layer as? SurfaceLayer else { continue }
                let frame = host.convert(host.bounds, to: view)
                display(surface)
                context.saveGState()
                // Go To and the key help sit over the previews: the surfaces
                // aren't painted where they are, so they stay on top.
                let overlays = view.subviews.filter { $0 is GoToPanel || $0 is KeyHelp }
                if !overlays.isEmpty {
                    let keep = CGMutablePath()
                    keep.addRect(view.bounds)
                    for overlay in overlays {
                        let f = overlay.frame
                        keep.addRect(CGRect(x: f.minX, y: view.bounds.height - f.maxY, width: f.width, height: f.height))
                    }
                    context.addPath(keep)
                    context.clip(using: .evenOdd)
                }
                // The view is flipped; Core Animation draws from the bottom.
                context.translateBy(x: frame.minX, y: view.bounds.height - frame.maxY)
                surface.render(in: context)
                context.restoreGState()
            }
        }
        // Stage setup sits over the stage, so it is drawn again over the
        // surface just painted.
        if let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext {
            for overlay in view.subviews where !overlay.isHidden && overlay is StageSetupOverlay {
                let frame = overlay.convert(overlay.bounds, to: view)
                context.saveGState()
                context.translateBy(x: frame.minX, y: view.bounds.height - frame.minY)
                context.scaleBy(x: 1, y: -1)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
                overlay.draw(overlay.bounds)
                NSGraphicsContext.restoreGraphicsState()
                context.restoreGState()
            }
        }
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// The views showing a stage surface, anywhere under `view`.
    private static func surfaces(in view: NSView) -> [NSView] {
        view.subviews.flatMap { sub -> [NSView] in
            guard !sub.isHidden else { return [] }
            return (sub.layer is SurfaceLayer ? [sub] : []) + surfaces(in: sub)
        }
    }
}
#endif
