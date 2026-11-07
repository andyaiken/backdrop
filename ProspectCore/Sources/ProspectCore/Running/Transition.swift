/// How the stage changes from whatever is on it to a cue.
public enum TransitionStyle: String, Codable, CaseIterable, Sendable {
    /// The old picture goes and the new one appears at once.
    case snap
    /// The old picture fades out to black, then the new one fades in.
    case fade
    /// The old picture dissolves into the new one, which is already running
    /// underneath. The only style that depends on the outgoing cue.
    case crossfade
}

/// The transition into a cue.
public struct Transition: Codable, Equatable, Sendable {
    public var style: TransitionStyle
    /// The length of each fade: out, then in; or of a whole crossfade. Unused by a snap.
    public var fadeMs: Int

    public init(style: TransitionStyle = .fade, fadeMs: Int = 500) {
        self.style = style
        self.fadeMs = fadeMs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Transition.standard
        style = try c.value(.style, d.style)
        fadeMs = try c.value(.fadeMs, d.fadeMs, in: SettingRange.fadeMs)
    }

    /// What a new cue changes with.
    public static let standard = Transition()

    public var fadeSeconds: Double { Double(fadeMs) / 1000 }

    /// Whether the style has a length to set.
    public var hasLength: Bool { style != .snap }
}
