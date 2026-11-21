import Accelerate
import AppKit
import BackdropCore
import CoreText

/// Shapes partway between two of the stage's glyphs, for a decryption whose
/// letters morph: the ciphertext glyph's shape becoming the letter's.
///
/// Two glyphs built alike, the same number of solid pieces and of holes, are
/// morphed by their outlines, each point travelling to its partner on the
/// other, which keeps the shapes clean and type-like on the way. That is
/// about half of all pairs. Two built differently, where a hole has to open
/// or close or a piece split off, are morphed by mixing their distance
/// fields and drawing round where the mix is inside, which lets holes come
/// and go of themselves; its edge is placed so the shape is always as big as
/// the two glyphs' sizes mixed, so it never thins away to nothing between two
/// that hardly overlap. A glyph with no shape at all, a space, shrinks to
/// nothing, or grows from it, by its outline.
///
/// Shapes are in em units, `unitsPerEm` to the em, from the glyph's origin on
/// the baseline, as Core Text draws it.
@MainActor
final class GlyphMorph {
    nonisolated static let unitsPerEm: CGFloat = 1000

    /// One per face of the stage's type: titles are medium, scene lines regular.
    private static var faces: [String: GlyphMorph] = [:]

    static func face(of font: CTFont) -> GlyphMorph {
        let name = CTFontCopyPostScriptName(font) as String
        if let face = faces[name] { return face }
        let face = GlyphMorph(font: CTFontCreateCopyWithAttributes(font, unitsPerEm, nil, nil))
        faces[name] = face
        return face
    }

    private let font: CTFont
    /// Everything a field covers: every glyph a decryption shows, with room
    /// round it, so the field is outside at its edges.
    private let box: CGRect

    private init(font: CTFont) {
        self.font = font
        var box = CGRect.null
        for c in StageFont.revealCharacters {
            box = box.union(Self.path(of: c, in: font).boundingBoxOfPath)
        }
        self.box = box.insetBy(dx: -Self.margin, dy: -Self.margin)
    }

    // MARK: Shapes

    /// The shape `amount` of the way from `from` to `to`: 0 is `from`, 1 `to`.
    func shape(from: Character, to: Character, amount: Double) -> CGPath {
        let pair = Pair(from: from, to: to)
        switch plan(for: pair) {
        case .outline(let contours):
            let t = CGFloat(amount), path = CGMutablePath()
            for (a, b) in contours {
                path.addLines(between: zip(a, b).map { CGPoint(x: $0.x + ($1.x - $0.x) * t, y: $0.y + ($1.y - $0.y) * t) })
                path.closeSubpath()
            }
            return path
        case .field(let a, let b):
            // Steps fine enough not to show, so a shape once worked out is
            // kept for every surface and every refresh that lands on it.
            let step = Int((amount * Double(Self.fieldSteps)).rounded())
            let key = FieldKey(pair: pair, step: step)
            if let path = fieldShapes[key] { return path }
            if fieldShapes.count > 4096 { fieldShapes.removeAll() }
            let path = fieldShape(a, b, Float(step) / Float(Self.fieldSteps))
            fieldShapes[key] = path
            return path
        }
    }

    /// Whether two glyphs are morphed by their outlines, rather than their
    /// distance fields.
    func morphsByOutline(from: Character, to: Character) -> Bool {
        if case .outline = plan(for: Pair(from: from, to: to)) { return true }
        return false
    }

    /// Works out everything these pairs need ahead of time, so the first
    /// frames that show them don't wait for it.
    func prepare(_ pairs: [(Character, Character)]) {
        for (from, to) in pairs where from != to { _ = plan(for: Pair(from: from, to: to)) }
    }

    // MARK: Plans

    private struct Pair: Hashable {
        var from: Character
        var to: Character
    }

    private enum Plan {
        /// Each contour of one glyph with its partner on the other, point
        /// for point.
        case outline([([CGPoint], [CGPoint])])
        case field(Field, Field)
    }

    private var plans: [Pair: Plan] = [:]

    private func plan(for pair: Pair) -> Plan {
        if let plan = plans[pair] { return plan }
        let a = outline(of: pair.from), b = outline(of: pair.to)
        let plan: Plan
        if a.contours.isEmpty || b.contours.isEmpty || (a.solids == b.solids && a.holes == b.holes) {
            plan = .outline(Self.partners(a, b))
        } else {
            plan = .field(field(of: pair.from), field(of: pair.to))
        }
        plans[pair] = plan
        return plan
    }

