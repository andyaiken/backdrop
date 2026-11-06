import CoreGraphics
import CoreImage
import Foundation
import ProspectCore

/// What the layered renderer works out from a layer's pixels.
enum LayerImages {
    /// The bounding box of a layer's opaque pixels, as shares of its width
    /// and height from the top left. For a full-frame layer with transparency
    /// that is the part being described. Nil when nothing in it is visible.
    ///
    /// Read from a small copy of its alpha, so a large layer costs little.
    static func opaqueBounds(of image: CGImage, threshold: UInt8 = 12) -> PictureRect? {
        let w = min(image.width, 256), h = max(1, min(image.height, Int((Double(w) * Double(image.height) / Double(max(image.width, 1))).rounded())))
        guard w > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
        var minX = w, minY = h, maxX = -1, maxY = -1
        // Memory holds the top row first.
        for y in 0..<h {
            for x in 0..<w where bytes[y * w + x] > threshold {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return nil }
        return PictureRect(x: Double(minX) / Double(w), y: Double(minY) / Double(h),
                           width: Double(maxX - minX + 1) / Double(w), height: Double(maxY - minY + 1) / Double(h))
    }

    /// The layer's alpha edge drawn as a line in `colour`, on transparency:
    /// what an outline entrance blooms and fades. At most 1024 across.
    static func edge(of image: CGImage, colour: CGColor) -> CGImage? {
        let scale = min(1, 1024 / Double(max(image.width, 1)))
        let source = CIImage(cgImage: image)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let radius = max(2, Double(image.width) * scale / 400)
        // The alpha alone, spread out and drawn in, leaves a ring at the edge.
        guard let alpha = CIFilter(name: "CIColorMatrix", parameters: [
            kCIInputImageKey: source,
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
        ])?.outputImage,
            let ring = CIFilter(name: "CIMorphologyGradient", parameters: [kCIInputImageKey: alpha, kCIInputRadiusKey: radius])?.outputImage,
            let tinted = CIFilter(name: "CIColorMatrix", parameters: [
                kCIInputImageKey: ring,
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: colour.components?[0] ?? 1, y: colour.components?[1] ?? 1, z: colour.components?[2] ?? 1, w: 0),
            ])?.outputImage else { return nil }
        let extent = CGRect(x: 0, y: 0, width: Double(image.width) * scale, height: Double(image.height) * scale)
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(tinted, from: extent)
    }
}
