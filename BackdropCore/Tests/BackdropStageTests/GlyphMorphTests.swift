import BackdropCore
import CoreText
import Testing
@testable import BackdropStage

/// These work out fields and fill shapes on the main actor, as the stage
/// does, so each yields between letter pairs: other suites running at the
/// same time wait on the main actor too.
@Suite("Glyphs morphing")
@MainActor
struct GlyphMorphTests {
    let face = GlyphMorph.face(of: StageFont.title(size: 100))

    /// Where a shape covers, five em units to a pixel, over everything a
    /// glyph reaches.
    func coverage(_ path: CGPath) -> [UInt8] {
        let w = 160, h = 264
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.scaleBy(x: 0.2, y: 0.2)
        ctx.translateBy(x: 100, y: 300)
        ctx.addPath(path)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fillPath(using: .winding)
        return Array(UnsafeBufferPointer(start: ctx.data!.bindMemory(to: UInt8.self, capacity: w * h), count: w * h))
    }

    func glyph(_ c: Character) -> CGPath {
        GlyphMorph.path(of: c, in: StageFont.title(size: GlyphMorph.unitsPerEm))
    }

    /// How much of the two shapes is shared: 1 when they are the same.
    func overlap(_ a: CGPath, _ b: CGPath) -> Double {
        let p = coverage(a), q = coverage(b)
        var both = 0, either = 0
        for k in p.indices {
            let x = p[k] > 127, y = q[k] > 127
            if x && y { both += 1 }
            if x || y { either += 1 }
        }
        return either == 0 ? 1 : Double(both) / Double(either)
    }

    func area(_ path: CGPath) -> Int {
        var n = 0
        for v in coverage(path) where v > 127 { n += 1 }
        return n
    }

    @Test("A glyph's solid pieces and holes are told apart, overlapping pieces merged")
    func structure() {
        for (c, solids, holes) in [("B", 1, 2), ("A", 1, 1), ("C", 1, 0), ("8", 1, 2), ("!", 2, 0), ("?", 2, 0)] as [(Character, Int, Int)] {
            let o = face.outline(of: c)
            #expect(o.solids == solids && o.holes == holes, "\(c): \(o.solids) solid, \(o.holes) holes")
        }
        #expect(face.outline(of: " ").contours.isEmpty)
    }

    @Test("Glyphs built alike morph by their outlines; others by their fields; a space by outline, to or from nothing")
    func whichWay() async {
        #expect(face.morphsByOutline(from: "A", to: "R"))
        #expect(face.morphsByOutline(from: ".", to: "-"))
        #expect(face.morphsByOutline(from: "X", to: " ") && face.morphsByOutline(from: " ", to: "X"))
        await Task.yield()
        #expect(!face.morphsByOutline(from: "B", to: "C"))
        await Task.yield()
        #expect(!face.morphsByOutline(from: "G", to: "8"))
    }

    @Test("Just begun, a morph is the glyph it starts as; nearly done, the one it ends as")
    func endsMatch() async {
        for (a, b) in [("A", "R"), ("B", "C"), ("O", "X"), ("G", "8"), ("7", "Q")] as [(Character, Character)] {
            let start = overlap(face.shape(from: a, to: b, amount: 0.001), glyph(a))
            let end = overlap(face.shape(from: a, to: b, amount: 0.999), glyph(b))
            #expect(start > 0.9 && end > 0.9, "\(a) → \(b): \(start), \(end)")
            await Task.yield()
        }
    }

    @Test("Halfway, a morph is about as big as the two glyphs mixed, and never nothing")
    func neverVanishes() async {
        for (a, b) in [(".", "-"), ("O", "X"), ("B", "C"), ("G", "8"), ("I", "W"), (",", "T")] as [(Character, Character)] {
            let middle = Double(area(face.shape(from: a, to: b, amount: 0.5)))
            let mixed = Double(area(glyph(a)) + area(glyph(b))) / 2
            #expect(middle > 0 && abs(middle - mixed) / mixed < 0.2, "\(a) → \(b): \(middle) against \(mixed)")
            await Task.yield()
        }
    }

    @Test("A space grows into its letter from nothing, and a letter shrinks away to a space")
    func spaces() {
        #expect(area(face.shape(from: " ", to: "X", amount: 0.01)) < area(glyph("X")) / 10)
        #expect(area(face.shape(from: "X", to: " ", amount: 0.99)) < area(glyph("X")) / 10)
    }

    @Test("Holes close up of themselves when there are none to go to")
    func holesClose() {
        func pieces(_ path: CGPath) -> Int {
            var n = 0
            path.applyWithBlock { if $0.pointee.type == .moveToPoint { n += 1 } }
            return n
        }
        #expect(pieces(face.shape(from: "B", to: "C", amount: 0.05)) == 3, "a B: its outside and two holes")
        #expect(pieces(face.shape(from: "B", to: "C", amount: 0.95)) == 1, "a C: one piece")
    }

    @Test("The same morph is the same shape every time it is asked for")
    func repeatable() {
        for (a, b) in [("A", "R"), ("B", "C")] as [(Character, Character)] {
            #expect(CFEqual(face.shape(from: a, to: b, amount: 0.3), face.shape(from: a, to: b, amount: 0.3)))
        }
    }
}
