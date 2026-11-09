import Foundation

/// A live feed cue: the picture from a camera, shown as it arrives. The
/// camera is a capture device on this Mac (a webcam, a capture card, an
/// iPhone by Continuity Camera, or a virtual camera another app provides for
/// a wireless source), so the cue holds which one, not where a file is.
///
/// A live feed never finishes: it stays up until the next cue replaces it,
/// as a looping clip does. It is always silent.
public struct FeedContent: Equatable, Sendable {
    /// The cue's name.
    public var text: String
    /// The caption.
    public var sub: String
    public var settings: FeedSettings

    public init(text: String = "", sub: String = "", settings: FeedSettings = .init()) {
        self.text = text
        self.sub = sub
        self.settings = settings
    }
}

/// A live feed cue's settings.
public struct FeedSettings: Codable, Equatable, Sendable {
    /// The capture device's unique ID. Empty is a sheet problem.
    public var device: String
    /// The device's name when it was chosen. A device's ID can differ from
    /// machine to machine, so where the ID isn't found the name is looked for.
    public var deviceName: String
    /// Flip the picture left to right, as a mirror does: for a camera that
    /// faces the person it films.
    public var mirror: Bool
    public var rotation: FeedRotation
    public var fit: FeedFit
    /// What the stage does when the feed is lost.
    public var onLoss: FeedLoss

    public init(device: String = "", deviceName: String = "", mirror: Bool = false, rotation: FeedRotation = .none,
                fit: FeedFit = .fit, onLoss: FeedLoss = .black) {
        self.device = device
        self.deviceName = deviceName
        self.mirror = mirror
        self.rotation = rotation
        self.fit = fit
        self.onLoss = onLoss
    }

    private enum CodingKeys: String, CodingKey {
        case device, deviceName, mirror, rotation, fit, onLoss
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FeedSettings()
        device = try c.value(.device, d.device)
        deviceName = try c.value(.deviceName, d.deviceName)
        mirror = try c.value(.mirror, d.mirror)
        // A hand-edited value that isn't one of the choices is the default.
        rotation = (try? c.decodeIfPresent(FeedRotation.self, forKey: .rotation)) ?? d.rotation
        fit = (try? c.decodeIfPresent(FeedFit.self, forKey: .fit)) ?? d.fit
        onLoss = (try? c.decodeIfPresent(FeedLoss.self, forKey: .onLoss)) ?? d.onLoss
    }
}

/// How far a live feed is turned, clockwise, for a camera that isn't held
/// the right way up.
public enum FeedRotation: Int, Codable, Sendable, CaseIterable {
    case none = 0, quarter = 90, half = 180, threeQuarters = 270

    public var name: String {
        switch self {
        case .none: "None"
        case .quarter: "90\u{00B0} clockwise"
        case .half: "180\u{00B0}"
        case .threeQuarters: "90\u{00B0} anticlockwise"
        }
    }

    /// Whether the turn swaps the picture's width and height.
    public var isSideways: Bool { self == .quarter || self == .threeQuarters }
}

/// How a live feed sits in the projection area.
public enum FeedFit: String, Codable, Sendable, CaseIterable {
    /// All of the picture, with black bars where its shape differs.
    case fit
    /// The area filled, with the edges of the picture cropped.
    case fill

    public var name: String { rawValue.capitalized }
}

/// What the stage does when a live feed is lost, as a clip's end does.
public enum FeedLoss: String, Codable, Sendable, CaseIterable {
    /// Cut to black. A frozen face looks like a fault to an audience.
    case black
    /// Freeze on the last frame.
    case hold

    public var name: String { rawValue.capitalized }
}
