import Foundation

/// A layered image cue: one picture assembled from several images that
/// arrive one at a time, each on its own GO, so an actor can describe a
/// painting part by part while the parts appear as they are named.
///
/// The layers are what gets edited. What everything else counts in is the
/// derived step list (`steps`): a GO's worth of change to the picture, which
/// may bring on several layers at once or take one off again.
public struct LayeredContent: Equatable, Sendable {
    /// The cue's name, and what the stage shows when there are no pictures.
    public var text: String
    /// The whole picture, under every layer. Empty is black.
    public var base: String
    /// The layers in the order they arrive, which is also the order they
    /// stack: the last to arrive sits on top.
    public var layers: [ImageLayer]
    public var settings: LayeredSettings

    public init(text: String = "", base: String = "", layers: [ImageLayer] = [], settings: LayeredSettings = .init()) {
        self.text = text
        self.base = base
        self.layers = layers
        self.settings = settings
    }
}

/// How a layer composites over what is under it.
public enum LayerBlend: String, Codable, Sendable, CaseIterable {
    case normal, screen, multiply
}

/// Whether a layer stays once it has arrived.
public enum LayerLife: String, Codable, Sendable, CaseIterable {
    /// It stays to the end of the cue.
    case stays
    /// It goes as the next layer arrives: one GO, the wrong part leaving as
    /// the right one comes up.
    case untilNextLayer
    /// It goes on a GO of its own, so the correction lands on its own beat
    /// before anything replaces it.
    case untilNextGo
}

/// What happens to the layers already standing while a new one arrives.
public enum LayerContext: String, Codable, Sendable, CaseIterable {
    case none, dim, desaturate, spotlight
}

/// What the arriving layer itself does.
public enum LayerEntrance: String, Codable, Sendable, CaseIterable {
    /// It fades up to its level, and nothing more.
    case fade
    /// Its alpha edge is drawn as a brass line that blooms and fades.
    case outline
    /// It fades in slightly magnified and settles to size.
    case settle
    /// It fades past its level and settles back.
    case bloom
}

/// What the frame does as the cue runs.
public enum LayeredCamera: String, Codable, Sendable, CaseIterable {
    /// It never moves: the whole picture, throughout.
    case still
    /// It pulls back out to the whole picture and then in on the new part,
    /// so the composition reasserts itself on every move.
    case push
    /// It travels from one part straight to the next, without pulling back.
    case travel
}

/// A layer's own highlight treatment. Nil takes the cue's.
public struct LayerHighlight: Codable, Equatable, Sendable {
    public var context: LayerContext?
    public var entrance: LayerEntrance?

    public init(context: LayerContext? = nil, entrance: LayerEntrance? = nil) {
        self.context = context
        self.entrance = entrance
    }

    public var isEmpty: Bool { self == LayerHighlight() }
}

/// A rectangle on a picture, as shares of its width and height from the top
/// left.
public struct PictureRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Pulled onto the picture, and no smaller than a sliver.
    public var clamped: PictureRect {
        let w = min(max(width, 0.01), 1), h = min(max(height, 0.01), 1)
        return PictureRect(x: min(max(x, 0), 1 - w), y: min(max(y, 0), 1 - h), width: w, height: h)
    }
}

/// One part of the picture, and the GO that brings it on.
public struct ImageLayer: Codable, Equatable, Sendable {
    /// Relative path inside the package. A full-frame image at the base's
    /// pixel size, with transparency.
    public var src: String
    /// What the operator and the DSM call it: "the hands", "the M".
    public var name: String
    /// The cue point of the GO that brings it on, when the cue waits for one.
    public var cuePoint: String
    /// The cue point of the GO that takes it off again, for a layer that
    /// goes on a GO of its own.
    public var exitCuePoint: String
    /// How long it takes to arrive, if not the cue's.
    public var fadeMs: Int?
    /// What it comes up to, as a percentage. Nil is full.
    public var level: Int?
    /// How it composites over what is under it.
    public var blend: LayerBlend
    /// It arrives on the same GO as the layer before it.
    public var withPrevious: Bool
    /// Whether it stays, or is taken off again: a false step.
    public var life: LayerLife
    /// Its own highlight treatment, if not the cue's.
    public var highlight: LayerHighlight?
    /// What the view frames as this layer arrives. Nil derives it from the
    /// layer's own opaque bounds.
    public var frame: PictureRect?

    public init(src: String = "", name: String = "", cuePoint: String = "", exitCuePoint: String = "", fadeMs: Int? = nil,
                level: Int? = nil, blend: LayerBlend = .normal, withPrevious: Bool = false, life: LayerLife = .stays,
                highlight: LayerHighlight? = nil, frame: PictureRect? = nil) {
        self.src = src
        self.name = name
        self.cuePoint = cuePoint
        self.exitCuePoint = exitCuePoint
        self.fadeMs = fadeMs
        self.level = level
        self.blend = blend
        self.withPrevious = withPrevious
        self.life = life
        self.highlight = highlight
        self.frame = frame
    }

    /// The shortest and longest a layer takes to arrive, and the levels.
    public static let fadeRange = 100...5000
    public static let levelRange = 5...100

