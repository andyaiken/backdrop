import Foundation
import Testing
@testable import BackdropCore

/// Bytes written out as an OSC packet is laid out, four to a row.
private func bytes(_ rows: [UInt8]...) -> [UInt8] { rows.flatMap { $0 } }
private func text(_ s: String) -> [UInt8] {
    var b = Array(s.utf8) + [0]
    while b.count % 4 != 0 { b.append(0) }
    return b
}

@Suite("OSC")
struct OSCTests {
    @Test("A message with no arguments, as QLab sends /backdrop/go")
    func bare() {
        // A message with no type tags at all, from before OSC 1.0, reads too.
        #expect(OSCMessage.parse(text("/backdrop/go") + text(",")) == [OSCMessage("/backdrop/go")])
        #expect(OSCMessage.parse(text("/backdrop/go")) == [OSCMessage("/backdrop/go")])
    }

    @Test("Each kind of argument, read in order")
    func arguments() {
        let packet = bytes(text("/x"), text(",ifsTFNd"),
                           [0, 0, 0, 12], [0x41, 0x48, 0, 0], text("P12"), [0x40, 0x29, 0, 0, 0, 0, 0, 0])
        #expect(OSCMessage.parse(packet) == [OSCMessage("/x", [.int(12), .float(12.5), .string("P12"), .bool(true), .bool(false), .other, .double(12.5)])])
    }

    @Test("Blobs, time tags and arrays are stepped over")
    func skipped() {
        let packet = bytes(text("/x"), text(",b[t]s"), [0, 0, 0, 5], [1, 2, 3, 4, 5, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 1], text("after"))
        #expect(OSCMessage.parse(packet) == [OSCMessage("/x", [.other, .other, .string("after")])])
    }

    @Test("Every message in a bundle, and in a bundle inside it")
    func bundles() {
        let go = OSCMessage("/backdrop/go").encoded()
        let standby = OSCMessage("/backdrop/standby", [.string("4")]).encoded()
        let inner = text("#bundle") + [UInt8](repeating: 0, count: 8) + [0, 0, 0, UInt8(standby.count)] + standby
        let outer = text("#bundle") + [UInt8](repeating: 0, count: 8)
            + [0, 0, 0, UInt8(go.count)] + go + [0, 0, 0, UInt8(inner.count)] + inner
        #expect(OSCMessage.parse(outer) == [OSCMessage("/backdrop/go"), OSCMessage("/backdrop/standby", [.string("4")])])
    }

    @Test("Garbled and truncated packets are refused")
    func refused() {
        #expect(OSCMessage.parse([]) == nil)
        #expect(OSCMessage.parse(Array("hello".utf8)) == nil)
        // An integer promised and not sent.
        #expect(OSCMessage.parse(text("/x") + text(",i") + [0, 0]) == nil)
        // A bundle element longer than the bundle.
        #expect(OSCMessage.parse(text("#bundle") + [UInt8](repeating: 0, count: 8) + [0, 0, 0, 99] + text("/x")) == nil)
        // A type Backdrop doesn't know, whose size it can't step over.
        #expect(OSCMessage.parse(text("/x") + text(",q") + [0, 0, 0, 0]) == nil)
    }

    @Test("What Backdrop sends reads back the same")
    func roundTrip() {
        let message = OSCMessage("/backdrop/go", [.string("12.5"), .int(-3), .float(1.25), .double(2.5), .bool(true), .bool(false)])
        #expect(OSCMessage.parse(message.encoded()) == [message])
    }
}

@Suite("OSC commands")
struct OSCCommandTests {
    private func command(_ address: String, _ arguments: [OSCMessage.Argument] = []) -> RemoteCommand? {
        RemoteCommand(osc: OSCMessage(address, arguments))
    }

    @Test("GO, for the cue standing by or for a cue by number")
    func go() {
        #expect(command("/backdrop/go") == .go(cue: nil))
        #expect(command("/backdrop/go/12.5") == .go(cue: "12.5"))
        #expect(command("/backdrop/go/P12") == .go(cue: "P12"))
        #expect(command("/backdrop/go", [.string("P12")]) == .go(cue: "P12"))
        #expect(command("/backdrop/go", [.int(12)]) == .go(cue: "12"))
        #expect(command("/backdrop/go", [.float(12.5)]) == .go(cue: "12.5"))
        #expect(command("/backdrop/go", [.float(12)]) == .go(cue: "12"))
        #expect(command("/backdrop/go", [.float(1.1)]) == .go(cue: "1.1"))
        #expect(command("/Backdrop/GO") == .go(cue: nil))
    }

    @Test("Standby needs a number; blackout says which way")
    func others() {
        #expect(command("/backdrop/standby/4") == .standBy(cue: "4"))
        #expect(command("/backdrop/standby", [.string("4")]) == .standBy(cue: "4"))
        #expect(command("/backdrop/standby") == nil)
        #expect(command("/backdrop/standby", [.string("  ")]) == nil)
        #expect(command("/backdrop/blackout/on") == .blackout(true))
        #expect(command("/backdrop/blackout/off") == .blackout(false))
        #expect(command("/backdrop/blackout") == nil)
    }

    @Test("Anything else isn't Backdrop's")
    func notOurs() {
        #expect(command("/go") == nil)
        #expect(command("/cue/12/go") == nil)
        #expect(command("/backdrop") == nil)
        #expect(command("/backdrop/fire/12") == nil)
        #expect(command("/backdrop/go/12/now") == nil)
    }
}

