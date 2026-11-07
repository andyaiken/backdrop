import Foundation
import Testing
@testable import ProspectCore

@Suite("Map cues")
struct MapTests {
    func p(_ x: Double, _ y: Double) -> PicturePoint { PicturePoint(x: x, y: y) }

    /// From the start, along the top and down to a stop, then a jump.
    func route() -> MapContent {
        MapContent(text: "OPERATION NIGHTJAR", src: "media/london.png", route: [
            RoutePoint(at: p(0.1, 0.1), stop: MapStop(status: "PARKED", place: "SOHO")),
            RoutePoint(at: p(0.5, 0.1)),
            RoutePoint(at: p(0.5, 0.5), stop: MapStop(travelMs: 4000, place: "KING'S CROSS")),
            RoutePoint(at: p(0.9, 0.9), stop: MapStop(arrival: .jump, status: "MOVING", place: "DOCKS")),
        ])
    }

    /// 100 ms frames, no hold, a pause of 10.
    let settings = MapSettings(clockMs: 100, holdTicks: 0, advance: .byItself, pauseTicks: 10)

    @Test("By itself, each leg follows a pause after the one before; a jump takes its lost signal and its return")
    func parts() {
        let plan = MapCuePlan(route(), settings: settings)
        #expect(plan.legs.map(\.path.count) == [3, 2], "the travel passes its point; the jump goes straight")
        #expect(plan.legs.map(\.ms) == [4000, MapCuePlan.lostMs + MapCuePlan.acquiredMs])
        #expect(plan.parts == [40 + 10 + 34])
        #expect(plan.legs.map(\.offset) == [0, 50])
    }

    @Test("The dot pulls away, travels the route at speed and slows to a halt, the view on it all the way")
    func travel() {
        #expect(MapCuePlan.travelled(0) == 0 && MapCuePlan.travelled(1) == 1)
        #expect(abs(MapCuePlan.travelled(0.5) - 0.5) < 1e-12)
        #expect(MapCuePlan.travelled(0.1) < 0.1 / 2, "slow away")
        #expect(MapCuePlan.travelled(0.95) > 0.99, "slowing at the end")
        let plan = MapCuePlan(route(), settings: settings), timeline = GoTimeline(parts: plan.parts)
        let start = plan.state(at: -5, timeline: timeline)
        #expect(start.dot == p(0.1, 0.1) && start.status.text == "PARKED" && start.place.text == "SOHO")
        // Halfway by time is halfway by distance, 0.4 along the top's 0.4 and
        // the 0.4 down: at the corner.
        let half = plan.state(at: 20, timeline: timeline)
        #expect(abs(half.dot.x - 0.5) < 1e-9 && abs(half.dot.y - 0.1) < 1e-9)
        #expect(half.view == half.dot)
        #expect(half.status.text == MapCuePlan.Words.moving && half.place.text.isEmpty)
        let there = plan.state(at: 45, timeline: timeline)
        #expect(there.dot == p(0.5, 0.5) && there.status.text == MapCuePlan.Words.stationary && there.place.text == "KING'S CROSS")
        #expect(there.status.since == 4000, "typed from arrival")
    }

    @Test("Distances are true on the map's own shape")
    func aspect() {
        let plan = MapCuePlan(route(), settings: settings, aspect: 2)
        // On a map twice as wide as high, the top's 0.4 is 0.8 long, so a
        // third of the way by distance is short of the corner.
        let leg = plan.legs[0]
        #expect(abs(plan.point(on: leg, at: 2.0 / 3).x - 0.5) < 1e-9 && abs(plan.point(on: leg, at: 2.0 / 3).y - 0.1) < 1e-9)
        #expect(plan.point(on: leg, at: 1.0 / 3).x < 0.5)
    }

