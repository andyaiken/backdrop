import Foundation

/// A place on a picture, as fractions of its width and height from the top
/// left, so it holds whatever size the picture is shown at.
public struct PicturePoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Pulled onto the picture if it is off it.
    public var clamped: PicturePoint {
        PicturePoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }

    func mix(_ other: PicturePoint, _ t: Double) -> PicturePoint {
        PicturePoint(x: x + (other.x - x) * t, y: y + (other.y - y) * t)
    }
}

/// In show.json, `[x, y]`.
extension PicturePoint: Codable {
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        y = try c.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
    }
}

/// One feature found on both pictures, an eye or the point of a chin: where
/// it is on the first, and where on the second. Through the morph it slides
/// from one to the other, and the pictures stretch with it.
public struct MorphPair: Codable, Hashable, Sendable {
    public var from: PicturePoint
    public var to: PicturePoint

    public init(from: PicturePoint, to: PicturePoint) {
        self.from = from
        self.to = to
    }
}

/// The triangles a morph is drawn with. Every matched pair is a vertex, and
/// so are the pictures' corners and the middles of their edges, which match
/// corner to corner, so the whole of both pictures is covered. The mesh is
/// triangulated, Delaunay, on where each vertex is halfway through, which
/// keeps the triangles as fat as they can be for the whole morph.
public struct MorphMesh: Equatable, Sendable {
    /// Each vertex on the first picture, and on the second.
    public let from: [PicturePoint]
    public let to: [PicturePoint]
    /// Three vertex indices to a triangle.
    public let triangles: [Int]

    /// The corners and edge middles, clockwise from the top left.
    public static let frame: [PicturePoint] = [(0, 0), (0.5, 0), (1, 0), (1, 0.5), (1, 1), (0.5, 1), (0, 1), (0, 0.5)]
        .map { PicturePoint(x: $0.0, y: $0.1) }

    public init(pairs: [MorphPair]) {
        var from = Self.frame, to = Self.frame
        // Each pair on the pictures, unless it would sit on a vertex already
        // there: two vertices in one place make no triangle.
        for pair in pairs {
            let a = pair.from.clamped, b = pair.to.clamped, middle = a.mix(b, 0.5)
            let taken = zip(from, to).contains { f, t in
                let m = f.mix(t, 0.5)
                return abs(m.x - middle.x) < 1e-4 && abs(m.y - middle.y) < 1e-4
            }
            guard !taken else { continue }
            from.append(a)
            to.append(b)
        }
        self.from = from
        self.to = to
        // The frame's points nudged outward a hair, so no three of them lie
        // on one line, where a triangle would have no area.
        let middles = zip(from, to).enumerated().map { i, pair in
            let m = pair.0.mix(pair.1, 0.5)
            guard i < Self.frame.count else { return m }
            return PicturePoint(x: m.x + (m.x - 0.5) * 1e-3, y: m.y + (m.y - 0.5) * 1e-3)
        }
        triangles = Delaunay.triangulate(middles)
    }

    /// Where every vertex is `t` of the way from the first picture to the
    /// second.
    public func vertices(at t: Double) -> [PicturePoint] {
        zip(from, to).map { $0.mix($1, t) }
    }
}

/// How far through its change a morph is.
public enum MorphTiming {
    /// From 0 to 1, `ms` into a morph of `morphMs`, eased in and out so it
    /// neither jumps off nor lands hard.
    public static func progress(ms: Double, morphMs: Int) -> Double {
        let t = min(max(ms / Double(max(morphMs, 1)), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// Bowyer-Watson: each point in turn, every triangle whose circumcircle
/// holds it taken out, and the hole filled with triangles to the point.
enum Delaunay {
    static func triangulate(_ points: [PicturePoint]) -> [Int] {
        let n = points.count
        guard n >= 3 else { return [] }
        // A triangle around everything, its corners dropped at the end.
        var p = points.map { (x: $0.x, y: $0.y) }
        p += [(x: -100, y: -100), (x: 200, y: -100), (x: -100, y: 200)]
        var triangles = [[n, n + 1, n + 2]]

        func contains(_ t: [Int], _ q: (x: Double, y: Double)) -> Bool {
            let a = p[t[0]], b = p[t[1]], c = p[t[2]]
            let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
            guard abs(d) > 1e-15 else { return false }
            let a2 = a.x * a.x + a.y * a.y, b2 = b.x * b.x + b.y * b.y, c2 = c.x * c.x + c.y * c.y
            let ux = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d
            let uy = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d
            let r2 = (a.x - ux) * (a.x - ux) + (a.y - uy) * (a.y - uy)
            return (q.x - ux) * (q.x - ux) + (q.y - uy) * (q.y - uy) < r2 * (1 - 1e-12)
        }

        for i in 0..<n {
            let bad = triangles.indices.filter { contains(triangles[$0], p[i]) }
            // The hole's edge: edges of the bad triangles that only one of
            // them has.
            var edges: [[Int]] = []
            for t in bad {
                let tri = triangles[t]
                for edge in [[tri[0], tri[1]], [tri[1], tri[2]], [tri[2], tri[0]]] {
                    if let shared = edges.firstIndex(where: { Set($0) == Set(edge) }) {
                        edges.remove(at: shared)
                    } else {
                        edges.append(edge)
                    }
                }
            }
            for t in bad.reversed() { triangles.remove(at: t) }
            triangles += edges.map { [$0[0], $0[1], i] }
        }
        return triangles.filter { $0.allSatisfy { $0 < n } }.flatMap { $0 }
    }
}
