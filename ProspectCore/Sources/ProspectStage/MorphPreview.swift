import AppKit
import Metal
import ProspectCore
import Vision

/// A morph drawn offscreen at any moment, as the stage would draw it: for
/// the console's points window, where the morph is scrubbed through while
/// its points are placed.
@MainActor
public final class MorphPreview {
    private let gpu = MorphGPU()
    private var first: (texture: MTLTexture, aspect: Double)?
    private var second: (texture: MTLTexture, aspect: Double)?

    public init() {}

    /// Whether this Mac can draw morphs at all.
    public var isAvailable: Bool { gpu != nil }

    public func setPictures(first: CGImage, second: CGImage) {
        func picture(_ image: CGImage) -> (texture: MTLTexture, aspect: Double)? {
            gpu?.texture(from: image).map { ($0, Double(image.width) / Double(max(image.height, 1))) }
        }
        self.first = picture(first)
        self.second = picture(second)
    }

    /// The morph `t` of the way through, from 0 to 1, on a stage of `size`.
    public func image(pairs: [MorphPair], at t: Double, size: CGSize) -> CGImage? {
        guard let gpu, let first, let second else { return nil }
        let mesh = MorphMesh(pairs: pairs)
        let vertices = MorphRenderer.vertices(mesh, first: first.aspect, second: second.aspect, at: t, in: size)
        return gpu.image(width: Int(size.width), height: Int(size.height)) { target in
            gpu.draw(vertices: vertices, indices: mesh.triangles, first: first.texture, second: second.texture, mix: t,
                     into: target, present: nil)
        }
    }
}

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
