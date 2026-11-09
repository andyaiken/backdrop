import Foundation

/// Where a layered cue's frame looks, as a function of the step.
///
/// A frame is a share of the picture, and the picture keeps its own shape on
/// the stage, so a frame is as wide a share as it is high: a square of
/// shares, `size` on each side. Padding keeps the part off the edge, and a
/// cap on how close the frame comes stops a cue that describes a single hand
/// from pushing in absurdly far.
public enum LayeredFraming {
    /// The whole picture.
    public static let whole = PictureRect(x: 0, y: 0, width: 1, height: 1)

    /// The share of a part's size added round it on each side.
    public static let padding = 0.08

    /// The frame that shows `part`: padded, as close as `zoom` allows, and
    /// kept on the picture.
    public static func frame(framing part: PictureRect, zoom: Int) -> PictureRect {
        let closest = 1 / Double(max(zoom, 1))
        let size = min(1, max(closest, max(part.width, part.height) * (1 + 2 * padding)))
        let x = min(max(part.x + part.width / 2 - size / 2, 0), 1 - size)
        let y = min(max(part.y + part.height / 2 - size / 2, 0), 1 - size)
        return PictureRect(x: x, y: y, width: size, height: size)
    }

    /// The smallest rect holding every rect given.
    static func union(_ rects: [PictureRect]) -> PictureRect? {
        guard let first = rects.first else { return nil }
        let minX = rects.map(\.x).min() ?? first.x, minY = rects.map(\.y).min() ?? first.y
        let maxX = rects.map { $0.x + $0.width }.max() ?? 1, maxY = rects.map { $0.y + $0.height }.max() ?? 1
        return PictureRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension LayeredContent {
    /// The frame at the end of each step: the part that step brings on,
    /// from the layer's own frame if it has one and otherwise its opaque
    /// bounds. A step that only takes a layer off pulls back to whatever the
    /// step before it framed, and a part with nothing to frame leaves the
    /// frame where it was. A still camera never leaves the whole picture.
    ///
    /// - Parameter bounds: Each layer's opaque bounds, nil where unknown.
    public func frames(bounds: [PictureRect?], camera: LayeredCamera, zoom: Int) -> [PictureRect] {
        let all = steps
        guard camera != .still else { return all.map { _ in LayeredFraming.whole } }
        var previous = LayeredFraming.whole
        return all.map { step in
            let parts = step.arriving.compactMap { layers[$0].frame ?? (bounds.indices.contains($0) ? bounds[$0] : nil) }
            if let part = LayeredFraming.union(parts) { previous = LayeredFraming.frame(framing: part, zoom: zoom) }
            return previous
        }
    }

    /// The frame once step `k` has run, `k` below 0 being before any step.
    /// A function of the step alone, so a jump either way lands on it.
    public func frame(after k: Int, frames: [PictureRect]) -> PictureRect {
        frames.indices.contains(k) ? frames[k] : LayeredFraming.whole
    }
}
