import Foundation

/// A police tracking map: a map the audience watches slide under a blinking
/// red dot as it follows a route, stop to stop.
public struct MapContent: Equatable, Sendable {
    /// The header, typed out at the top of the screen.
    public var text: String
    /// The map: a relative path inside the package.
    public var src: String
    /// The route in order. The first point is where the dot starts.
    public var route: [RoutePoint]
    /// Two places on the map whose latitude and longitude are known, for the
    /// coordinates on screen. Without them, none are shown.
    public var reference: MapReference?
    public var overrides: MapOverrides

    public init(text: String = "", src: String = "", route: [RoutePoint] = [], reference: MapReference? = nil,
                overrides: MapOverrides = .init()) {
        self.text = text
        self.src = src
        self.route = route
        self.reference = reference
        self.overrides = overrides
    }

    /// Where the dot rests, as places in the route: the start, then every
    /// stop.
    public var stops: [Int] {
        route.indices.filter { $0 == 0 || route[$0].stop != nil }
    }

    /// The stop at a place in the route, the start as a stop with nothing
    /// to say if it has none.
    public func stop(at index: Int) -> MapStop {
        route[index].stop ?? MapStop()
    }
}

/// A point on the route.
public struct RoutePoint: Codable, Equatable, Sendable {
    /// Where it is on the map.
    public var at: PicturePoint
    /// What the dot does there: rests, if it is a stop, or nil for a point
    /// that only shapes the route between stops. The first point is where
    /// the dot starts, stop or not.
    public var stop: MapStop?

    public init(at: PicturePoint, stop: MapStop? = nil) {
        self.at = at
        self.stop = stop
    }
}

/// How the dot reaches a stop: travelling along the route, or jumping.
public enum MapArrival: String, Codable, Sendable, CaseIterable {
    case travel, jump
}

/// Where the dot rests, how it gets there, and what the screen says once it
/// does.
public struct MapStop: Codable, Equatable, Sendable {
    public var arrival: MapArrival
    /// How long it travels from the stop before, through the points between.
    public var travelMs: Int
    /// The status line on arrival. Empty says STATIONARY.
    public var status: String
    /// The place name beneath it.
    public var place: String
    /// The cue point of the GO before the dot leaves for it, when the cue
    /// waits for one.
    public var cuePoint: String

    public init(arrival: MapArrival = .travel, travelMs: Int = 4000, status: String = "", place: String = "", cuePoint: String = "") {
        self.arrival = arrival
        self.travelMs = travelMs
        self.status = status
        self.place = place
        self.cuePoint = cuePoint
    }

    public static let travelRange = 500...60000

    enum CodingKeys: String, CodingKey {
        case arrival, travelMs, status, place, cuePoint
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        arrival = try c.decodeIfPresent(MapArrival.self, forKey: .arrival) ?? .travel
        travelMs = Self.travelRange.clamp(try c.decodeIfPresent(Int.self, forKey: .travelMs) ?? 4000)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        place = try c.decodeIfPresent(String.self, forKey: .place) ?? ""
        cuePoint = try c.decodeIfPresent(String.self, forKey: .cuePoint) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(arrival, forKey: .arrival)
        if arrival == .travel { try c.encode(travelMs, forKey: .travelMs) }
        if !status.isEmpty { try c.encode(status, forKey: .status) }
        if !place.isEmpty { try c.encode(place, forKey: .place) }
        if !cuePoint.isEmpty { try c.encode(cuePoint, forKey: .cuePoint) }
    }
}

/// A place on the map whose latitude and longitude are known.
public struct MapAnchor: Codable, Equatable, Sendable {
    public var at: PicturePoint
    public var latitude: Double
    public var longitude: Double