    @Test("A jump: the dot and trail vanish, SIGNAL LOST, the view cuts, and the dot comes back with SIGNAL ACQUIRED")
    func jump() {
        let plan = MapCuePlan(route(), settings: settings), timeline = GoTimeline(parts: plan.parts)
        let lost = plan.state(at: 51, timeline: timeline)
        #expect(!lost.dotVisible && lost.signal == .lost && lost.status.text == MapCuePlan.Words.lost)
        #expect(lost.view == p(0.5, 0.5), "still on the old place")
        #expect(plan.trail(at: 51, timeline: timeline, seconds: 8).isEmpty)
        let back = plan.state(at: 50 + 19, timeline: timeline)
        #expect(back.dotVisible && back.dot == p(0.9, 0.9) && back.view == back.dot && back.signal == .acquired)
        #expect(back.trailSince == 6800, "no trail from before the cut")
        let trail = plan.trail(at: 50 + 19, timeline: timeline, seconds: 8)
        #expect(trail.allSatisfy { $0.point == p(0.9, 0.9) })
        let settled = plan.state(at: 85, timeline: timeline)
        #expect(settled.signal == .live && settled.status.text == "MOVING" && settled.place.text == "DOCKS")
        #expect(!plan.isFinished(at: 83.9, timeline: timeline) && plan.isFinished(at: 84, timeline: timeline))
    }

    @Test("Each stop on GO: the dot waits at its start, and at each stop, for GO")
    func eachOnGO() {
        var s = settings
        s.advance = .eachAnagram
        let content = route(), plan = MapCuePlan(content, settings: s)
        #expect(plan.parts == [0, 40, 34])
        var timeline = GoTimeline(parts: plan.parts)
        #expect(timeline.isWaiting(at: 0) && plan.state(at: 100, timeline: timeline).dot == p(0.1, 0.1))
        timeline.carryOn(at: 100)
        #expect(plan.state(at: 120, timeline: timeline).dot.x == 0.5)
        #expect(content.goPoints(eachStopOnGO: true) == [GoPoint(unit: .stop, text: "KING'S CROSS"), GoPoint(unit: .stop, text: "DOCKS (jump)")])
        timeline.jump(toPart: 2, at: 300)
        #expect(plan.state(at: 300, timeline: timeline).dot == p(0.5, 0.5), "straight to the stop before")
    }

    @Test("The trail is where the dot was, fading with age, as long as the Trail setting")
    func trail() {
        let plan = MapCuePlan(route(), settings: settings), timeline = GoTimeline(parts: plan.parts)
        let trail = plan.trail(at: 30, timeline: timeline, seconds: 2, stepMs: 500)
        #expect(trail.map(\.age) == [1, 0.75, 0.5, 0.25, 0])
        #expect(trail.first?.point == plan.state(at: 10, timeline: timeline).dot)
        #expect(plan.trail(at: 30, timeline: timeline, seconds: 0).isEmpty)
    }

    @Test("Text types out a letter at a time, the first at once")
    func typing() {
        let line = MapCuePlan.Line(text: "SOHO", since: 1000)
        #expect(line.typed(at: 1000) == "S" && line.typed(at: 1000 + 2.5 * Double(MapCuePlan.typeMs)) == "SOH")
        #expect(line.isTyping(at: 1000) && !line.isTyping(at: 2000))
    }

    @Test("The dot lights hard once a second, and its ring spreads out and goes")
    func pulse() {
        #expect(MapPulse.brightness(at: 3000) == 1)
        #expect(MapPulse.brightness(at: 3600) < 0.4)
        #expect(MapPulse.ring(at: 3000) == 0 && MapPulse.ring(at: 3400) == 0.5 && MapPulse.ring(at: 3900) == nil)
        #expect(MapPulse.brightness(at: -1000) == 1, "through the hold too")
    }

    @Test("Coordinates come from two known places, always the same width")
    func coordinates() throws {
        let reference = MapReference(a: MapAnchor(at: p(0, 0), latitude: 52, longitude: -1), b: MapAnchor(at: p(1, 1), latitude: 51, longitude: 0))
        let c = try #require(reference.coordinates(of: p(0.5, 0.5)))
        #expect(c.latitude == 51.5 && c.longitude == -0.5)
        #expect(MapReference.format(latitude: c.latitude, longitude: c.longitude) == "51.50000 N  000.50000 W")
        #expect(MapReference.format(latitude: -33.8688, longitude: 151.2093).count == MapReference.lost.count)
        let flat = MapReference(a: MapAnchor(at: p(0, 0.5), latitude: 52, longitude: -1), b: MapAnchor(at: p(1, 0.5), latitude: 51, longitude: 0))
        #expect(flat.coordinates(of: p(0.5, 0.5)) == nil)
    }

