import Foundation
import Testing
@testable import ProspectCore

@Suite("Morphs")
struct MorphTests {
    /// A face's worth of points: eyes, nose, mouth and chin, each a little
    /// lower and wider on the second picture.
    static let face: [MorphPair] = [
        (0.38, 0.40), (0.62, 0.40), (0.50, 0.55), (0.42, 0.68), (0.58, 0.68), (0.50, 0.85), (0.30, 0.30), (0.70, 0.30),
    ].map { x, y in
        MorphPair(from: PicturePoint(x: x, y: y), to: PicturePoint(x: 0.5 + (x - 0.5) * 1.1, y: y + 0.03))
    }

    func area(_ a: PicturePoint, _ b: PicturePoint, _ c: PicturePoint) -> Double {
        ((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2
    }

    @Test("The mesh covers the whole picture, at every moment, with no triangle folded or flat")
    func covers() {
        let mesh = MorphMesh(pairs: Self.face)
        #expect(mesh.from.count == 8 + Self.face.count)
        for t in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let v = mesh.vertices(at: t)
            let areas = stride(from: 0, to: mesh.triangles.count, by: 3).map {
                area(v[mesh.triangles[$0]], v[mesh.triangles[$0 + 1]], v[mesh.triangles[$0 + 2]])
            }
            #expect(abs(areas.map(abs).reduce(0, +) - 1) < 1e-9, "the unit square exactly, at \(t)")
            // Every triangle keeps its winding: none turns inside out.
            #expect(areas.allSatisfy { $0 > 1e-6 } || areas.allSatisfy { $0 < -1e-6 }, "at \(t)")
        }
    }

    @Test("Triangles are Delaunay on the halfway points: no vertex inside another triangle's circle")
    func delaunay() {
        let mesh = MorphMesh(pairs: Self.face)
        let v = mesh.vertices(at: 0.5)
        for k in stride(from: 0, to: mesh.triangles.count, by: 3) {
            let a = v[mesh.triangles[k]], b = v[mesh.triangles[k + 1]], c = v[mesh.triangles[k + 2]]
            let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
            let a2 = a.x * a.x + a.y * a.y, b2 = b.x * b.x + b.y * b.y, c2 = c.x * c.x + c.y * c.y
            let ux = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d
            let uy = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d
            let r = hypot(a.x - ux, a.y - uy)
            for (i, p) in v.enumerated() where !mesh.triangles[k..<k + 3].contains(i) {
                #expect(hypot(p.x - ux, p.y - uy) >= r - 1e-3)
            }
        }
    }

    @Test("With no points at all, the pictures still map corner to corner")
    func noPoints() {
        let mesh = MorphMesh(pairs: [])
        #expect(mesh.from == MorphMesh.frame && mesh.to == MorphMesh.frame)
        #expect(mesh.triangles.count == 6 * 3, "an octagon in six triangles")
    }

    @Test("Points off the picture are pulled onto it, and a second point in the same place is dropped")
    func tidying() {
        let off = MorphPair(from: PicturePoint(x: 1.2, y: -0.1), to: PicturePoint(x: 0.9, y: 0.1))
        let twice = MorphPair(from: PicturePoint(x: 0.5, y: 0.5), to: PicturePoint(x: 0.5, y: 0.5))
        let mesh = MorphMesh(pairs: [off, twice, twice])
        #expect(mesh.from.count == 10)
        #expect(mesh.from[8] == PicturePoint(x: 1, y: 0))
    }

    @Test("Each vertex slides from its place on the first picture to its place on the second")
    func sliding() {
        let mesh = MorphMesh(pairs: Self.face)
        #expect(mesh.vertices(at: 0) == mesh.from && mesh.vertices(at: 1) == mesh.to)
        let halfway = mesh.vertices(at: 0.5)[8]
        #expect(abs(halfway.x - (mesh.from[8].x + mesh.to[8].x) / 2) < 1e-12)
    }

    @Test("A morph eases in and out over its time")
    func timing() {
        #expect(MorphTiming.progress(ms: -10, morphMs: 3000) == 0)
        #expect(MorphTiming.progress(ms: 1500, morphMs: 3000) == 0.5)
        #expect(MorphTiming.progress(ms: 300, morphMs: 3000) < 0.1, "slow to start")
        #expect(MorphTiming.progress(ms: 5000, morphMs: 3000) == 1)
    }

    @Test("A morph cue keeps both pictures and its points in show.json, each point as [x, y]")
    func roundTrips() throws {
        let cue = Cue(number: "9", content: .morph(MorphContent(text: "LEONARDO", src: "media/leonardo.jpg", into: "media/mona-lisa.jpg",
                                                               pairs: Self.face, overrides: MorphOverrides(morphMs: 4000))))
        let data = try JSONEncoder().encode(cue)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"kind\":\"morph\"") && json.contains("\"into\":\"media\\/mona-lisa.jpg\"") && json.contains("\"from\":[0.38,0.4]"))
        #expect(try JSONDecoder().decode(Cue.self, from: data) == cue)
        #expect(cue.mediaPaths == ["media/leonardo.jpg", "media/mona-lisa.jpg"])
        #expect(cue.finishes && !cue.isInstant)
    }

    @Test("A morph has a clock, a hold and its own time, but no wave")
    func settings() {
        #expect(SettingKey.allCases.filter { $0.applies(to: .morph) } == [.clock, .hold, .morphTime, .transition, .fade])
        var cue = Cue(content: .morph(MorphContent()))
        SettingKey.morphTime.setOverride(.number(4250), in: &cue)
        #expect(SettingKey.morphTime.override(in: cue) == .number(4300), "snapped to a tenth of a second")
        #expect(SettingKey.morphTime.format(.number(4300)) == "4.3 s")
        #expect(cue.timing(defaults: ShowSettings()) == CueTiming(clockMs: 44, holdTicks: 44, isInstant: false))
        #expect(ShowSettings().morphMs == 3000)
        var s = ShowSettings()
        SettingKey.morphTime.set(.number(5000), in: &s)
        #expect(try! JSONDecoder().decode(ShowSettings.self, from: JSONEncoder().encode(s)).morphMs == 5000)
    }

    @Test("The sheet flags a morph missing a picture, and prints both with the number of points")
    func sheet() {
        let half = Cue(number: "9", content: .morph(MorphContent(text: "LEONARDO", src: "media/leonardo.jpg")))
        let show = Show(title: "T", cues: [half])
        #expect(show.issues == [.morphWithoutPictures(cue: half.id)])
        #expect(show.message(for: show.issues[0]) == "Cue 9 needs both pictures: the one it starts from and the one it becomes.")
        let settings = CueSheet(show: show, title: "T", layout: .operatorSettings).rows[0].settings
        #expect(settings.map(\.name) == ["Clock", "Hold", "Morph", "First picture", "Second picture", "Points", "Transition", "Fade"])
        #expect(settings[3].value == "leonardo.jpg" && settings[4].value == "none" && settings[5].value == "0")
    }
}
