import Foundation

/// How the stage changes from whatever is on it to a cue.
public enum TransitionStyle: String, Codable, CaseIterable, Sendable {
    /// The old picture goes and the new one appears at once.
    case snap
    /// The old picture fades out to black, then the new one fades in.
    case fade
    /// The old picture dissolves into the new one, which is already running
    /// underneath. The only style that depends on the outgoing cue.
    case crossfade
    /// The new cue, already running, is uncovered from one side or corner,
    /// the old picture wiped off the stage ahead of it. Depends on the
    /// outgoing cue, as a crossfade does.
    case wipe
}

/// The side or corner of the stage a wipe starts from.
public enum WipeEdge: String, Codable, CaseIterable, Sendable {
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight

    /// How far a point has come to being wiped, from 0 at the side or corner
    /// the wipe starts from to 1 at the far side or corner. `u` runs from
    /// the left of the stage to the right, and `v` from the top to the bottom,
    /// each from 0 to 1.
    public func progress(u: Double, v: Double) -> Double {
        switch self {
        case .left: u
        case .right: 1 - u
        case .top: v
        case .bottom: 1 - v
        case .topLeft: (u + v) / 2
        case .topRight: ((1 - u) + v) / 2
        case .bottomLeft: (u + (1 - v)) / 2
        case .bottomRight: ((1 - u) + (1 - v)) / 2
        }
    }

    /// The part of the stage a wipe has yet to reach when it is `done` of the
    /// way across (0 to 1), as a polygon in the same unit square `u` and `v`
    /// measure. Empty once the wipe is complete.
    public func remaining(after done: Double) -> [CGPoint] {
        guard done < 1 else { return [] }
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        let inside = { (p: CGPoint) in progress(u: p.x, v: p.y) - done }
        var out: [CGPoint] = []
        for (i, a) in square.enumerated() {
            let b = square[(i + 1) % square.count]
            let da = inside(a), db = inside(b)
            if da >= 0 { out.append(a) }
            if (da >= 0) != (db >= 0) {
                let t = da / (da - db)
                out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        return out.count < 3 ? [] : out
    }
}

/// The transition into a cue.
public struct Transition: Codable, Equatable, Sendable {
    public var style: TransitionStyle
    /// The length of each fade: out, then in; or of a whole crossfade. Unused by a snap.
    public var fadeMs: Int
    /// Where a wipe starts from. Unused by the other styles.
    public var wipeFrom: WipeEdge

    public init(style: TransitionStyle = .fade, fadeMs: Int = 500, wipeFrom: WipeEdge = .left) {
        self.style = style
        self.fadeMs = fadeMs
        self.wipeFrom = wipeFrom
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Transition.standard
        style = try c.value(.style, d.style)
        fadeMs = try c.value(.fadeMs, d.fadeMs, in: SettingRange.fadeMs)
        wipeFrom = try c.value(.wipeFrom, d.wipeFrom)
    }

    /// What a new cue changes with.
    public static let standard = Transition()

    public var fadeSeconds: Double { Double(fadeMs) / 1000 }

    /// Whether the style has a length to set.
    public var hasLength: Bool { style != .snap }
}