@Suite("System exclusive in Universal MIDI Packets")
struct UMPTests {
    @Test("A short message fits one packet; a long one is split and put back together")
    func roundTrip() {
        let short = MSC.message(deviceID: 1, command: 0x01)
        #expect(UMP.sysEx7Words(short).count == 2)
        var assembler = SysEx7Assembler()
        #expect(assembler.receive(UMP.sysEx7Words(short)) == [Array(short.dropFirst().dropLast())])

        let long = MSC.message(deviceID: 1, command: 0x01, cue: "123.45")
        let words = UMP.sysEx7Words(long)
        #expect(words.count == 4)
        #expect(words[0] >> 20 & 0xF == 1 && words[2] >> 20 & 0xF == 3)
        #expect(assembler.receive(words) == [Array(long.dropFirst().dropLast())])
    }

    @Test("Packets split across deliveries, with other messages between them")
    func acrossDeliveries() {
        let message = MSC.message(deviceID: 1, command: 0x05, cue: "1234567.5")
        let words = UMP.sysEx7Words(message)
        #expect(words.count == 6)
        var assembler = SysEx7Assembler()
        let noteOn: UInt32 = 0x2090_3C64
        #expect(assembler.receive([words[0], words[1], noteOn]).isEmpty)
        #expect(assembler.receive([words[2], words[3]]).isEmpty)
        #expect(assembler.receive(words[4...]) == [Array(message.dropFirst().dropLast())])
    }

    @Test("A continuation with no start, and a dump too long for MSC, are dropped")
    func dropped() {
        let words = UMP.sysEx7Words(MSC.message(deviceID: 1, command: 0x01, cue: "123.45"))
        var assembler = SysEx7Assembler()
        #expect(assembler.receive(words[2...]).isEmpty)

        let dump = [UInt8](repeating: 0x10, count: 600)
        #expect(assembler.receive(UMP.sysEx7Words([0xF0] + dump + [0xF7])).isEmpty)
        // And the next message still comes through.
        #expect(assembler.receive(UMP.sysEx7Words(MSC.message(deviceID: 1, command: 0x08))).count == 1)
    }
}

@Suite("MIDI Show Control")
struct MSCTests {
    @Test("GO, with and without a cue number, and with a cue list after it")
    func go() {
        #expect(MSC.command(in: MSC.message(deviceID: 1, command: 0x01), deviceID: 1) == .go(cue: nil))
        #expect(MSC.command(in: MSC.message(deviceID: 1, command: 0x01, cue: "12.5"), deviceID: 1) == .go(cue: "12.5"))
        let withList: [UInt8] = [0xF0, 0x7F, 1, 0x02, 0x30, 0x01] + Array("12".utf8) + [0] + Array("3".utf8) + [0xF7]
        #expect(MSC.command(in: withList, deviceID: 1) == .go(cue: "12"))
        // As CoreMIDI's newer API delivers it, without the F0 and F7.
        #expect(MSC.command(in: [0x7F, 1, 0x02, 0x30, 0x01] + Array("7".utf8), deviceID: 1) == .go(cue: "7"))
    }

    @Test("LOAD stands a cue by; ALL OFF and RESTORE black out and back")
    func others() {
        #expect(MSC.command(in: MSC.message(deviceID: 1, command: 0x05, cue: "4"), deviceID: 1) == .standBy(cue: "4"))
        #expect(MSC.command(in: MSC.message(deviceID: 1, command: 0x05), deviceID: 1) == nil)
        #expect(MSC.command(in: MSC.message(deviceID: 1, command: 0x08), deviceID: 1) == .blackout(true))
        #expect(MSC.command(in: MSC.message(deviceID: 1, command: 0x09), deviceID: 1) == .blackout(false))
        // STOP, RESUME and the rest mean nothing to Backdrop.
        #expect(MSC.command(in: MSC.message(deviceID: 1, command: 0x02, cue: "4"), deviceID: 1) == nil)
    }

    @Test("Only for this device, or for all of them")
    func device() {
        #expect(MSC.command(in: MSC.message(deviceID: 2, command: 0x01), deviceID: 1) == nil)
        #expect(MSC.command(in: MSC.message(deviceID: 0x7F, command: 0x01), deviceID: 1) == .go(cue: nil))
        #expect(MSC.command(in: MSC.message(deviceID: 0, command: 0x01), deviceID: 0) == .go(cue: nil))
    }

    @Test("Only for video, or for every kind of equipment: not the lighting desk's cues")
    func format() {
        #expect(MSC.command(in: MSC.message(deviceID: 1, format: 0x01, command: 0x01, cue: "12"), deviceID: 1) == nil)
        #expect(MSC.command(in: MSC.message(deviceID: 1, format: 0x10, command: 0x01, cue: "12"), deviceID: 1) == nil)
        #expect(MSC.command(in: MSC.message(deviceID: 1, format: 0x32, command: 0x01, cue: "12"), deviceID: 1) == .go(cue: "12"))
        #expect(MSC.command(in: MSC.message(deviceID: 1, format: 0x7F, command: 0x01, cue: "12"), deviceID: 1) == .go(cue: "12"))
    }

    @Test("Other system exclusive messages, and cue numbers MSC doesn't allow, are refused")
    func refused() {
        #expect(MSC.command(in: [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7], deviceID: 1) == nil)
        #expect(MSC.command(in: [0xF0, 0x7F, 1, 0x02, 0xF7], deviceID: 1) == nil)
        #expect(MSC.command(in: MSC.message(deviceID: 1, command: 0x01, cue: "P12"), deviceID: 1) == nil)
    }
}
