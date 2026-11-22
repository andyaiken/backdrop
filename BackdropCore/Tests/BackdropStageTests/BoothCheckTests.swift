import CoreGraphics
import BackdropCore
import Testing
@testable import BackdropStage

private let epson = DisplayInfo(
    identity: DisplayIdentity(uuid: "EPSON-1", name: "EPSON PJ", vendor: 19_539, model: 1),
    frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), isMain: false)

/// Everything that can go wrong on the night, at once.
private let everything = BoothConditions(inBackground: true, power: .battery(percent: 64), lowPowerMode: true,
                                         heat: .throttled, showDisk: .external("SHOW DRIVE"))

extension BoothConditions {
    /// The messages alone, in order.
    fileprivate func said(mode: ShowController.Mode, projector: ProjectorState) -> [String] {
        warnings(mode: mode, projector: projector).map(\.message)
    }
}

@Suite("Booth warnings")
struct BoothCheckTests {
    @Test("A Mac in good order says nothing")
    func allClear() {
        #expect(BoothConditions().said(mode: .show, projector: .fullScreen(epson)).isEmpty)
        #expect(BoothConditions().said(mode: .show, projector: .closed).isEmpty)
    }

    @Test("Show mode warns of everything, most urgent first")
    func showMode() {
        let said = everything.said(mode: .show, projector: .fullScreen(epson))
        #expect(said.count == 5)
        #expect(said[0] == "Another app is in front, so Space won\u{2019}t fire GO. Click this window to bring Backdrop back.")
        #expect(said[1] == "This Mac is running on battery (64%). Plug it in: if the battery runs down, the Mac sleeps and the projector goes dark.")
        #expect(said[2].hasPrefix("This Mac is running hot"))
        #expect(said[3].hasPrefix("Low Power Mode is on"))
        #expect(said[4].hasPrefix("The show is on \u{201C}SHOW DRIVE\u{201D}, not this Mac\u{2019}s internal disk."))
    }

