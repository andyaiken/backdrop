import Foundation

/// When each part of a cue starts, for a cue that waits partway for GO, as an
/// anagram cue's working can.
///
/// Such a cue runs in parts. The first starts on frame 0, when the hold ends;
/// each after it waits for GO, or a GO can jump straight to any of them. The cue knows how long each part takes, and
/// where within its part everything it does sets off; this keeps when each
/// part was let go.
public struct GoTimeline: Equatable, Sendable {
    public private(set) var starts = [0]
    /// The frames each part takes, from its start until the last thing in it
    /// has finished.
    public let parts: [Int]

    public init(parts: [Int]) {
        self.parts = parts
    }

    /// Whether any part still waits for GO.
    public var hasPartsLeft: Bool { starts.count < parts.count }

    /// When the parts let go so far have all finished.
    private var end: Int { starts[starts.count - 1] + parts[starts.count - 1] }

    /// Done everything it can by frame `f`, with more still to come on GO.
    public func isWaiting(at f: Int) -> Bool {
        hasPartsLeft && f >= end
    }

    /// Every part has run, and the last has finished.
    public func isFinished(at f: Int) -> Bool {
        !hasPartsLeft && f >= end
    }

    /// GO on frame `f`: the next part starts then, or as soon as the part
    /// before it has finished, if that is later, so nothing jumps.
    public mutating func carryOn(at f: Int) {
        guard hasPartsLeft else { return }
        starts.append(max(f, end))
    }

    /// Every part let go, each straight after the one before, as when the
    /// cue is put up finished.
    public mutating func carryOnToEnd() {
        while hasPartsLeft { starts.append(end) }
    }

    /// GO straight to part `p` on frame `f`, forward or back: every part
    /// before it finished at once, as if each had run straight after the one
    /// before and the last had just ended, and part `p` starting then, or
    /// when the hold ends if that is later. Part 0 is the cue from its start,
    /// which a jump never needs.
    public mutating func jump(toPart p: Int, at f: Int) {
        guard p > 0, parts.indices.contains(p) else { return }
        var starts = Array(repeating: 0, count: p + 1)
        starts[p] = max(f, 0)
        var end = f
        for i in stride(from: p - 1, through: 0, by: -1) {
            starts[i] = end - parts[i]
            end = starts[i]
        }
        self.starts = starts
    }

    /// The frame something `offset` frames into `part` sets off; nil while
    /// that part waits for GO.
    public func start(part: Int, offset: Int) -> Int? {
        starts.indices.contains(part) ? starts[part] + offset : nil
    }
}