    @Test("show.json holds the route; a show with a map is version 5, and a show without stays as it was")
    func json() throws {
        var content = route()
        content.reference = MapReference(a: MapAnchor(at: p(0, 0), latitude: 52, longitude: -1), b: MapAnchor(at: p(1, 1), latitude: 51, longitude: 0))
        content.settings = MapSettings(zoom: 4, trailSeconds: 3)
        let cue = Cue(number: "12", content: .map(content))
        let data = try JSONEncoder().encode(cue)
        #expect(try JSONDecoder().decode(Cue.self, from: data) == cue)
        #expect(cue.mediaPaths == ["media/london.png"])
        #expect(cue.finishes && !cue.isInstant)
        #expect(Show(cues: [cue]).version == 5)
    }

    @Test("A map has Clock, Hold, Advance, Pause, View, Zoom and Trail, and Advance offers Each stop on GO")
    func settingKeys() {
        #expect(SettingKey.allCases.filter { $0.applies(to: .map) } == [.clock, .hold, .advance, .pause, .camera, .zoom, .trail, .transition, .fade, .wipeFrom])
        #expect(SettingKey.camera.choices().map(\.label) == ["Follows the dot", "Holds still"])
        #expect(SettingKey.camera.format(.camera(.still)) == "holds still")
        #expect(SettingKey.advance.choices(for: .map).map(\.label) == ["By itself", "Each stop on GO"])
        #expect(SettingKey.zoom.format(.number(3)) == "3\u{00D7}" && SettingKey.trail.format(.number(0)) == "none")
        var cue = Cue(content: .map(MapContent()))
        SettingKey.zoom.set(.number(5), in: &cue)
        #expect(SettingKey.zoom.value(in: cue) == .number(5))
    }

    @Test("Held still, the view frames the whole route, the stage's shape, no closer than Zoom, inside the map")
    func stillView() {
        func view(_ points: [PicturePoint], aspect: Double, stage: Double, zoom: Int) -> (centre: PicturePoint, width: Double) {
            let content = MapContent(route: points.map { RoutePoint(at: $0, stop: MapStop()) })
            return MapCuePlan(content, settings: MapSettings(camera: .still, zoom: zoom), aspect: aspect).stillView(stageAspect: stage)
        }
        let wide = view([p(0.1, 0.25), p(0.9, 0.25), p(0.5, 0.75)], aspect: 2, stage: 16.0 / 9, zoom: 3)
        #expect(wide.centre == p(0.5, 0.5) && wide.width == 1, "a route across the map shows all of it")
        let short = view([p(0.5, 0.5), p(0.52, 0.5)], aspect: 1, stage: 1, zoom: 4)
        #expect(short.width == 0.25 && abs(short.centre.x - 0.51) < 1e-12, "no closer than Zoom 4")
        let corner = view([p(0.05, 0.05), p(0.1, 0.1)], aspect: 1, stage: 1, zoom: 4)
        #expect(corner.centre == p(0.125, 0.125), "kept inside the map's edges")
        #expect(MapCuePlan(MapContent(), settings: MapSettings(camera: .still)).stillView(stageAspect: 1).width == 1)
    }

    @Test("The sheet flags a map without its picture or a stop, and lists the stops")
    func sheet() {
        let empty = Cue(number: "12", content: .map(MapContent(text: "TRACK")))
        let show = Show(title: "T", cues: [empty, Cue(number: "13", content: .map(route()))])
        #expect(show.issues == [.mapWithoutMap(cue: empty.id), .mapWithoutStops(cue: empty.id)])
        #expect(show.message(for: show.issues[1]) == "Cue 12 needs a route with a stop after its start, or the dot never moves.")
        let rows = CueSheet(show: show, title: "T", layout: .dsm).rows
        #expect(rows[1].content == ["OPERATION NIGHTJAR", "SOHO \u{2192} KING'S CROSS \u{2192} \u{21AF} DOCKS"])
        let settings = CueSheet(show: show, title: "T", layout: .operatorSettings).rows[1].settings
        #expect(settings.first { $0.name == "Route" }?.value == "2 stops, 1 by a jump")
        #expect(settings.map(\.name).prefix(7) == ["Clock", "Hold", "Advance", "Pause", "View", "Zoom", "Trail"])
    }
}
