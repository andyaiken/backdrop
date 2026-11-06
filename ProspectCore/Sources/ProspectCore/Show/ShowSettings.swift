import Foundation

/// The show's defaults for every per-cue setting, plus what is show-wide.
public struct ShowSettings: Equatable, Sendable {
    /// Milliseconds per frame of the cue clock.
    public var clockMs = 44
    /// Frames between successive characters, or diagonal tile steps.
    public var waveTicks = 3
    /// Frames a cue holds its opening state before it starts to resolve.
    public var holdTicks = 44
    public var histogram = true
    public var sceneLine = true
    public var letters = TitleLetters.cycle
    public var bars = TitleBars.letters
    public var gridColumns = 12
    public var flipMs = 420
    public var order = TileOrder.diagonal
    public var reveal = TileReveal.flip
    /// How an anagram cue moves on from each step, and a morph cue from each
    /// picture: by itself, or on GO. For a morph, either GO choice waits for
    /// GO before each stage.
    public var advance = AnagramAdvance.byItself
    /// Frames an anagram rests on each step before the next moves, and a
    /// morph on each picture.
    public var pauseTicks = 44
    /// The font family anagram letters are set in. Empty is the stage's own
    /// type, SF Mono.
    public var anagramFont = ""
    /// How long a morph takes, from the first picture to the second.
    public var morphMs = 3000
    /// Whether a map cue's view follows its dot, or holds still.
    public var mapCamera = MapCamera.follow
    /// How many stage widths a map cue's map is drawn across.
    public var mapZoom = 3
    /// How long the trail behind a map cue's dot lasts.
    public var trailSeconds = 8
    /// How long a layered cue's layer takes to arrive, what its base picture
    /// sits at (percent), and what happens to the layers already standing:
    /// the treatment, how far it goes (percent) and how long it lasts.
    public var layerMs = 800
    public var baseLevel = 25
    public var layeredContext = LayerContext.desaturate
    public var contextLevel = 60
    public var contextTicks = 22
    public var layeredEntrance = LayerEntrance.outline
    /// What a layered cue's frame does, and how long a move takes.
    public var layeredCamera = LayeredCamera.still
    public var cameraMs = 1200
    /// How the stage changes to each cue, and how long each fade takes.
    public var transition = Transition.standard.style
    public var fadeMs = Transition.standard.fadeMs

    /// Title text size, percent. Show-wide.
    public var textScale = 100
    /// Show-wide.
    public var geometry = Geometry()
    /// The display the projector window last ran on.
    public var projector: DisplayIdentity?

    public init() {}

    public func resolved(_ o: TitleOverrides) -> TitleSettings {
        TitleSettings(
            clockMs: o.clockMs ?? clockMs,
            waveTicks: o.waveTicks ?? waveTicks,
            holdTicks: o.holdTicks ?? holdTicks,
            histogram: o.histogram ?? histogram,
            sceneLine: o.sceneLine ?? sceneLine,
            letters: o.letters ?? letters,
            bars: o.bars ?? bars
        )
    }

    public func resolved(_ o: AnagramOverrides) -> AnagramSettings {
        AnagramSettings(clockMs: o.clockMs ?? clockMs, waveTicks: o.waveTicks ?? waveTicks, holdTicks: o.holdTicks ?? holdTicks,
                        advance: o.advance ?? advance, pauseTicks: o.pauseTicks ?? pauseTicks, font: o.font ?? anagramFont)
    }

    public func resolved(_ o: MorphOverrides) -> MorphSettings {
        MorphSettings(clockMs: o.clockMs ?? clockMs, holdTicks: o.holdTicks ?? holdTicks, morphMs: o.morphMs ?? morphMs,
                      advance: o.advance ?? advance, pauseTicks: o.pauseTicks ?? pauseTicks)
    }

    public func resolved(_ o: MapOverrides) -> MapSettings {
        MapSettings(clockMs: o.clockMs ?? clockMs, holdTicks: o.holdTicks ?? holdTicks, advance: o.advance ?? advance,
                    pauseTicks: o.pauseTicks ?? pauseTicks, camera: o.camera ?? mapCamera, zoom: o.zoom ?? mapZoom,
                    trailSeconds: o.trailSeconds ?? trailSeconds)
    }