    enum CodingKeys: String, CodingKey {
        case src, name, cuePoint, exitCuePoint, fadeMs, level, blend, withPrevious, life, highlight, frame
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        src = try c.decodeIfPresent(String.self, forKey: .src) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        cuePoint = try c.decodeIfPresent(String.self, forKey: .cuePoint) ?? ""
        exitCuePoint = try c.decodeIfPresent(String.self, forKey: .exitCuePoint) ?? ""
        fadeMs = try c.decodeIfPresent(Int.self, forKey: .fadeMs).map { Self.fadeRange.clamp($0) }
        level = try c.decodeIfPresent(Int.self, forKey: .level).map { Self.levelRange.clamp($0) }
        blend = try c.decodeIfPresent(LayerBlend.self, forKey: .blend) ?? .normal
        withPrevious = try c.decodeIfPresent(Bool.self, forKey: .withPrevious) ?? false
        life = try c.decodeIfPresent(LayerLife.self, forKey: .life) ?? .stays
        highlight = try c.decodeIfPresent(LayerHighlight.self, forKey: .highlight)
        frame = try c.decodeIfPresent(PictureRect.self, forKey: .frame)?.clamped
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(src, forKey: .src)
        if !name.isEmpty { try c.encode(name, forKey: .name) }
        if !cuePoint.isEmpty { try c.encode(cuePoint, forKey: .cuePoint) }
        if !exitCuePoint.isEmpty { try c.encode(exitCuePoint, forKey: .exitCuePoint) }
        try c.encodeIfPresent(fadeMs, forKey: .fadeMs)
        try c.encodeIfPresent(level, forKey: .level)
        if blend != .normal { try c.encode(blend, forKey: .blend) }
        if withPrevious { try c.encode(withPrevious, forKey: .withPrevious) }
        if life != .stays { try c.encode(life, forKey: .life) }
        if let highlight, !highlight.isEmpty { try c.encode(highlight, forKey: .highlight) }
        try c.encodeIfPresent(frame, forKey: .frame)
    }

    /// What the operator and the sheet call it: its name, or its file's.
    public var displayName: String {
        name.isEmpty ? MorphContent.name(of: src) : name
    }
}

// MARK: - The step list

/// One GO's worth of change to the picture.
public struct LayerStep: Equatable, Sendable {
    /// Layers that come up on this step, as places in `layers`.
    public let arriving: [Int]
    /// Layers taken off on this step.
    public let leaving: [Int]
    /// What this GO brings, for the standby panel and the cue list: "the
    /// hands", or for a withdrawal "the chalice goes".
    public let name: String
    /// What the sheet shows for it: the same, with a withdrawal marked.
    public let sheetName: String
    /// The cue point of this GO.
    public let cuePoint: String

    /// A step that only takes a layer off.
    public var isWithdrawal: Bool { arriving.isEmpty }
}

extension LayeredContent {
    /// Every step of the cue in order. The one source of truth for GO
    /// points, the plan's parts and what the stage shows.
    ///
    /// Layers arrive in groups, a layer marked `withPrevious` joining the
    /// group before it. A layer that lasts until the next layer leaves on the
    /// next group's step; one that lasts until the next GO gets a step of its
    /// own straight after its arrival. A layer that lasts until the next layer
    /// but has none after it gets a final step of its own too, as the other
    /// would, so it cannot stand for ever.
    public var steps: [LayerStep] {
        var result: [LayerStep] = []
        var pending: [Int] = []
        var i = 0

        func names(_ indices: [Int]) -> String {
            indices.map { layers[$0].displayName }.joined(separator: " + ")
        }
        func exitPoint(_ indices: [Int]) -> String {
            indices.lazy.map { layers[$0].exitCuePoint }.first { !$0.isEmpty } ?? ""
        }

        while i < layers.count {
            var group = [i]
            i += 1
            while i < layers.count, layers[i].withPrevious {
                group.append(i)
                i += 1
            }
            let leaving = pending
            pending = []
            var name = names(group)
            var sheet = name
            if !leaving.isEmpty {
                name += " (\(names(leaving)) goes)"
                sheet += " (\u{2715} \(names(leaving)))"
            }
            result.append(LayerStep(arriving: group, leaving: leaving, name: name, sheetName: sheet,
                                    cuePoint: layers[group[0]].cuePoint))
            for index in group {
                switch layers[index].life {
                case .stays: break
                case .untilNextLayer: pending.append(index)
                case .untilNextGo:
                    result.append(LayerStep(arriving: [], leaving: [index], name: layers[index].displayName + " goes",
                                            sheetName: "\u{2715} " + layers[index].displayName,
                                            cuePoint: layers[index].exitCuePoint))
                }
            }
        }
        if !pending.isEmpty {
            result.append(LayerStep(arriving: [], leaving: pending, name: names(pending) + " goes",
                                    sheetName: "\u{2715} " + names(pending), cuePoint: exitPoint(pending)))
        }
        return result
    }

