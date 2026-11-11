#if DEBUG
import AppKit
import BackdropCore
import BackdropStage
import CoreMIDI
import Network

/// Debug builds only: turns show control on, sends Backdrop real OSC over
/// the network and real MSC from a virtual MIDI source, checks the show does
/// what each asks, and writes what it found to result.txt.
///
///     Backdrop.app/Contents/MacOS/Backdrop -BackdropShowControlCheck /some/folder
///
/// The show is in memory and never saved, and the settings are left alone,
/// so nothing on disk or in Open Recent changes.
@MainActor
enum ShowControlCheck {
    private static var lines: [String] = []
    private static var failed = false

    private static func check(_ ok: Bool, _ what: String) {
        lines.append((ok ? "PASS  " : "FAIL  ") + what)
        if !ok { failed = true }
    }

    static func run(in directory: String) {
        let folder = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Task {
            await steps()
            try? (lines.joined(separator: "\n") + "\n").write(to: folder.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
            exit(failed ? 1 : 0)
        }
    }

    /// Waits for a condition, giving up after a few seconds.
    private static func until(_ seconds: Double = 3, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > end { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    private static func steps() async {
        let cues = ["THE LOUVRE", "SAINT-SULPICE", "ROSSLYN CHAPEL"].enumerated().map { i, text in
            Cue(number: String(i + 1), content: .title(TitleContent(text: text)))
        }
        let document = ShowDocument(show: Show(title: "Show control check", cues: cues), warnings: [])
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        guard let controller = document.controller, let console = document.console else {
            check(false, "the show opens")
            return
        }
        controller.enterShowMode()
        func live() -> String? { controller.playhead.live.flatMap { controller.show[$0]?.number } }
        func standby() -> String? { controller.playhead.standby.flatMap { controller.show[$0]?.number } }
        func message() -> String { controller.message ?? "nothing" }

        let control = ShowControl.shared
        control.onCommand = { command, source in controller.perform(command, from: source) }
        let port = Int.random(in: 53_200...53_899)
        control.configure(msc: 1, osc: port)

        // OSC, over the network to this Mac.
        check(await until { control.oscState == .listening }, "OSC listens on port \(port)")
        let sender = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(port))!, using: .udp)
        sender.start(queue: .main)
        func osc(_ address: String, _ arguments: [OSCMessage.Argument] = []) {
            sender.send(content: Data(OSCMessage(address, arguments).encoded()), completion: .idempotent)
        }
        osc("/backdrop/go")
        check(await until { live() == "1" }, "/backdrop/go fires the cue standing by")
        check(message() == "Cue 1 fired by OSC from this Mac.", "the status line says what fired it: \(message())")
        osc("/backdrop/go/3")
        check(await until { live() == "3" }, "/backdrop/go/3 fires cue 3")
        osc("/backdrop/standby", [.string("2")])
        check(await until { standby() == "2" } && live() == "3", "/backdrop/standby with 2 stands cue 2 by, and fires nothing")
        osc("/backdrop/blackout/on")
        check(await until { controller.playhead.blackout }, "/backdrop/blackout/on blacks out")
        osc("/backdrop/blackout/off")
        check(await until { !controller.playhead.blackout }, "/backdrop/blackout/off brings the picture back")
        controller.enterEditMode()
        osc("/backdrop/go")
        check(await until { message().hasPrefix("Ignored GO, which arrived by OSC from this Mac:") } && live() == "3",
              "in edit mode, /backdrop/go fires nothing and says so: \(message())")
        controller.enterShowMode()

        // A port another app has.
        var blocker: OSCInput? = OSCInput(port: port + 1)
        check(await until { blocker?.state == .listening }, "a second listener takes port \(port + 1)")
        control.configure(msc: 1, osc: port + 1)
        check(await until { control.oscState == .portInUse }, "Backdrop sees that port \(port + 1) is taken")
        check(await until {
            console.booth().warnings(mode: controller.mode, projector: controller.projector)
                .contains { $0.hasPrefix("Backdrop can\u{2019}t take OSC on port \(port + 1), because another app is using it.") }
        }, "the console warns that the port is taken")
        blocker = nil
        control.configure(msc: 1, osc: port)
        check(await until { control.oscState == .listening }, "back on port \(port)")
        check(await until { console.booth().showControl == nil }, "and the warning goes")

        // MSC, from a MIDI source that appears after Backdrop started listening.
        var client = MIDIClientRef()
        var source = MIDIEndpointRef()
        guard MIDIClientCreateWithBlock("Backdrop check" as CFString, &client, nil) == noErr,
              MIDISourceCreateWithProtocol(client, "Backdrop Check" as CFString, ._1_0, &source) == noErr else {
            check(false, "a virtual MIDI source can be made")
            return
        }
        defer {
            MIDIEndpointDispose(source)
            MIDIClientDispose(client)
        }
        check(await until { control.midiSources.contains("Backdrop Check") }, "MSC is listened for on a MIDI source as soon as it appears")
        func msc(_ message: [UInt8]) {
            let words = UMP.sysEx7Words(message)
            var list = MIDIEventList()
            withUnsafeMutablePointer(to: &list) { pointer in
                let packet = MIDIEventListInit(pointer, ._1_0)
                words.withUnsafeBufferPointer { buffer in
                    _ = MIDIEventListAdd(pointer, MemoryLayout<MIDIEventList>.size, packet, 0, buffer.count, buffer.baseAddress!)
                }
                MIDIReceivedEventList(source, pointer)
            }
        }
        controller.standBy(number: "1")
        msc(MSC.message(deviceID: 1, command: 0x01, cue: "1"))
        check(await until { live() == "1" }, "MSC GO 1 fires cue 1")
        check(message() == "Cue 1 fired by MIDI Show Control from Backdrop Check.", "the status line says what fired it: \(message())")
        msc(MSC.message(deviceID: 2, command: 0x01, cue: "3"))
        msc(MSC.message(deviceID: 1, format: 0x01, command: 0x01, cue: "3"))
        try? await Task.sleep(for: .milliseconds(300))
        check(live() == "1", "MSC for another device, or for lighting, fires nothing")
        msc(MSC.message(deviceID: 1, command: 0x05, cue: "3"))
        check(await until { standby() == "3" } && live() == "1", "MSC LOAD 3 stands cue 3 by, and fires nothing")
        msc(MSC.message(deviceID: 0x7F, command: 0x01))
        check(await until { live() == "3" }, "MSC GO for all devices, with no number, fires the cue standing by")
        msc(MSC.message(deviceID: 1, command: 0x08))
        check(await until { controller.playhead.blackout }, "MSC ALL OFF blacks out")
        msc(MSC.message(deviceID: 1, command: 0x09))
        check(await until { !controller.playhead.blackout }, "MSC RESTORE brings the picture back")
        msc(MSC.message(deviceID: 1, command: 0x01, cue: "12.25"))
        check(await until { message() == "GO for cue 12.25 arrived by MIDI Show Control from Backdrop Check, but no cue is numbered 12.25." },
              "an MSC message in two packets is put back together, and GO for a cue not in the sheet fires nothing: \(message())")

        // Off.
        control.configure(msc: nil, osc: nil)
        check(control.midiSources.isEmpty && control.oscState == nil, "turning show control off lets go of MIDI and the port")
        controller.standBy(number: "1")
        msc(MSC.message(deviceID: 1, command: 0x01))
        osc("/backdrop/go")
        try? await Task.sleep(for: .milliseconds(300))
        check(live() == "3", "with show control off, nothing fires")
        sender.cancel()
    }
}
#endif
