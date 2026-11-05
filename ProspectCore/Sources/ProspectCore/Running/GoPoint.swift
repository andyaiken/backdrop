import Foundation

/// A place partway through a cue where it waits for GO, as an anagram cue's
/// working can. GO carries the cue on rather than firing the next one.
public struct GoPoint: Equatable, Sendable {
    public enum Unit: String, Sendable {
        case anagram, step
    }

    /// What it is the GO for: an anagram's turn, or a step of one.
    public var unit: Unit
    /// What GO brings on: the anagram whose turn it is, or the step it
    /// moves to.
    public var text: String

    public init(unit: Unit, text: String) {
        self.unit = unit
        self.text = text
    }
}

extension Cue {
    /// Where this cue waits for GO partway, with the settings it runs with.
    /// Only anagram cues ever do.
    public func goPoints(defaults: ShowSettings) -> [GoPoint] {
        guard case .anagram(let c) = content else { return [] }
        return c.goPoints(defaults.resolved(c.overrides).advance)
    }
}