    // MARK: Outlines

    /// Points round each contour: enough that a curve shows no flats even
    /// on a title filling a 4K stage.
    private static let samples = 360

    struct Outline {
        struct Contour {
            var points: [CGPoint]
            var hole: Bool
            var centre: CGPoint
        }

        var contours: [Contour]
        var solids: Int { contours.count(where: { !$0.hole }) }
        var holes: Int { contours.count(where: \.hole) }
    }

    private var outlines: [Character: Outline] = [:]

    /// A glyph's contours, evenly spaced points round each, solid pieces
    /// anticlockwise and holes clockwise, so a fill of any mixture of them
    /// by winding is right. Overlapping pieces are merged first, as SF's
    /// letters are built of them: an A's crossbar is a piece of its own,
    /// over its legs. A hole is then told by its winding.
    func outline(of c: Character) -> Outline {
        if let outline = outlines[c] { return outline }
        let raw = Self.flatten(Self.path(of: c, in: font).normalized(using: .winding)).map { Self.resample($0, Self.samples) }
        var contours: [Outline.Contour] = []
        if let biggest = raw.max(by: { abs(Self.signedArea($0)) < abs(Self.signedArea($1)) }) {
            let solid: CGFloat = Self.signedArea(biggest) > 0 ? 1 : -1
            contours = raw.map { points in
                let p = solid > 0 ? points : points.reversed()
                return Outline.Contour(points: p, hole: Self.signedArea(points) * solid < 0, centre: Self.centre(of: p))
            }
        }
        let outline = Outline(contours: contours)
        outlines[c] = outline
        return outline
    }

    /// Solid pieces paired with solid pieces and holes with holes, nearest
    /// first, each partner turned round so its points line up best. Any
    /// left over, as when the other glyph is a space, shrinks to its own
    /// middle.
    private static func partners(_ a: Outline, _ b: Outline) -> [([CGPoint], [CGPoint])] {
        var out: [([CGPoint], [CGPoint])] = []
        var usedA = Set<Int>(), usedB = Set<Int>()
        for hole in [false, true] {
            var candidates: [(distance: CGFloat, i: Int, j: Int)] = []
            for (i, p) in a.contours.enumerated() where p.hole == hole {
                for (j, q) in b.contours.enumerated() where q.hole == hole {
                    candidates.append((hypot(p.centre.x - q.centre.x, p.centre.y - q.centre.y), i, j))
                }
            }
            for c in candidates.sorted(by: { $0.distance < $1.distance }) where !usedA.contains(c.i) && !usedB.contains(c.j) {
                usedA.insert(c.i)
                usedB.insert(c.j)
                out.append((a.contours[c.i].points, aligned(a.contours[c.i].points, b.contours[c.j].points)))
            }
        }
        for (i, p) in a.contours.enumerated() where !usedA.contains(i) {
            out.append((p.points, Array(repeating: p.centre, count: samples)))
        }
        for (j, q) in b.contours.enumerated() where !usedB.contains(j) {
            out.append((Array(repeating: q.centre, count: samples), q.points))
        }
        return out
    }

    /// `b` turned round so its points sit nearest `a`'s, each measured from
    /// its own middle: every fourth turn tried, then the turns either side
    /// of the best of those.
    private static func aligned(_ a: [CGPoint], _ b: [CGPoint]) -> [CGPoint] {
        let n = a.count, ca = centre(of: a), cb = centre(of: b)
        let ax = UnsafeMutablePointer<CGFloat>.allocate(capacity: n), ay = UnsafeMutablePointer<CGFloat>.allocate(capacity: n)
        let bx = UnsafeMutablePointer<CGFloat>.allocate(capacity: n), by = UnsafeMutablePointer<CGFloat>.allocate(capacity: n)
        defer {
            ax.deallocate()
            ay.deallocate()
            bx.deallocate()
            by.deallocate()
        }
        for i in 0..<n {
            ax[i] = a[i].x - ca.x
            ay[i] = a[i].y - ca.y
            bx[i] = b[i].x - cb.x
            by[i] = b[i].y - cb.y
        }
        func cost(_ k: Int) -> CGFloat {
            var total: CGFloat = 0, j = k
            for i in 0..<n {
                let dx = ax[i] - bx[j], dy = ay[i] - by[j]
                total += dx * dx + dy * dy
                j += 1
                if j == n { j = 0 }
            }
            return total
        }
        var best = 0, bestCost = CGFloat.infinity
        for k in Swift.stride(from: 0, to: n, by: 4) {
            let c = cost(k)
            if c < bestCost {
                bestCost = c
                best = k
            }
        }
        let coarse = best
        for d in -3...3 where d != 0 {
            let k = (coarse + d + n) % n, c = cost(k)
            if c < bestCost {
                bestCost = c
                best = k
            }
        }
        return (0..<n).map { b[($0 + best) % n] }
    }