    public init(at: PicturePoint, latitude: Double, longitude: Double) {
        self.at = at
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Two known places, from which every other point's latitude and longitude
/// follow: latitude down the map, longitude across it, each in proportion.
/// Near enough for a town's map.
public struct MapReference: Codable, Equatable, Sendable {
    public var a: MapAnchor
    public var b: MapAnchor

    public init(a: MapAnchor, b: MapAnchor) {
        self.a = a
        self.b = b
    }

    /// A point's latitude and longitude. Nil when the two places share a
    /// row or a column, which can't say how the other runs.
    public func coordinates(of p: PicturePoint) -> (latitude: Double, longitude: Double)? {
        let dx = b.at.x - a.at.x, dy = b.at.y - a.at.y
        guard abs(dx) > 1e-6, abs(dy) > 1e-6 else { return nil }
        return (a.latitude + (p.y - a.at.y) / dy * (b.latitude - a.latitude),
                a.longitude + (p.x - a.at.x) / dx * (b.longitude - a.longitude))
    }

    /// As the screen shows them, always the same width so the readout never
    /// jitters: `51.50740 N  000.12780 W`.
    public static func format(latitude: Double, longitude: Double) -> String {
        let lat = String(format: "%08.5f", abs(latitude)), lon = String(format: "%09.5f", abs(longitude))
        return "\(lat) \(latitude < 0 ? "S" : "N")  \(lon) \(longitude < 0 ? "W" : "E")"
    }

    /// What the readout shows while the signal is lost.
    public static let lost = "--.----- -  ---.----- -"
}

/// What the view does as the dot moves.
public enum MapCamera: String, Codable, Sendable, CaseIterable {
    /// The dot stays at the middle of the stage, and the map slides under it.
    case follow
    /// The map stays put, framed round the whole route, and the dot moves
    /// across it.
    case still
}

/// A map cue's own values for settings the show holds defaults for. Nil
/// inherits the show's default.
public struct MapOverrides: Codable, Equatable, Sendable {
    public var clockMs: Int?
    public var holdTicks: Int?
    /// Either GO choice waits for GO before the dot leaves for each stop.
    public var advance: AnagramAdvance?
    public var pauseTicks: Int?
    public var camera: MapCamera?
    public var zoom: Int?
    public var trailSeconds: Int?

    public init(clockMs: Int? = nil, holdTicks: Int? = nil, advance: AnagramAdvance? = nil, pauseTicks: Int? = nil, camera: MapCamera? = nil,
                zoom: Int? = nil, trailSeconds: Int? = nil) {
        self.clockMs = clockMs
        self.holdTicks = holdTicks
        self.advance = advance
        self.pauseTicks = pauseTicks
        self.camera = camera
        self.zoom = zoom
        self.trailSeconds = trailSeconds
    }

    public var isEmpty: Bool { self == MapOverrides() }

    func clamped() -> MapOverrides {
        var o = self
        o.clockMs = clockMs.map { SettingRange.clockMs.clamp($0) }
        o.holdTicks = holdTicks.map { SettingRange.holdTicks.clamp($0) }
        o.pauseTicks = pauseTicks.map { SettingRange.pauseTicks.clamp($0) }
        o.zoom = zoom.map { SettingRange.mapZoom.clamp($0) }
        o.trailSeconds = trailSeconds.map { SettingRange.trailSeconds.clamp($0) }
        return o
    }
}

/// The settings a map cue runs with, once its overrides are applied.
public struct MapSettings: Equatable, Sendable {
    public var clockMs: Int
    public var holdTicks: Int
    public var advance: AnagramAdvance
    public var pauseTicks: Int
    public var camera: MapCamera
    /// Following the dot, how many stage widths the map is drawn across;
    /// holding still, the closest the frame comes.
    public var zoom: Int
    /// How long the trail behind the dot lasts.
    public var trailSeconds: Int

    public init(clockMs: Int = 44, holdTicks: Int = 44, advance: AnagramAdvance = .byItself, pauseTicks: Int = 44, camera: MapCamera = .follow,
                zoom: Int = 3, trailSeconds: Int = 8) {
        self.clockMs = clockMs
        self.holdTicks = holdTicks
        self.advance = advance
        self.pauseTicks = pauseTicks
        self.camera = camera
        self.zoom = zoom
        self.trailSeconds = trailSeconds
    }

    /// Whether each stop waits for GO.
    public var eachStopOnGO: Bool { advance != .byItself }
}