    public func resolved(_ o: LayeredOverrides) -> LayeredSettings {
        LayeredSettings(clockMs: o.clockMs ?? clockMs, holdTicks: o.holdTicks ?? holdTicks, advance: o.advance ?? advance,
                        pauseTicks: o.pauseTicks ?? pauseTicks, layerMs: o.layerMs ?? layerMs, baseLevel: o.baseLevel ?? baseLevel,
                        context: o.context ?? layeredContext, contextLevel: o.contextLevel ?? contextLevel,
                        contextTicks: o.contextTicks ?? contextTicks, entrance: o.entrance ?? layeredEntrance,
                        camera: o.camera ?? layeredCamera, zoom: o.zoom ?? mapZoom, cameraMs: o.cameraMs ?? self.cameraMs)
    }

    public func resolved(_ o: ImageOverrides) -> ImageSettings {
        ImageSettings(
            clockMs: o.clockMs ?? clockMs,
            waveTicks: o.waveTicks ?? waveTicks,
            holdTicks: o.holdTicks ?? holdTicks,
            gridColumns: o.gridColumns ?? gridColumns,
            flipMs: o.flipMs ?? flipMs,
            order: o.order ?? order,
            reveal: o.reveal ?? reveal
        )
    }
}

/// The settings a title cue runs with, once its overrides are applied.
public struct TitleSettings: Equatable, Sendable {
    public var clockMs: Int
    public var waveTicks: Int
    public var holdTicks: Int
    public var histogram: Bool
    public var sceneLine: Bool
    public var letters: TitleLetters
    public var bars: TitleBars

    public init(clockMs: Int, waveTicks: Int, holdTicks: Int, histogram: Bool, sceneLine: Bool, letters: TitleLetters = .cycle,
                bars: TitleBars = .letters) {
        self.clockMs = clockMs
        self.waveTicks = waveTicks
        self.holdTicks = holdTicks
        self.histogram = histogram
        self.sceneLine = sceneLine
        self.letters = letters
        self.bars = bars
    }
}

/// The settings an anagram cue runs with, once its overrides are applied.
public struct AnagramSettings: Equatable, Sendable {
    public var clockMs: Int
    public var waveTicks: Int
    public var holdTicks: Int
    public var advance: AnagramAdvance
    public var pauseTicks: Int
    /// A font family's name. Empty is the stage's own type.
    public var font: String

    public init(clockMs: Int, waveTicks: Int, holdTicks: Int, advance: AnagramAdvance = .byItself, pauseTicks: Int = 44, font: String = "") {
        self.clockMs = clockMs
        self.waveTicks = waveTicks
        self.holdTicks = holdTicks
        self.advance = advance
        self.pauseTicks = pauseTicks
        self.font = font
    }
}

/// The settings a morph cue runs with, once its overrides are applied.
public struct MorphSettings: Equatable, Sendable {
    public var clockMs: Int
    public var holdTicks: Int
    public var morphMs: Int
    /// Either GO choice waits for GO before each stage.
    public var advance: AnagramAdvance
    /// Frames each picture rests before the next stage, when the cue moves
    /// on by itself.
    public var pauseTicks: Int

    public init(clockMs: Int, holdTicks: Int, morphMs: Int, advance: AnagramAdvance = .byItself, pauseTicks: Int = 44) {
        self.clockMs = clockMs
        self.holdTicks = holdTicks
        self.morphMs = morphMs
        self.advance = advance
        self.pauseTicks = pauseTicks
    }

    /// Whether each stage waits for GO.
    public var eachStageOnGO: Bool { advance != .byItself }
}

/// The settings an image cue runs with, once its overrides are applied.
public struct ImageSettings: Equatable, Sendable {
    public var clockMs: Int
    public var waveTicks: Int
    public var holdTicks: Int
    public var gridColumns: Int
    public var flipMs: Int
    public var order: TileOrder
    public var reveal: TileReveal

    public init(clockMs: Int, waveTicks: Int, holdTicks: Int, gridColumns: Int, flipMs: Int, order: TileOrder, reveal: TileReveal = .flip) {
        self.clockMs = clockMs
        self.waveTicks = waveTicks
        self.holdTicks = holdTicks
        self.gridColumns = gridColumns
        self.flipMs = flipMs
        self.order = order
        self.reveal = reveal
    }
}

