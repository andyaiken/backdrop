import Foundation

/// What another machine in the booth can ask of the show: QLab, a lighting
/// desk, or anything else that speaks MIDI Show Control or OSC. Only the
/// show keys that make sense from afar, and only in show mode; see
/// `ShowController.perform(_:from:)`.
public enum RemoteCommand: Equatable, Sendable {
    /// GO: the cue standing by, or with a number, that cue.
    case go(cue: String?)
    /// Stand a cue by, by number.
    case standBy(cue: String)
    /// Blackout on or off.
    case blackout(Bool)

    /// What the command is, for the status line, mid-sentence.
    public var name: String {
        switch self {
        case .go(nil): "GO"
        case .go(let cue?): "GO for cue \(cue)"
        case .standBy(let cue): "standby for cue \(cue)"
        case .blackout(true): "blackout"
        case .blackout(false): "blackout off"
        }
    }
}

extension RemoteCommand {
    /// The command an OSC message asks for, if it is one of Backdrop's:
    ///
    ///     /backdrop/go              GO for the cue standing by
    ///     /backdrop/go/12           GO for cue 12
    ///     /backdrop/standby/12      stand cue 12 by
    ///     /backdrop/blackout/on     blackout
    ///     /backdrop/blackout/off    the picture back
    ///
    /// A cue number may come as the message's first argument instead, as
    /// `/backdrop/go 12`: a string, an integer or a float.
    public init?(osc message: OSCMessage) {
        let parts = message.address.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2, parts.count <= 3, parts[0].lowercased() == "backdrop" else { return nil }
        let number = parts.count == 3 ? parts[2] : message.arguments.first?.cueNumber
        switch parts[1].lowercased() {
        case "go":
            self = .go(cue: number)
        case "standby":
            guard let number else { return nil }
            self = .standBy(cue: number)
        case "blackout":
            switch parts.count == 3 ? parts[2].lowercased() : nil {
            case "on": self = .blackout(true)
            case "off": self = .blackout(false)
            default: return nil
            }
        default:
            return nil
        }
    }
}

extension OSCMessage.Argument {
    /// The argument read as a cue number. A float is written as briefly as
    /// it can be, so 12.5 is "12.5" and 12.0 is "12".
    var cueNumber: String? {
        switch self {
        case .string(let s):
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .int(let i): return String(i)
        case .float(let f): return f.rounded() == f && abs(f) < 1e9 ? String(Int(f)) : String(f)
        case .double(let d): return d.rounded() == d && abs(d) < 1e15 ? String(Int(d)) : String(d)
        case .bool, .other: return nil
        }
    }
}
