import AppKit
import BackdropCore
import Testing
@testable import BackdropStage

/// A 400 x 200 picture, red on the left half and blue on the right, in a
/// temporary folder.
private let media: URL = {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("QuickLookTests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let context = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
    context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
    context.fill(CGRect(x: 200, y: 0, width: 200, height: 200))
    try! NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: folder.appendingPathComponent("halves.png"))
    return folder
}()

/// The colour at a point measured from the top left, over white, so a
/// transparent pixel can't pass for black.
private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
    let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    let i = (y * image.width + x) * 4
    return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
}

@Suite("Quick Look")
@MainActor
struct QuickLookTests {
    @Test("The thumbnail is the first cue that shows anything, finished, at the stage's shape")
    func firstTitle() async throws {
        let show = Show(title: "T", cues: [
            Cue(number: "1", content: .blank(BlankContent())),
            Cue(number: "2", content: .title(TitleContent(text: "THE LOUVRE", sub: "PARIS"))),
        ])
        #expect(ShowThumbnail.cue(of: show)?.number == "2")
        let image = try #require(await ShowThumbnail.image(of: show, width: 640) { _ in nil })
        #expect(image.width == 640 && image.height == 360)
        // The words, light on black, in the upper half; the stage black.
        let words = stride(from: 0, to: 640, by: 2).flatMap { x in stride(from: 60, to: 180, by: 4).map { pixel(image, x: x, y: $0) } }
        #expect(words.contains { $0.r > 128 && $0.g > 128 && $0.b > 128 })
        #expect(pixel(image, x: 4, y: 4) == (0, 0, 0))
        #expect(pixel(image, x: 320, y: 30) == (0, 0, 0))
    }

    @Test("An image cue's thumbnail is its picture, waited for")
    func picture() async throws {
        let show = Show(title: "T", cues: [
            Cue(number: "1", content: .image(ImageContent(text: "Halves", src: "halves.png"))),
        ])
        let image = try #require(await ShowThumbnail.image(of: show, width: 640) { media.appendingPathComponent($0) })
        let left = pixel(image, x: 200, y: 180), right = pixel(image, x: 440, y: 180)
        #expect(left.r > 200 && left.b < 60, "red on the left: \(left)")
        #expect(right.b > 200 && right.r < 60, "blue on the right: \(right)")
    }

    @Test("A show with nothing to show has no thumbnail")
    func nothing() async {
        let show = Show(title: "T", cues: [
            Cue(number: "1", content: .blank(BlankContent())),
            Cue(number: "2", content: .video(VideoContent(text: "Clip", src: "clip.mov"))),
        ])
        #expect(ShowThumbnail.cue(of: show) == nil)
        #expect(await ShowThumbnail.image(of: show, width: 640) { _ in nil } == nil)
    }

    @Test("The preview is the cue sheet, as a PDF")
    func cueSheet() throws {
        let show = Show(title: "The Da Vinci Code", cues: (1...60).map {
            Cue(number: "\($0)", content: .title(TitleContent(text: "CUE \($0)")))
        })
        let data = try #require(CueSheetPrinting.pdfData(for: show, title: show.title))
        #expect(data.prefix(4) == Data("%PDF".utf8))
        let pdf = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        #expect(pdf.numberOfPages > 1, "sixty cues run onto a second page: \(pdf.numberOfPages)")
    }
}