/// How a cue's clock runs: the tick length, and how many ticks it holds its
/// opening state before resolving.
public struct CueTiming: Equatable, Sendable {
    public var clockMs: Int
    public var holdTicks: Int
    /// Nothing to resolve, so no hold.
    public var isInstant: Bool
}

extension Cue {
    public func timing(defaults: ShowSettings) -> CueTiming {
        switch content {
        case .title(let c):
            let s = defaults.resolved(c.overrides)
            return CueTiming(clockMs: s.clockMs, holdTicks: s.holdTicks, isInstant: false)
        case .anagram(let c):
            let s = defaults.resolved(c.overrides)
            return CueTiming(clockMs: s.clockMs, holdTicks: s.holdTicks, isInstant: false)
        case .image(let c):
            let s = defaults.resolved(c.overrides)
            return CueTiming(clockMs: s.clockMs, holdTicks: s.holdTicks, isInstant: false)
        case .morph(let c):
            let s = defaults.resolved(c.overrides)
            return CueTiming(clockMs: s.clockMs, holdTicks: s.holdTicks, isInstant: false)
        case .map(let c):
            let s = defaults.resolved(c.overrides)
            return CueTiming(clockMs: s.clockMs, holdTicks: s.holdTicks, isInstant: false)
        case .layered(let c):
            let s = defaults.resolved(c.overrides)
            return CueTiming(clockMs: s.clockMs, holdTicks: s.holdTicks, isInstant: false)
        case .video, .blank:
            // A video plays on its own clock from GO, and a blank is instant.
            return CueTiming(clockMs: defaults.clockMs, holdTicks: 0, isInstant: true)
        }
    }
}

/// The ranges the sliders allow. Values from a file are clamped to them.
public enum SettingRange {
    public static let clockMs = 18...110
    public static let waveTicks = 0...10
    public static let holdTicks = 0...80
    /// Longer than a hold: working is read, not glanced at.
    public static let pauseTicks = 0...160
    public static let textScale = 40...130
    public static let gridColumns = 4...28
    public static let flipMs = 150...1200
    public static let morphMs = 500...15000
    public static let mapZoom = 1...8
    public static let trailSeconds = 0...30
    public static let fadeMs = 100...3000
    public static let layerMs = 200...5000
    public static let baseLevel = 0...100
    public static let contextLevel = 0...100
    public static let contextTicks = 0...80
    public static let cameraMs = 300...5000
    public static let geometrySize = 20...100
    public static let geometryOffset = -40...40
}

