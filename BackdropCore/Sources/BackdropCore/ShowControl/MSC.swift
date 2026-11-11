/// MIDI Show Control: the theatre standard for sending cues as MIDI
/// system exclusive messages.
///
///     F0 7F <device> 02 <format> <command> <data> F7
///
/// Each receiver has a device ID, 0 to 111, and acts only on messages sent
/// to it or to all devices (127). The command format says what kind of
/// equipment a message is for. Backdrop answers to the video formats and to
/// All Types, so a lighting desk sending MSC for its own cue 12 doesn't fire
/// projection cue 12.
public enum MSC {
    /// Device IDs a receiver can have.
    public static let deviceIDs: ClosedRange<Int> = 0...111

    /// The command in a MIDI Show Control message, if it is one Backdrop
    /// answers: GO, with or without a cue number; LOAD, which stands a cue
    /// by; ALL OFF, which blacks out; and RESTORE, which brings the picture
    /// back. The message may come with or without its F0 and F7.
    public static func command(in message: [UInt8], deviceID: Int) -> RemoteCommand? {
        var bytes = message[...]
        if bytes.first == 0xF0 { bytes = bytes.dropFirst() }
        if bytes.last == 0xF7 { bytes = bytes.dropLast() }
        guard bytes.count >= 5 else { return nil }
        let header = Array(bytes.prefix(5))
        guard header[0] == 0x7F, header[2] == 0x02 else { return nil }
        guard Int(header[1]) == deviceID || header[1] == allDevices else { return nil }
        guard videoFormats.contains(header[3]) || header[3] == allTypes else { return nil }
        let data = Array(bytes.dropFirst(5))
        switch header[4] {
        case 0x01:
            guard let number = cueNumber(in: data) else { return nil }
            return .go(cue: number.isEmpty ? nil : number)
        case 0x05:
            guard let number = cueNumber(in: data), !number.isEmpty else { return nil }
            return .standBy(cue: number)
        case 0x08:
            return .blackout(true)
        case 0x09:
            return .blackout(false)
        default:
            return nil
        }
    }

    /// The device ID that addresses every device.
    static let allDevices: UInt8 = 0x7F
    /// The command format meaning every kind of equipment.
    static let allTypes: UInt8 = 0x7F
    /// Video, from General to Shutter Controls, by way of Projectors.
    static let videoFormats: ClosedRange<UInt8> = 0x30...0x37

    /// A message's cue number, up to the zero before its cue list: ASCII
    /// digits and decimal points only, as the standard allows. Empty for
    /// none; nil for anything else.
    static func cueNumber(in data: [UInt8]) -> String? {
        let number = data.prefix { $0 != 0 }
        guard number.allSatisfy({ (0x30...0x39).contains($0) || $0 == 0x2E }) else { return nil }
        return String(decoding: number, as: UTF8.self)
    }

    /// A message that sends a command: for the debug check, and for tests.
    public static func message(deviceID: Int, format: UInt8 = 0x30, command: UInt8, cue: String? = nil) -> [UInt8] {
        [0xF0, 0x7F, UInt8(deviceID), 0x02, format, command] + Array((cue ?? "").utf8) + [0xF7]
    }
}
