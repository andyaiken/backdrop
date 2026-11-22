/// Where a command from outside the console came from: another machine in
/// the booth, over OSC or MIDI Show Control, or a shortcut on this Mac.
public struct CommandSource: Equatable, Sendable, CustomStringConvertible {
    public enum Kind: Equatable, Sendable {
        case osc, msc, shortcut
    }

    public let kind: Kind
    /// The sender: an address for OSC, a MIDI source's name for MSC.
    /// Empty for a shortcut.
    public let name: String

    public init(kind: Kind, name: String) {
        self.kind = kind
        self.name = name
    }

    public static func osc(_ sender: String) -> CommandSource { CommandSource(kind: .osc, name: sender) }
    public static func msc(_ source: String) -> CommandSource { CommandSource(kind: .msc, name: source) }
    public static let shortcut = CommandSource(kind: .shortcut, name: "")

    /// As the status line says it: "OSC from 10.0.0.12".
    public var description: String {
        switch kind {
        case .osc: "OSC from \(name)"
        case .msc: "MIDI Show Control from \(name)"
        case .shortcut: "a shortcut"
        }
    }

    /// The badge beside the status line.
    public var badge: String {
        switch kind {
        case .osc: "OSC"
        case .msc: "MSC"
        case .shortcut: "SHORTCUT"
        }
    }
}