extension ShowSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case clockMs, waveTicks, holdTicks, histogram, sceneLine, letters, bars, gridColumns, flipMs, order
        case reveal, advance, pauseTicks, anagramFont, morphMs, mapCamera, mapZoom, trailSeconds, transition, fadeMs, textScale, geometry, projector
        case layerMs, baseLevel, layeredContext, contextLevel, contextTicks, layeredEntrance, layeredCamera, cameraMs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ShowSettings()
        func int(_ key: CodingKeys, _ fallback: Int, _ range: ClosedRange<Int>) throws -> Int {
            range.clamp(try c.decodeIfPresent(Int.self, forKey: key) ?? fallback)
        }
        clockMs = try int(.clockMs, d.clockMs, SettingRange.clockMs)
        waveTicks = try int(.waveTicks, d.waveTicks, SettingRange.waveTicks)
        holdTicks = try int(.holdTicks, d.holdTicks, SettingRange.holdTicks)
        histogram = try c.decodeIfPresent(Bool.self, forKey: .histogram) ?? d.histogram
        sceneLine = try c.decodeIfPresent(Bool.self, forKey: .sceneLine) ?? d.sceneLine
        letters = try c.decodeIfPresent(TitleLetters.self, forKey: .letters) ?? d.letters
        bars = try c.decodeIfPresent(TitleBars.self, forKey: .bars) ?? d.bars
        gridColumns = try int(.gridColumns, d.gridColumns, SettingRange.gridColumns)
        flipMs = try int(.flipMs, d.flipMs, SettingRange.flipMs)
        order = try c.decodeIfPresent(TileOrder.self, forKey: .order) ?? d.order
        reveal = try c.decodeIfPresent(TileReveal.self, forKey: .reveal) ?? d.reveal
        advance = try c.decodeIfPresent(AnagramAdvance.self, forKey: .advance) ?? d.advance
        pauseTicks = try int(.pauseTicks, d.pauseTicks, SettingRange.pauseTicks)
        anagramFont = try c.decodeIfPresent(String.self, forKey: .anagramFont) ?? d.anagramFont
        morphMs = try int(.morphMs, d.morphMs, SettingRange.morphMs)
        mapCamera = try c.decodeIfPresent(MapCamera.self, forKey: .mapCamera) ?? d.mapCamera
        mapZoom = try int(.mapZoom, d.mapZoom, SettingRange.mapZoom)
        trailSeconds = try int(.trailSeconds, d.trailSeconds, SettingRange.trailSeconds)
        layerMs = try int(.layerMs, d.layerMs, SettingRange.layerMs)
        baseLevel = try int(.baseLevel, d.baseLevel, SettingRange.baseLevel)
        layeredContext = try c.decodeIfPresent(LayerContext.self, forKey: .layeredContext) ?? d.layeredContext
        contextLevel = try int(.contextLevel, d.contextLevel, SettingRange.contextLevel)
        contextTicks = try int(.contextTicks, d.contextTicks, SettingRange.contextTicks)
        layeredEntrance = try c.decodeIfPresent(LayerEntrance.self, forKey: .layeredEntrance) ?? d.layeredEntrance
        layeredCamera = try c.decodeIfPresent(LayeredCamera.self, forKey: .layeredCamera) ?? d.layeredCamera
        cameraMs = try int(.cameraMs, d.cameraMs, SettingRange.cameraMs)
        transition = try c.decodeIfPresent(TransitionStyle.self, forKey: .transition) ?? d.transition
        fadeMs = try int(.fadeMs, d.fadeMs, SettingRange.fadeMs)
        textScale = try int(.textScale, d.textScale, SettingRange.textScale)
        geometry = try c.decodeIfPresent(Geometry.self, forKey: .geometry) ?? d.geometry
        projector = try c.decodeIfPresent(DisplayIdentity.self, forKey: .projector)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clockMs, forKey: .clockMs)
        try c.encode(waveTicks, forKey: .waveTicks)
        try c.encode(holdTicks, forKey: .holdTicks)
        try c.encode(histogram, forKey: .histogram)
        try c.encode(sceneLine, forKey: .sceneLine)
        try c.encode(letters, forKey: .letters)
        try c.encode(bars, forKey: .bars)
        try c.encode(gridColumns, forKey: .gridColumns)
        try c.encode(flipMs, forKey: .flipMs)
        try c.encode(order, forKey: .order)
        try c.encode(reveal, forKey: .reveal)
        try c.encode(advance, forKey: .advance)
        try c.encode(pauseTicks, forKey: .pauseTicks)
        try c.encode(anagramFont, forKey: .anagramFont)
        try c.encode(morphMs, forKey: .morphMs)
        // Only when changed, so a show without maps reads as it did.
        let d = ShowSettings()
        if mapCamera != d.mapCamera { try c.encode(mapCamera, forKey: .mapCamera) }
        if mapZoom != d.mapZoom { try c.encode(mapZoom, forKey: .mapZoom) }
        if trailSeconds != d.trailSeconds { try c.encode(trailSeconds, forKey: .trailSeconds) }
        if layerMs != d.layerMs { try c.encode(layerMs, forKey: .layerMs) }
        if baseLevel != d.baseLevel { try c.encode(baseLevel, forKey: .baseLevel) }
        if layeredContext != d.layeredContext { try c.encode(layeredContext, forKey: .layeredContext) }
        if contextLevel != d.contextLevel { try c.encode(contextLevel, forKey: .contextLevel) }
        if contextTicks != d.contextTicks { try c.encode(contextTicks, forKey: .contextTicks) }
        if layeredEntrance != d.layeredEntrance { try c.encode(layeredEntrance, forKey: .layeredEntrance) }
        if layeredCamera != d.layeredCamera { try c.encode(layeredCamera, forKey: .layeredCamera) }
        if cameraMs != d.cameraMs { try c.encode(cameraMs, forKey: .cameraMs) }
        try c.encode(transition, forKey: .transition)
        try c.encode(fadeMs, forKey: .fadeMs)
        try c.encode(textScale, forKey: .textScale)
        try c.encode(geometry, forKey: .geometry)
        try c.encodeIfPresent(projector, forKey: .projector)
    }
}
