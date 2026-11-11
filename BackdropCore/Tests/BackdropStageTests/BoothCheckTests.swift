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

@Suite("Booth warnings")
struct BoothCheckTests {
    @Test("A Mac in good order says nothing")
    func allClear() {
        #expect(BoothConditions().warnings(mode: .show, projector: .fullScreen(epson)).isEmpty)
        #expect(BoothConditions().warnings(mode: .show, projector: .closed).isEmpty)
    }

    @Test("Show mode warns of everything, most urgent first")
    func showMode() {
        let said = everything.warnings(mode: .show, projector: .fullScreen(epson))
        #expect(said.count == 5)
        #expect(said[0] == "Another app is in front, so Space won\u{2019}t fire GO. Click this window to bring Backdrop back.")
        #expect(said[1] == "This Mac is running on battery (64%). Plug it in: if the battery runs down, the Mac sleeps and the projector goes dark.")
        #expect(said[2].hasPrefix("This Mac is running hot"))
        #expect(said[3].hasPrefix("Low Power Mode is on"))
        #expect(said[4].hasPrefix("The show is on \u{201C}SHOW DRIVE\u{201D}, not this Mac\u{2019}s internal disk."))
    }

    @Test("Edit mode leaves the night's warnings for show mode")
    func editMode() {
        #expect(everything.warnings(mode: .edit, projector: .fullScreen(epson)).isEmpty)
        // But where the picture goes matters in either.
        var mirrored = everything
        mirrored.consoleMirrored = true
        #expect(mirrored.warnings(mode: .edit, projector: .closed).count == 1)
        #expect(everything.warnings(mode: .edit, projector: .windowed(.noSecondDisplay))
                == [ProjectorState.windowed(.noSecondDisplay).warning!])
    }

    @Test("The projector's own warning comes first, before the night's")
    func projectorFirst() {
        let waiting = ProjectorState.waiting(for: epson.identity)
        let said = everything.warnings(mode: .show, projector: waiting)
        #expect(said.first == waiting.warning)
        #expect(said.count == 6)
    }

    @Test("Mirroring takes the place of the projector's warning, which would mislead")
    func mirroring() {
        let mirrored = BoothConditions(consoleMirrored: true)
        let windowed = mirrored.warnings(mode: .show, projector: .windowed(.noSecondDisplay))
        #expect(windowed == ["The display this window is on is mirrored, so the projector has no display of its own and the audience may be seeing this window. Turn mirroring off in System Settings \u{203A} Displays, then close the projector and open it again."])
        // A projector waiting for its display, or windowed while it's
        // missing, goes back by itself once mirroring is off.
        for state in [ProjectorState.waiting(for: epson.identity), .windowed(.displayMissing(epson.identity)), .closed] {
            let said = mirrored.warnings(mode: .show, projector: state)
            #expect(said.count == 1)
            #expect(said[0].hasSuffix("Turn mirroring off in System Settings \u{203A} Displays."))
        }
    }

    @Test("A port show control can't have is said in either mode, after the projector")
    func showControl() {
        let taken = BoothConditions(power: .battery(percent: 50), showControl: .oscPortInUse(53100))
        #expect(taken.warnings(mode: .edit, projector: .closed)
                == ["Backdrop can\u{2019}t take OSC on port 53100, because another app is using it. Choose another port in Backdrop\u{2019}s Settings, and send to that."])
        let said = taken.warnings(mode: .show, projector: .windowed(.noSecondDisplay))
        #expect(said.count == 3)
        #expect(said[1].hasPrefix("Backdrop can\u{2019}t take OSC on port 53100"))
        #expect(BoothConditions(showControl: .oscPortUnavailable(80)).warnings(mode: .edit, projector: .closed)
                == ["Backdrop can\u{2019}t take OSC on port 80. Choose another port in Backdrop\u{2019}s Settings, and send to that."])
    }

    @Test("Battery without a reading, and the other kinds of heat and disk")
    func variants() {
        #expect(BoothConditions(power: .battery(percent: nil)).warnings(mode: .show, projector: .closed)
                == ["This Mac is running on battery. Plug it in: if the battery runs down, the Mac sleeps and the projector goes dark."])
        #expect(BoothConditions(heat: .critical).warnings(mode: .show, projector: .closed).first?.hasPrefix("This Mac is overheating") == true)
        #expect(BoothConditions(showDisk: .network("Production")).warnings(mode: .show, projector: .closed)
                == ["The show is on the server \u{201C}Production\u{201D}. If the network drops, cues can\u{2019}t load their pictures and clips. Copy the show onto this Mac."])
    }
}