    @Test("Edit mode leaves the night's warnings for show mode")
    func editMode() {
        #expect(everything.said(mode: .edit, projector: .fullScreen(epson)).isEmpty)
        // But where the picture goes matters in either.
        var mirrored = everything
        mirrored.consoleMirrored = true
        #expect(mirrored.said(mode: .edit, projector: .closed).count == 1)
        #expect(everything.said(mode: .edit, projector: .windowed(.noSecondDisplay))
                == [ProjectorState.windowed(.noSecondDisplay).warning!])
    }

    @Test("The projector's own warning comes first of the cautions, before the night's")
    func projectorFirst() {
        let waiting = ProjectorState.waiting(for: epson.identity)
        let said = everything.said(mode: .show, projector: waiting)
        // After the one stop, another app in front.
        #expect(said[1] == waiting.warning)
        #expect(said.count == 6)
    }

    @Test("Mirroring takes the place of the projector's warning, which would mislead")
    func mirroring() {
        let mirrored = BoothConditions(consoleMirrored: true)
        let windowed = mirrored.said(mode: .show, projector: .windowed(.noSecondDisplay))
        #expect(windowed == ["The display this window is on is mirrored, so the projector has no display of its own and the audience may be seeing this window. Turn mirroring off in System Settings \u{203A} Displays, then close the projector and open it again."])
        // A projector waiting for its display, or windowed while it's
        // missing, goes back by itself once mirroring is off.
        for state in [ProjectorState.waiting(for: epson.identity), .windowed(.displayMissing(epson.identity)), .closed] {
            let said = mirrored.said(mode: .show, projector: state)
            #expect(said.count == 1)
            #expect(said[0].hasSuffix("Turn mirroring off in System Settings \u{203A} Displays."))
        }
    }

    @Test("A port show control can't have is said in either mode, after the projector")
    func showControl() {
        let taken = BoothConditions(power: .battery(percent: 50), showControl: .oscPortInUse(53100))
        #expect(taken.said(mode: .edit, projector: .closed)
                == ["Backdrop can\u{2019}t take OSC on port 53100, because another app is using it. Choose another port in Backdrop\u{2019}s Settings, and send to that."])
        let said = taken.said(mode: .show, projector: .windowed(.noSecondDisplay))
        #expect(said.count == 3)
        #expect(said[1].hasPrefix("Backdrop can\u{2019}t take OSC on port 53100"))
        #expect(BoothConditions(showControl: .oscPortUnavailable(80)).said(mode: .edit, projector: .closed)
                == ["Backdrop can\u{2019}t take OSC on port 80. Choose another port in Backdrop\u{2019}s Settings, and send to that."])
    }

    @Test("Battery without a reading, and the other kinds of heat and disk")
    func variants() {
        #expect(BoothConditions(power: .battery(percent: nil)).said(mode: .show, projector: .closed)
                == ["This Mac is running on battery. Plug it in: if the battery runs down, the Mac sleeps and the projector goes dark."])
        #expect(BoothConditions(heat: .critical).said(mode: .show, projector: .closed).first?.hasPrefix("This Mac is overheating") == true)
        #expect(BoothConditions(showDisk: .network("Production")).said(mode: .show, projector: .closed)
                == ["The show is on the server \u{201C}Production\u{201D}. If the network drops, cues can\u{2019}t load their pictures and clips. Copy the show onto this Mac."])
    }

    @Test("Each warning has its tier, and each caution its lamp")
    func tiers() {
        func only(_ c: BoothConditions, _ projector: ProjectorState = .closed) -> BoothWarning? {
            c.warnings(mode: .show, projector: projector).first
        }
        #expect(only(BoothConditions(inBackground: true))?.tier == .stop)
        #expect(only(BoothConditions(inBackground: true))?.lamp == nil)
        #expect(only(BoothConditions(consoleMirrored: true))?.tier == .stop)
        #expect(only(BoothConditions(heat: .critical))?.tier == .stop)
        let cautions: [(BoothWarning?, String)] = [
            (only(BoothConditions(heat: .throttled)), "Hot"),
            (only(BoothConditions(power: .battery(percent: 64))), "Battery 64%"),
            (only(BoothConditions(power: .battery(percent: nil))), "Battery"),
            (only(BoothConditions(lowPowerMode: true)), "Low Power"),
            (only(BoothConditions(showDisk: .external("SHOW DRIVE"))), "On SHOW DRIVE"),
            (only(BoothConditions(showDisk: .network("Production"))), "On a server"),
            (only(BoothConditions(showControl: .oscPortInUse(53100))), "OSC port"),
            (only(BoothConditions(), .standIn(epson, for: epson.identity)), "Stand-in display"),
            (only(BoothConditions(), .windowed(.noSecondDisplay)), "In a window"),
            (only(BoothConditions(), .windowed(.displayMissing(epson.identity))), "In a window"),
            (only(BoothConditions(), .waiting(for: epson.identity)), "Disconnected"),
        ]
        for (warning, lamp) in cautions {
            #expect(warning?.tier == .caution)
            #expect(warning?.lamp == lamp)
        }
        var main = epson
        main.isMain = true
        #expect(only(BoothConditions(), .fullScreen(main))?.lamp == "Banners")
    }

    @Test("Stops come before cautions, whatever order they were found in")
    func stopsFirst() {
        let said = BoothConditions(power: .battery(percent: 10), heat: .critical)
            .warnings(mode: .show, projector: .windowed(.noSecondDisplay))
        #expect(said.map(\.tier) == [.stop, .caution, .caution])
        #expect(said[0].id == .overheating)
        #expect(said[1].id == .inAWindow)
    }

    @Test("Beginners: a Mac in good order is fine on every row")
    func checklistFine() {
        let checks = BoothConditions().checklist(mode: .show, projector: .fullScreen(epson),
                                                 showControl: ShowControlStatus(mscDevice: 1, oscPort: 53100),
                                                 issues: [], arm: nil)
        #expect(checks.allSatisfy { $0.state == .fine })
        #expect(checks.map(\.text) == [
            "Projector live on EPSON PJ", "Displays aren\u{2019}t mirrored", "Backdrop is in front: Space fires GO",
            "On mains power", "Running cool", "Low Power Mode is off", "Show is on this Mac\u{2019}s internal disk",
            "MSC listening as device 1", "OSC listening on port 53100", "Cue sheet has no issues",
        ])
    }

    @Test("Beginners: the projector closed is a stop, with the lamp's words")
    func checklistProjectorClosed() {
        let checks = BoothConditions().checklist(mode: .show, projector: .closed, showControl: ShowControlStatus(),
                                                 issues: [], arm: nil)
        #expect(checks[0] == BoothCheck(id: .projector, state: .stop, text: "Projector closed"))
        #expect(!checks.contains { $0.id == .msc || $0.id == .osc }, "show control that is off isn't listed")
    }

    @Test("Beginners: an OSC port that is taken says why")
    func checklistOSC() {
        let checks = BoothConditions(showControl: .oscPortInUse(53100))
            .checklist(mode: .show, projector: .fullScreen(epson), showControl: ShowControlStatus(oscPort: 53100),
                       issues: [], arm: nil)
        let osc = checks.first { $0.id == .osc }
        #expect(osc?.state == .caution)
        #expect(osc?.text.hasPrefix("Backdrop can\u{2019}t take OSC on port 53100") == true)
    }

    @Test("Beginners: issues in the sheet are counted, with their words as detail")
    func checklistIssues() {
        let checks = BoothConditions().checklist(mode: .show, projector: .fullScreen(epson), showControl: ShowControlStatus(),
                                                 issues: ["Cue 3 has no picture.", "Cue 7 has no clip."], arm: nil)
        let sheet = checks.first { $0.id == .cueSheet }
        #expect(sheet == BoothCheck(id: .cueSheet, state: .caution, text: "2 issues in the cue sheet",
                                    detail: "Cue 3 has no picture.\nCue 7 has no clip."))
        let one = BoothConditions().checklist(mode: .show, projector: .fullScreen(epson), showControl: ShowControlStatus(),
                                              issues: ["Cue 3 has no picture."], arm: nil)
        #expect(one.first { $0.id == .cueSheet }?.text == "1 issue in the cue sheet")
    }

    @Test("Beginners: a video standing by, arming and then armed")
    func checklistArming() {
        func armRow(_ state: ArmState, feed: Bool = false) -> BoothCheck? {
            BoothConditions().checklist(mode: .show, projector: .fullScreen(epson), showControl: ShowControlStatus(),
                                        issues: [], arm: (number: "4", isFeed: feed, state: state)).last
        }
        #expect(armRow(.arming) == BoothCheck(id: .armed, state: .caution, text: "Video loading \u{2014} not armed yet"))
        #expect(armRow(.arming, feed: true)?.text == "Camera connecting \u{2014} not armed yet")
        #expect(armRow(.armed) == BoothCheck(id: .armed, state: .fine, text: "Cue 4 armed"))
        #expect(armRow(.failed("gone"))?.text == "No clip \u{2014} this cue goes to black")
    }
}