    /// The layers standing once the step at index `k` has run, bottom of the
    /// stack first. Before any step (`k` below 0) there are none; past the
    /// last, those left at the end. A function of the step alone, so a jump
    /// to any step, forward or back, lands on the same picture.
    public func layers(after k: Int) -> [Int] {
        var standing = Set<Int>()
        for step in steps.prefix(max(k + 1, 0)) {
            standing.formUnion(step.arriving)
            standing.subtract(step.leaving)
        }
        return standing.sorted()
    }

    /// Where the cue waits for GO, in order: before each step. None when it
    /// moves on by itself.
    public func goPoints(eachStepOnGO: Bool) -> [GoPoint] {
        guard eachStepOnGO else { return [] }
        return steps.map { GoPoint(unit: .layer, text: $0.name, cuePoint: $0.cuePoint) }
    }

    /// Whether any GO has a cue point of its own.
    var hasGoCuePoints: Bool {
        layers.contains { !$0.cuePoint.isEmpty || !$0.exitCuePoint.isEmpty }
    }

    /// Sets the cue point of the GO at step `index`: on the layer that
    /// arrives with it, or for a withdrawal on the layer that goes.
    mutating func setCuePoint(_ line: String, ofStep index: Int) {
        let all = steps
        guard all.indices.contains(index) else { return }
        let step = all[index]
        if let first = step.arriving.first {
            layers[first].cuePoint = line
        } else if let first = step.leaving.first {
            layers[first].exitCuePoint = line
            // A final step of several layers keeps one cue point between
            // them: the others' stale ones would be read first otherwise.
            for other in step.leaving.dropFirst() { layers[other].exitCuePoint = "" }
        }
    }

    /// The paths of the base and every layer.
    public var mediaPaths: [String] {
        ([base] + layers.map(\.src)).filter { !$0.isEmpty }
    }

    /// Layer `from` moved to `to`, arrival and stacking together.
    public mutating func moveLayer(from: Int, to: Int) {
        guard layers.indices.contains(from), layers.indices.contains(to), from != to else { return }
        layers.insert(layers.remove(at: from), at: to)
    }

    public mutating func removeLayer(at index: Int) {
        guard layers.indices.contains(index) else { return }
        layers.remove(at: index)
    }
}

// MARK: - Settings

/// A layered cue's settings.
public struct LayeredSettings: Codable, Equatable, Sendable {
    public var clockMs: Int
    public var holdTicks: Int
    /// Either GO choice waits for GO before each step.
    public var advance: AnagramAdvance
    public var pauseTicks: Int
    /// How long a layer takes to arrive.
    public var layerMs: Int
    /// What the base picture sits at, as a percentage.
    public var baseLevel: Int
    /// What happens to the layers already standing, and how far it goes.
    public var context: LayerContext
    public var contextLevel: Int
    /// How long the treatment lasts, in clock ticks.
    public var contextTicks: Int
    /// What the arriving layer does.
    public var entrance: LayerEntrance
    public var camera: LayeredCamera
    /// The closest the frame comes: the picture's width over this.
    public var zoom: Int
    /// How long a camera move takes.
    public var cameraMs: Int

    public init(clockMs: Int = 44, holdTicks: Int = 44, advance: AnagramAdvance = .byItself, pauseTicks: Int = 44,
                layerMs: Int = 800, baseLevel: Int = 25, context: LayerContext = .desaturate, contextLevel: Int = 60,
                contextTicks: Int = 22, entrance: LayerEntrance = .outline, camera: LayeredCamera = .still, zoom: Int = 3,
                cameraMs: Int = 1200) {
        self.clockMs = clockMs
        self.holdTicks = holdTicks
        self.advance = advance
        self.pauseTicks = pauseTicks
        self.layerMs = layerMs
        self.baseLevel = baseLevel
        self.context = context
        self.contextLevel = contextLevel
        self.contextTicks = contextTicks
        self.entrance = entrance
        self.camera = camera
        self.zoom = zoom
        self.cameraMs = cameraMs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LayeredSettings()
        clockMs = try c.value(.clockMs, d.clockMs, in: SettingRange.clockMs)
        holdTicks = try c.value(.holdTicks, d.holdTicks, in: SettingRange.holdTicks)
        advance = try c.value(.advance, d.advance)
        pauseTicks = try c.value(.pauseTicks, d.pauseTicks, in: SettingRange.pauseTicks)
        layerMs = try c.value(.layerMs, d.layerMs, in: SettingRange.layerMs)
        baseLevel = try c.value(.baseLevel, d.baseLevel, in: SettingRange.baseLevel)
        context = try c.value(.context, d.context)
        contextLevel = try c.value(.contextLevel, d.contextLevel, in: SettingRange.contextLevel)
        contextTicks = try c.value(.contextTicks, d.contextTicks, in: SettingRange.contextTicks)
        entrance = try c.value(.entrance, d.entrance)
        camera = try c.value(.camera, d.camera)
        zoom = try c.value(.zoom, d.zoom, in: SettingRange.mapZoom)
        cameraMs = try c.value(.cameraMs, d.cameraMs, in: SettingRange.cameraMs)
    }

    /// Whether each step waits for GO.
    public var eachStepOnGO: Bool { advance != .byItself }
}