    static func path(of c: Character, in font: CTFont) -> CGPath {
        var units = Array(String(c).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard c != " ", CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count) else { return CGMutablePath() }
        return CTFontCreatePathForGlyph(font, glyphs[0], nil) ?? CGMutablePath()
    }

    /// Each contour as a closed run of short lines.
    private static func flatten(_ path: CGPath) -> [[CGPoint]] {
        var contours: [[CGPoint]] = [], current: [CGPoint] = [], last = CGPoint.zero
        let steps = 10
        path.applyWithBlock { element in
            let e = element.pointee, p = e.points
            switch e.type {
            case .moveToPoint:
                if current.count > 2 { contours.append(current) }
                current = [p[0]]
                last = p[0]
            case .addLineToPoint:
                current.append(p[0])
                last = p[0]
            case .addQuadCurveToPoint:
                for i in 1...steps {
                    let t = CGFloat(i) / CGFloat(steps), u = 1 - t
                    current.append(CGPoint(x: u * u * last.x + 2 * u * t * p[0].x + t * t * p[1].x,
                                           y: u * u * last.y + 2 * u * t * p[0].y + t * t * p[1].y))
                }
                last = p[1]
            case .addCurveToPoint:
                for i in 1...steps {
                    let t = CGFloat(i) / CGFloat(steps), u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    current.append(CGPoint(x: a * last.x + b * p[0].x + c * p[1].x + d * p[2].x,
                                           y: a * last.y + b * p[0].y + c * p[1].y + d * p[2].y))
                }
                last = p[2]
            case .closeSubpath:
                if current.count > 2 { contours.append(current) }
                current = []
            @unknown default:
                break
            }
        }
        if current.count > 2 { contours.append(current) }
        return contours
    }

