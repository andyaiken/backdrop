import CoreGraphics
import ProspectCore
import Vision

/// The points of a face, found by Vision, for matching two faces.
public enum FacePoints {
    /// The largest face on a picture: Vision's 76 landmarks, then three
    /// points above the brow for the shape of the top of the head, as places
    /// on the picture. Nil when there is no face to find. The same feature
    /// is at the same place in the list on every face.
    public nonisolated static func find(in image: CGImage) -> [PicturePoint]? {
        let request = VNDetectFaceLandmarksRequest()
        request.constellation = .constellation76Points
        try? VNImageRequestHandler(cgImage: image).perform([request])
        guard let face = request.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }),
              let landmarks = face.landmarks?.allPoints?.normalizedPoints else { return nil }
        let box = face.boundingBox
        return landmarks.map { picturePoint($0, inFace: box) } + headPoints(of: box)
    }

    /// Vision measures a landmark across its face's box, and the box across
    /// the picture, both from the bottom left; a picture point runs from the
    /// top left.
    nonisolated static func picturePoint(_ p: CGPoint, inFace box: CGRect) -> PicturePoint {
        PicturePoint(x: Double(box.minX + p.x * box.width), y: Double(1 - (box.minY + p.y * box.height))).clamped
    }

    /// The crown and either side of it, above the face's box, where the
    /// landmarks stop at the brow.
    nonisolated static func headPoints(of box: CGRect) -> [PicturePoint] {
        let top = 1 - Double(box.maxY), h = Double(box.height), w = Double(box.width)
        return [
            PicturePoint(x: Double(box.midX), y: top - 0.35 * h),
            PicturePoint(x: Double(box.minX) - 0.05 * w, y: top - 0.15 * h),
            PicturePoint(x: Double(box.maxX) + 0.05 * w, y: top - 0.15 * h),
        ].map(\.clamped)
    }

    /// Two faces' points as pairs, feature to feature.
    public nonisolated static func pairs(_ first: [PicturePoint], _ second: [PicturePoint]) -> [MorphPair] {
        zip(first, second).map { MorphPair(from: $0, to: $1) }
    }
}
