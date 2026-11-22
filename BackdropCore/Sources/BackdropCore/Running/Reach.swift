import Foundation

/// A cue one GO sets running, and how it was reached.
public struct Reach: Equatable, Sendable {
    public enum Via: Equatable, Sendable {
        /// The GO itself.
        case go
        /// This long after the cue before it fired.
        case after(ms: Int)
        /// When the cue before it finished, after this wait.
        case whenFinished(waitMs: Int)
    }

    public var cue: Cue
    public var via: Via

    public init(cue: Cue, via: Via) {
        self.cue = cue
        self.via = via
    }
}

extension Show {
    /// The cues one GO on `id` sets running: that cue, then each cue after
    /// it while the one before continues by itself. It stops at a cue that
    /// waits for GO, at the end of the sheet, and before a cue waiting for
    /// one that never finishes, as a looping clip doesn't. Empty if `id`
    /// isn't in the sheet.
    public func reach(from id: UUID) -> [Reach] {
        guard let start = index(of: id) else { return [] }
        var reached = [Reach(cue: cues[start], via: .go)]
        var i = start
        while i + 1 < cues.count {
            let before = cues[i]
            let via: Reach.Via
            switch before.continueMode {
            case .whenCued: return reached
            case .after(let ms): via = .after(ms: ms)
            case .whenFinished(let wait):
                if before.neverFinishes { return reached }
                via = .whenFinished(waitMs: wait)
            }
            i += 1
            reached.append(Reach(cue: cues[i], via: via))
        }
        return reached
    }
}
