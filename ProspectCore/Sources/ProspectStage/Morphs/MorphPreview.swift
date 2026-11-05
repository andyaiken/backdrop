import AppKit
import Metal
import ProspectCore

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
