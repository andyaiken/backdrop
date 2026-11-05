import Foundation

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
