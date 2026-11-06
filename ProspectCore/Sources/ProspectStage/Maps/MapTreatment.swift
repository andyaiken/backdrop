import CoreImage
import CoreImage.CIFilterBuiltins
import ProspectCore
import QuartzCore

/// The look of a map cue: a police tracking terminal's phosphor green, with a
/// red dot, the only red on screen.
enum MapLook {
    /// Bright phosphor, for text and the brightest lines.
    static let phosphor = RGB(0x5C, 0xFF, 0x8A)
    /// The grid, and text that matters less.
    static let dimPhosphor = RGB(0x2E, 0x9E, 0x55)
    static let dot = RGB(0xFF, 0x2B, 0x2B)
}

/// Turns a map, as drawn or photographed, into the terminal's: done once, off
/// the main thread, as the map loads.
///
/// A light map is inverted, so its lines show bright on black. It is then
/// reduced to brightness, tinted phosphor green with the dark kept dark, given
/// a soft glow, and ruled with a faint grid that slides with it.
enum MapTreatment {
    /// The treated map. Nil only if Core Image can't draw at all.
    static func treat(_ image: CGImage) -> CGImage? {
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        var map = CIImage(cgImage: image)
        let extent = map.extent
        let grey = CIFilter.colorControls()
        grey.inputImage = map
        grey.saturation = 0
        grey.contrast = 1.15
        map = grey.outputImage ?? map
        if isLight(map, in: context) {
            let invert = CIFilter.colorInvert()
            invert.inputImage = map
            map = invert.outputImage ?? map
        }
        // Dark stays dark, so the lines glow and the ground doesn't.
        let gamma = CIFilter.gammaAdjust()
        gamma.inputImage = map
        gamma.power = 1.6
        map = gamma.outputImage ?? map
        let tint = CIFilter.colorMatrix()
        tint.inputImage = map
        tint.rVector = CIVector(x: 0.36, y: 0, z: 0, w: 0)
        tint.gVector = CIVector(x: 0, y: 1.0, z: 0, w: 0)
        tint.bVector = CIVector(x: 0, y: 0, z: 0.54, w: 0)
        map = tint.outputImage ?? map
        // The glow: the map blurred, laid over itself at half strength.
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = map.clampedToExtent()
        blur.radius = Float(max(2, extent.width / 700))
        let half = CIFilter.colorMatrix()
        half.inputImage = blur.outputImage?.cropped(to: extent)
        half.rVector = CIVector(x: 0.5, y: 0, z: 0, w: 0)
        half.gVector = CIVector(x: 0, y: 0.5, z: 0, w: 0)
        half.bVector = CIVector(x: 0, y: 0, z: 0.5, w: 0)
        let glow = CIFilter.additionCompositing()
        glow.inputImage = half.outputImage
        glow.backgroundImage = map
        map = (glow.outputImage ?? map).cropped(to: extent)

        let width = Int(extent.width), height = Int(extent.height)
        guard let rendered = context.createCGImage(map, from: extent),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(rendered, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The grid, square, about twenty-four across.
        let step = max(CGFloat(width) / 24, 8)
        ctx.setStrokeColor(MapLook.dimPhosphor.cgColor(alpha: 0.28))
        ctx.setLineWidth(max(1, CGFloat(width) / 2400))
        var x: CGFloat = step
        while x < CGFloat(width) {
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: CGFloat(height)))
            x += step
        }
        var y: CGFloat = step
        while y < CGFloat(height) {
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: CGFloat(width), y: y))
            y += step
        }
        ctx.strokePath()
        return ctx.makeImage()
    }

    /// Whether a map is mostly light, as a printed street map is.
    static func isLight(_ map: CIImage, in context: CIContext) -> Bool {
        let average = CIFilter.areaAverage()
        average.inputImage = map
        average.extent = map.extent
        guard let pixel = average.outputImage else { return false }
        var rgba = [UInt8](repeating: 0, count: 4)
        context.render(pixel, toBitmap: &rgba, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8,
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return Int(rgba[0]) + Int(rgba[1]) + Int(rgba[2]) > 3 * 128
    }

    /// What lies over the whole picture, fixed to the screen while the map
    /// slides beneath: scanlines, and corners darkening as an old tube's do.
    static func overlay(width: Int, height: Int, scale: CGFloat) -> CGImage? {
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let pitch = max(2, (3 * scale).rounded())
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.28))
        var y: CGFloat = 0
        while y < CGFloat(height) {
            ctx.fill(CGRect(x: 0, y: y, width: CGFloat(width), height: max(1, pitch / 3)))
            y += pitch
        }
        let centre = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        let colours = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.8)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours, locations: [0, 0.55, 1]) {
            ctx.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre,
                                   endRadius: hypot(CGFloat(width), CGFloat(height)) / 2, options: [.drawsAfterEndLocation])
        }
        return ctx.makeImage()
    }
}
