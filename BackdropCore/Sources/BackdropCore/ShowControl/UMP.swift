/// Universal MIDI Packets, as CoreMIDI's current API delivers MIDI: 32-bit
/// words, one to four to a message. A system exclusive message, which MIDI
/// Show Control is, comes as SysEx7 packets of two words, each carrying up
/// to six of its bytes, without the F0 and F7 that frame it on a cable.
public enum UMP {
    /// How many words a message of a type takes, from the type in its
    /// first word's top four bits.
    public static func wordCount(ofType type: UInt32) -> Int {
        switch type {
        case 0x0, 0x1, 0x2, 0x6, 0x7: 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: 2
        case 0xB, 0xC: 3
        default: 4
        }
    }

    /// A system exclusive message as SysEx7 packets in group 0. The message
    /// may come with or without its F0 and F7.
    public static func sysEx7Words(_ message: [UInt8]) -> [UInt32] {
        var bytes = message[...]
        if bytes.first == 0xF0 { bytes = bytes.dropFirst() }
        if bytes.last == 0xF7 { bytes = bytes.dropLast() }
        let chunks = stride(from: 0, to: max(bytes.count, 1), by: 6).map { start in
            Array(bytes.dropFirst(start).prefix(6))
        }
        var words: [UInt32] = []
        for (i, chunk) in chunks.enumerated() {
            let status: UInt32 = chunks.count == 1 ? 0 : i == 0 ? 1 : i == chunks.count - 1 ? 3 : 2
            let b = chunk + [UInt8](repeating: 0, count: 6 - chunk.count)
            words.append(0x3 << 28 | status << 20 | UInt32(chunk.count) << 16 | UInt32(b[0]) << 8 | UInt32(b[1]))
            words.append(UInt32(b[2]) << 24 | UInt32(b[3]) << 16 | UInt32(b[4]) << 8 | UInt32(b[5]))
        }
        return words
    }
}

/// Puts system exclusive messages back together from the SysEx7 packets
/// they arrive in, one source at a time. Everything else is skipped.
public struct SysEx7Assembler: Sendable {
    /// A message in progress: begun, not yet ended.
    private var partial: [UInt8]?

    /// Longer than any MIDI Show Control message. A long dump from a synth
    /// or a lighting desk is dropped rather than kept growing.
    static let longest = 256

    public init() {}

    /// The messages these words complete, without their F0 and F7. The words
    /// may hold several packets of any kind, as a CoreMIDI event packet does.
    public mutating func receive(_ words: some Collection<UInt32>) -> [[UInt8]] {
        var complete: [[UInt8]] = []
        var rest = words[...]
        while let first = rest.first {
            let count = UMP.wordCount(ofType: first >> 28)
            guard rest.count >= count else { break }
            let packet = Array(rest.prefix(count))
            rest = rest.dropFirst(count)
            guard first >> 28 == 0x3 else { continue }
            let size = min(Int(first >> 16 & 0xF), 6)
            let all = [UInt8(first >> 8 & 0xFF), UInt8(first & 0xFF),
                       UInt8(packet[1] >> 24), UInt8(packet[1] >> 16 & 0xFF), UInt8(packet[1] >> 8 & 0xFF), UInt8(packet[1] & 0xFF)]
            let bytes = Array(all.prefix(size))
            switch first >> 20 & 0xF {
            case 0:
                partial = nil
                complete.append(bytes)
            case 1:
                partial = bytes
            case 2:
                partial = partial.map { $0 + bytes }
            case 3:
                if let message = partial.map({ $0 + bytes }) { complete.append(message) }
                partial = nil
            default:
                partial = nil
            }
            if let p = partial, p.count > Self.longest { partial = nil }
        }
        return complete
    }
}