    /// `n` points evenly spaced round a closed run of lines.
    private static func resample(_ contour: [CGPoint], _ n: Int) -> [CGPoint] {
        let points = contour + [contour[0]]
        var lengths: [CGFloat] = [0]
        for i in 1..<points.count {
            lengths.append(lengths[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y))
        }
        let total = lengths[lengths.count - 1]
        var out: [CGPoint] = []
        var j = 1
        for k in 0..<n {
            let d = total * CGFloat(k) / CGFloat(n)
            while j < points.count - 1 && lengths[j] < d { j += 1 }
            let segment = lengths[j] - lengths[j - 1], u = segment > 0 ? (d - lengths[j - 1]) / segment : 0
            let a = points[j - 1], b = points[j]
            out.append(CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u))
        }
        return out
    }

    private static func signedArea(_ p: [CGPoint]) -> CGFloat {
        var area: CGFloat = 0
        for i in p.indices {
            let q = p[(i + 1) % p.count]
            area += p[i].x * q.y - q.x * p[i].y
        }
        return area / 2
    }

    private static func centre(of p: [CGPoint]) -> CGPoint {
        let sum = p.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(p.count), y: sum.y / CGFloat(p.count))
    }

    // MARK: Fields

    /// The field's grid spacing, in em units: over a hundred points up a
    /// capital, and the contour drawn round them lies between them, so curves
    /// come out smooth.
    private static let spacing: CGFloat = 6
    private static let margin: CGFloat = 90
    /// How finely a field morph's shapes are kept.
    private static let fieldSteps = 128

    struct Field {
        /// How far each grid point is from the glyph's edge, in em units:
        /// negative inside, positive outside. Rows run up from the bottom.
        var values: [Float]
        /// The same, softened. Two fields mixed crease wherever either
        /// glyph's ridges, the lines midway between its edges, cross the
        /// shape; softened, they don't. Softening rounds the glyph's
        /// corners too, so a morph mixes it in most in the middle and not
        /// at all at the ends, where the shape must be the glyph's own.
        var soft: [Float]
        /// Grid points inside.
        var inside: Int
    }

    /// Passes of the softening filter.
    private static let softening = 16

    private var fields: [Character: Field] = [:]
    private var fieldShapes: [FieldKey: CGPath] = [:]

    private struct FieldKey: Hashable {
        var pair: Pair
        var step: Int
    }

    private var columns: Int { Int((box.width / Self.spacing).rounded(.down)) }
    private var rows: Int { Int((box.height / Self.spacing).rounded(.down)) }

    /// Where grid point (i, j) is, in em units.
    private func point(_ i: Int, _ j: Int) -> CGPoint {
        let half = Self.spacing / 2
        return CGPoint(x: box.minX + half + CGFloat(i) * Self.spacing, y: box.minY + half + CGFloat(j) * Self.spacing)
    }

    // The field work runs on raw buffers with nothing allocated inside its
    // loops: it is the heavy part of a morph, and a debug build pays dearly
    // for every array touched or made in a loop of tens of thousands.

    private func field(of c: Character) -> Field {
        if let field = fields[c] { return field }
        let nx = columns, ny = rows, n = nx * ny
        // The glyph drawn, smoothed at its edges, one pixel to a grid point,
        // rows from the top as a bitmap keeps them.
        let ctx = CGContext(data: nil, width: nx, height: ny, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: nx, height: ny))
        ctx.scaleBy(x: 1 / Self.spacing, y: 1 / Self.spacing)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.addPath(Self.path(of: c, in: font))
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fillPath()
        let stride = ctx.bytesPerRow
        let bytes = ctx.data!.bindMemory(to: UInt8.self, capacity: stride * ny)
        // How much of each pixel the glyph covers, rows turned to run up from
        // the bottom, as the grid's do.
        let cover = UnsafeMutablePointer<Float>.allocate(capacity: n), squared = UnsafeMutablePointer<Double>.allocate(capacity: n)
        defer {
            cover.deallocate()
            squared.deallocate()
        }
        for j in 0..<ny {
            let row = bytes + (ny - 1 - j) * stride
            for i in 0..<nx { cover[j * nx + i] = Float(row[i]) / 255 }
        }
        // The edge runs through every pixel it partly covers, as far from
        // the pixel's middle as its cover is from half; between two whole
        // pixels either side of it, half a pixel from each. Out from there,
        // the transform finds every pixel's distance to the nearest of it.
        for j in 0..<ny {
            for i in 0..<nx {
                let k = j * nx + i, c = cover[k], inside = c >= 0.5
                var f = 1e20
                if c > 0 && c < 1 { f = Double((c - 0.5) * (c - 0.5)) }
                if (i > 0 && (cover[k - 1] >= 0.5) != inside) || (i < nx - 1 && (cover[k + 1] >= 0.5) != inside)
                    || (j > 0 && (cover[k - nx] >= 0.5) != inside) || (j < ny - 1 && (cover[k + nx] >= 0.5) != inside) {
                    f = min(f, 0.25)
                }
                squared[k] = f
            }
        }
        Self.squaredDistances(squared, width: nx, height: ny)
        var values = [Float](repeating: 0, count: n)
        var count = 0
        let spacing = Float(Self.spacing)
        values.withUnsafeMutableBufferPointer { out in
            for k in 0..<n {
                let d = Float(squared[k].squareRoot()) * spacing
                if cover[k] >= 0.5 {
                    out[k] = -d
                    count += 1
                } else {
                    out[k] = d
                }
            }
        }
        let field = Field(values: values, soft: Self.softened(values, columns: nx, rows: ny), inside: count)
        fields[c] = field
        return field
    }

    /// A field blurred, a few passes of a small Gaussian, its outermost
    /// points kept as they were: the filter leaves them out, and they must
    /// stay well outside.
    private static func softened(_ values: [Float], columns nx: Int, rows ny: Int) -> [Float] {
        var soft = values, pass = values
        let kernel: [Float] = [1, 2, 1, 2, 4, 2, 1, 2, 1].map { $0 / 16 }
        for _ in 0..<softening {
            vDSP_f3x3(soft, vDSP_Length(ny), vDSP_Length(nx), kernel, &pass)
            for i in 0..<nx {
                pass[i] = values[i]
                pass[(ny - 1) * nx + i] = values[(ny - 1) * nx + i]
            }
            for j in 0..<ny {
                pass[j * nx] = values[j * nx]
                pass[j * nx + nx - 1] = values[j * nx + nx - 1]
            }
            swap(&soft, &pass)
        }
        return soft
    }

    /// Each pixel's squared distance from the nearest pixel at 0, in place,
    /// by Felzenszwalb and Huttenlocher's exact transform: down each column,
    /// then along each row.
    private static func squaredDistances(_ grid: UnsafeMutablePointer<Double>, width w: Int, height h: Int) {
        let n = max(w, h)
        let f = UnsafeMutablePointer<Double>.allocate(capacity: n), d = UnsafeMutablePointer<Double>.allocate(capacity: n)
        let v = UnsafeMutablePointer<Int>.allocate(capacity: n), z = UnsafeMutablePointer<Double>.allocate(capacity: n + 1)
        defer {
            f.deallocate()
            d.deallocate()
            v.deallocate()
            z.deallocate()
        }
        func transform(_ count: Int) {
            var k = 0
            v[0] = 0
            z[0] = -.infinity
            z[1] = .infinity
            if count > 1 {
                for q in 1..<count {
                    let fq = f[q] + Double(q * q)
                    var p = v[k]
                    var s = (fq - (f[p] + Double(p * p))) / Double(2 * (q - p))
                    while s <= z[k] {
                        k -= 1
                        p = v[k]
                        s = (fq - (f[p] + Double(p * p))) / Double(2 * (q - p))
                    }
                    k += 1
                    v[k] = q
                    z[k] = s
                    z[k + 1] = .infinity
                }
            }
            k = 0
            for q in 0..<count {
                while z[k + 1] < Double(q) { k += 1 }
                let dq = Double(q - v[k])
                d[q] = dq * dq + f[v[k]]
            }
        }
        for x in 0..<w {
            for y in 0..<h { f[y] = grid[y * w + x] }
            transform(h)
            for y in 0..<h { grid[y * w + x] = d[y] }
        }
        for y in 0..<h {
            let row = grid + y * w
            for x in 0..<w { f[x] = row[x] }
            transform(w)
            for x in 0..<w { row[x] = d[x] }
        }
    }

    /// The two fields mixed, and the edge drawn round where the mix is
    /// inside, moved so as much is inside as the two glyphs' sizes mixed.
    private func fieldShape(_ a: Field, _ b: Field, _ t: Float) -> CGPath {
        let nx = columns, ny = rows, n = nx * ny
        let mix = UnsafeMutablePointer<Float>.allocate(capacity: n), soft = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer {
            mix.deallocate()
            soft.deallocate()
        }
        let length = vDSP_Length(n)
        // Sharp at the very ends, soft from an eighth of the way in to an
        // eighth from the end.
        var t = t, softness = min(1, 12 * t * (1 - t)), lo: Float = 0, hi: Float = 0
        vDSP_vintb(a.values, 1, b.values, 1, &t, mix, 1, length)
        vDSP_vintb(a.soft, 1, b.soft, 1, &t, soft, 1, length)
        vDSP_vintb(mix, 1, soft, 1, &softness, mix, 1, length)
        vDSP_minv(mix, 1, &lo, length)
        vDSP_maxv(mix, 1, &hi, length)
        let target = Float(a.inside) * (1 - t) + Float(b.inside) * t
        var down = -Self.level(mix, count: n, holding: target, lo: lo, hi: hi)
        vDSP_vsadd(mix, 1, &down, mix, 1, length)
        return contours(of: mix, columns: nx, rows: ny)
    }

    /// The level with `target` of the values below it, from a histogram of
    /// them, read between its bins.
    private static func level(_ values: UnsafeMutablePointer<Float>, count n: Int, holding target: Float, lo: Float, hi: Float) -> Float {
        guard target > 0, hi > lo else { return lo }
        let bins = 1024, width = (hi - lo) / Float(bins)
        let histogram = UnsafeMutablePointer<Int>.allocate(capacity: bins)
        histogram.initialize(repeating: 0, count: bins)
        defer { histogram.deallocate() }
        for k in 0..<n { histogram[min(bins - 1, Int((values[k] - lo) / width))] += 1 }
        var below: Float = 0
        for k in 0..<bins {
            let count = Float(histogram[k])
            if below + count >= target { return lo + (Float(k) + (target - below) / max(count, 1)) * width }
            below += count
        }
        return hi
    }

    /// The outline of where `values` is below 0, by marching squares, each
    /// crossing placed between its two grid points by their values. Every
    /// run goes with the inside on its left, so solid pieces come out
    /// anticlockwise and holes clockwise.
    private func contours(of values: UnsafeMutablePointer<Float>, columns nx: Int, rows ny: Int) -> CGPath {
        // Edges are numbered two to a grid point: the one going right from
        // it, and the one going up. Each crossing where a run leaves the
        // inside names the crossing it goes on to.
        let edges = nx * ny * 2
        let next = UnsafeMutablePointer<Int>.allocate(capacity: edges)
        next.initialize(repeating: -1, count: edges)
        let crossing = UnsafeMutablePointer<Int>.allocate(capacity: 4), leaving = UnsafeMutablePointer<Bool>.allocate(capacity: 4)
        defer {
            next.deallocate()
            crossing.deallocate()
            leaving.deallocate()
        }
        var starts: [Int] = []
        for j in 0..<ny - 1 {
            let row = j * nx
            for i in 0..<nx - 1 {
                let c0 = values[row + i], c1 = values[row + i + 1], c2 = values[row + nx + i + 1], c3 = values[row + nx + i]
                let in0 = c0 < 0, in1 = c1 < 0, in2 = c2 < 0, in3 = c3 < 0
                if in0 == in1 && in1 == in2 && in2 == in3 { continue }
                // Round the square anticlockwise from its bottom left: along
                // the bottom, up the right, back along the top, down the left.
                var m = 0
                if in0 != in1 { crossing[m] = (row + i) * 2; leaving[m] = in0; m += 1 }
                if in1 != in2 { crossing[m] = (row + i + 1) * 2 + 1; leaving[m] = in1; m += 1 }
                if in2 != in3 { crossing[m] = (row + nx + i) * 2; leaving[m] = in2; m += 1 }
                if in3 != in0 { crossing[m] = (row + i) * 2 + 1; leaving[m] = in3; m += 1 }
                // Each run leaves where the way round goes out, and ends
                // where it next comes back in; or, where two corners
                // opposite are inside and the middle isn't, where it last
                // came in, so the two stay apart.
                let joined = m == 2 || c0 + c1 + c2 + c3 < 0
                for k in 0..<m where leaving[k] {
                    next[crossing[k]] = joined ? crossing[(k + 1) % m] : crossing[(k + m - 1) % m]
                    starts.append(crossing[k])
                }
            }
        }
        func position(of edge: Int) -> CGPoint {
            let base = edge / 2, i = base % nx, j = base / nx
            let (i2, j2) = edge % 2 == 0 ? (i + 1, j) : (i, j + 1)
            let va = values[j * nx + i], vb = values[j2 * nx + i2]
            let u = CGFloat(va / (va - vb))
            let a = point(i, j), b = point(i2, j2)
            return CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
        }
        // Loops too small to read as part of a letter, the last specks of a
        // piece or a hole on its way out, are left out rather than flicker.
        let path = CGMutablePath()
        var loop: [CGPoint] = []
        for start in starts where next[start] >= 0 {
            var edge = start
            loop.removeAll(keepingCapacity: true)
            loop.append(position(of: edge))
            while next[edge] >= 0 {
                let to = next[edge]
                next[edge] = -1
                edge = to
                if edge == start { break }
                loop.append(position(of: edge))
            }
            guard abs(Self.signedArea(loop)) >= Self.speck else { continue }
            path.addLines(between: loop)
            path.closeSubpath()
        }
        return path
    }

    /// The smallest loop a field morph draws, in square em units: about
    /// forty across, where the smallest counter of any glyph a decryption
    /// shows, an A's or a 4's, is several times that.
    private static let speck: CGFloat = 1500
}
