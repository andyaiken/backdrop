import BackdropCore
import CoreGraphics
import QuartzCore

/// How a live picture is turned, mirrored and fitted, once, for the layers
/// and for the still a crossfade takes.
enum FeedPicture {
    /// The turn and mirror as a layer transform. Mirroring is of the picture
    /// itself, before the turn, so a mirrored picture turned a quarter is the
    /// same one turned, not one flipped the other way. Layer y runs up the
    /// stage, so a clockwise turn is a negative angle.
    static func transform(_ settings: FeedSettings) -> CATransform3D {
        let mirror = CATransform3DMakeScale(settings.mirror ? -1 : 1, 1, 1)
        let turn = CATransform3DMakeRotation(-CGFloat(settings.rotation.rawValue) * .pi / 180, 0, 0, 1)
        return CATransform3DConcat(mirror, turn)
    }

    /// The picture as the audience sees it, drawn into `size` pixels on black.
    static func render(_ image: CGImage, size: CGSize, settings: FeedSettings) -> CGImage? {
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w >= 1, h >= 1,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        let iw = Double(image.width), ih = Double(image.height)
        let sideways = settings.rotation.isSideways
        let turnedW = sideways ? ih : iw, turnedH = sideways ? iw : ih
        let fitScale = min(Double(w) / turnedW, Double(h) / turnedH)
        let fillScale = max(Double(w) / turnedW, Double(h) / turnedH)
        let scale = settings.fit == .fit ? fitScale : fillScale

        // Last call first: the picture is mirrored, then turned, then
        // scaled, then centred.
        ctx.translateBy(x: Double(w) / 2, y: Double(h) / 2)
        ctx.scaleBy(x: scale, y: scale)
        ctx.rotate(by: -Double(settings.rotation.rawValue) * .pi / 180)
        ctx.scaleBy(x: settings.mirror ? -1 : 1, y: 1)
        ctx.draw(image, in: CGRect(x: -iw / 2, y: -ih / 2, width: iw, height: ih))
        return ctx.makeImage()
    }
}
