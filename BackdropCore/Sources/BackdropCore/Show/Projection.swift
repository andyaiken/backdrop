import CoreGraphics
import Foundation

/// Where the picture lands within the projector output, as percentages of
/// it, so it holds if the resolution changes.
public struct Geometry: Equatable, Sendable {
    public var width = 100
    public var height = 100
    /// Offset from centre; positive is right.
    public var across = 0
    /// Offset from centre; positive is down.
    public var down = 0

    public init(width: Int = 100, height: Int = 100, across: Int = 0, down: Int = 0) {
        self.width = width
        self.height = height
        self.across = across
        self.down = down
    }
}

extension Geometry {
    /// The part of an output of `size` the picture lands on, with a top-left
    /// origin: centred, then offset, all in percentages of the output.
    public func insetRect(in size: CGSize) -> CGRect {
        let w = CGFloat(width) / 100, h = CGFloat(height) / 100
        return CGRect(
            x: ((1 - w) / 2 + CGFloat(across) / 100) * size.width,
            y: ((1 - h) / 2 + CGFloat(down) / 100) * size.height,
            width: w * size.width,
            height: h * size.height
        )
    }
}

extension Geometry: Codable {
    private enum CodingKeys: String, CodingKey { case width, height, across, down }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = SettingRange.geometrySize.clamp(try c.decodeIfPresent(Int.self, forKey: .width) ?? 100)
        height = SettingRange.geometrySize.clamp(try c.decodeIfPresent(Int.self, forKey: .height) ?? 100)
        across = SettingRange.geometryOffset.clamp(try c.decodeIfPresent(Int.self, forKey: .across) ?? 0)
        down = SettingRange.geometryOffset.clamp(try c.decodeIfPresent(Int.self, forKey: .down) ?? 0)
    }
}

/// Enough about a display to find it again. `CGDirectDisplayID` is not
/// stored, because it can change when a cable is replugged.
public struct DisplayIdentity: Codable, Equatable, Sendable {
    /// From `CGDisplayCreateUUIDFromDisplayID`.
    public var uuid: String?
    public var name: String
    public var vendor: UInt32?
    public var model: UInt32?

    public init(uuid: String? = nil, name: String, vendor: UInt32? = nil, model: UInt32? = nil) {
        self.uuid = uuid
        self.name = name
        self.vendor = vendor
        self.model = model
    }

    /// The connected display that is this one: the same UUID, failing that
    /// the same vendor and model, failing that the same name.
    public func bestMatch(in candidates: [DisplayIdentity]) -> Int? {
        if let uuid, let i = candidates.firstIndex(where: { $0.uuid == uuid }) { return i }
        if let vendor, let model,
           let i = candidates.firstIndex(where: { $0.vendor == vendor && $0.model == model }) { return i }
        return candidates.firstIndex { $0.name == name }
    }
}
