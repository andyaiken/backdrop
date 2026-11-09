
/// A value of one setting.
public enum SettingValue: Equatable, Sendable {
    case number(Int)
    case flag(Bool)
    case order(TileOrder)
    case reveal(TileReveal)
    case letters(TitleLetters)
    case bars(TitleBars)
    /// A font family's name; empty for the stage's own type.
    case font(String)
    case style(TransitionStyle)
    case advance(AnagramAdvance)
    case camera(MapCamera)
    case context(LayerContext)
    case entrance(LayerEntrance)
    case push(LayeredCamera)
    case edge(WipeEdge)
}

/// Every setting a cue holds. One definition serves the cue editor's panels
/// and the printed sheet: its range and step, how it reads, and where it
/// lives in the model.
public enum SettingKey: String, CaseIterable, Sendable {
    case clock, wave, hold, advance, pause, textScale, histogram, sceneLine, letters, bars, grid, flip, order, reveal, font, morphTime, camera, zoom, trail
    case layerTime, baseLevel, context, strength, length, entrance, push, move
    case transition, fade, wipeFrom

    /// What a title cue has.
    public static let title: [SettingKey] = [.clock, .wave, .hold, .histogram, .sceneLine, .letters, .bars]
    /// What an anagram cue has.
    public static let anagram: [SettingKey] = [.clock, .wave, .hold, .advance, .pause, .font]
    /// What a morph cue has: no wave.
    public static let morph: [SettingKey] = [.clock, .hold, .advance, .pause, .morphTime]
    /// What a map cue has: no wave.
    public static let map: [SettingKey] = [.clock, .hold, .advance, .pause, .camera, .zoom, .trail]
    /// What a layered cue has: no wave. Its zoom is the
    /// map's key, worded for both.
    public static let layered: [SettingKey] = [
        .clock, .hold, .advance, .pause, .layerTime, .baseLevel, .context, .strength, .length, .entrance, .push, .zoom, .move,
    ]
    /// What a keypad cue has: the pause is the time between key presses.
    public static let keypad: [SettingKey] = [.clock, .hold, .pause]
    /// What an image cue has.
    public static let image: [SettingKey] = [.clock, .wave, .hold, .grid, .flip, .order, .reveal]
    /// The transition into a cue, which every cue has.
    public static let transitions: [SettingKey] = [.transition, .fade, .wipeFrom]
    /// The cue panels, in their groups.
    public static let groups: [(name: String, keys: [SettingKey])] = [
        // Advance and Pause belong to every cue that runs in steps, anagrams
        // and morphs alike.
        ("Timing", [.clock, .wave, .hold, .advance, .pause]),
        ("Decryption cues", [.histogram, .sceneLine, .letters, .bars]),
        ("Image cues", [.grid, .flip, .order, .reveal]),
        ("Anagram cues", [.font]),
        ("Morph cues", [.morphTime]),
        ("Map cues", [.camera, .zoom, .trail]),
        ("Layered image cues", [.layerTime, .baseLevel, .context, .strength, .length, .entrance, .push, .move]),
        ("Transitions", transitions),
    ]

    public var label: String {
        switch self {
        case .clock: "Clock"
        case .wave: "Wave"
        case .hold: "Hold"
        case .textScale: "Text size"
        case .histogram: "Histogram"
        case .sceneLine: "Subtext"
        case .letters: "Letters"
        case .bars: "Bars"
        case .grid: "Grid"
        case .flip: "Flip"
        case .order: "Order"
        case .reveal: "Reveal"
        case .advance: "Advance"
        case .pause: "Pause"
        case .font: "Font"
        case .morphTime: "Morph"
        case .camera: "View"
        case .zoom: "Zoom"
        case .trail: "Trail"
        case .layerTime: "Layer"
        case .baseLevel: "Base picture"
        case .context: "Others while it arrives"
        case .strength: "Strength"
        case .length: "Lasts"
        case .entrance: "Arriving layer"
        case .push: "Frame"
        case .move: "Frame move"
        case .transition: "Transition"
        case .fade: "Fade"
        case .wipeFrom: "Wipe from"
        }
    }

    /// What the setting does, in a sentence or two, for the panels to show
    /// on hover.
    public var help: String {
        switch self {
        case .clock: "How long each step of the cue takes. Every other timing is counted in these steps, so a shorter clock runs the whole cue faster."
        case .wave: "How many steps apart neighbouring letters, or diagonals of tiles, start to move. None moves them all together."
        case .hold: "How many steps the cue shows its opening state, the ciphertext, the first phrase or the colour blocks, before it starts to resolve."
        case .textScale: "The size of decryption and anagram text, as a share of the largest that fits."
        case .histogram: "The letter-frequency bars and readouts beneath the text."
        case .sceneLine: "The smaller line of text beneath the main one."
        case .bars: "What the histogram counts: single letters, or the commonest pairs of letters, which tell more on a long text."
        case .advance: "Whether an anagram cue moves on through its working and from one anagram to the next by itself, a pause apart, or waits for GO: before each anagram, or before every step. A morph cue of several pictures, a map cue's dot, or a layered image cue's layers move on by themselves, or wait for GO before each stage, stop or step on either GO choice. GO carries the cue on rather than firing the next one."
        case .pause: "How many steps of the clock an anagram rests on each step of its working, and once solved, before the next moves; a morph on each picture before it becomes the next; a map's dot at each stop; and a layered image cue between steps when it moves on by itself; and a keypad between key presses."
        case .morphTime: "How long each picture takes to become the next, after the hold. A stage can have its own, set in the Cue tab."
        case .camera: "Whether a map follows its dot, the dot fixed at the middle and the map sliding under it, or holds still, framed round the whole route, with the dot moving across it."
        case .zoom: "Following the dot, how many stage widths across a map is drawn; holding still, the closest the frame comes. The map's picture should be about this many times the stage's width in pixels, or it softens. For a layered image cue, the closest its frame comes to a part; the layers should be about this many times the stage's width in pixels, and the cue holds that much more in memory."
        case .trail: "How long the red trail behind a map's dot lasts before it fades away. None leaves no trail."
        case .font: "The typeface an anagram is set in. Each letter keeps its own shape as it travels, so a printed hand suits; a joined-up script loses its joins."
        case .letters: "How each letter finds its way home: cycling through random glyphs and rolling back into place, or spinning on a dial, like a cryptex's, and settling."
        case .grid: "How many tiles across the picture is cut into. In quarters, how fine it gets: more tiles, more times a piece splits in four."
        case .flip: "How long each tile takes to show its part of the picture: to turn over, or to sharpen. In quarters, how long the finished picture takes to come up over the pieces."
        case .order: "Which tile goes next: in a wave from the top left, in a random order, or out along a golden spiral, square by Fibonacci square. Quarters, for a reveal that sharpens, has no tiles: the picture is one block, and a piece picked at random splits in four, again and again."
        case .reveal: "How the picture arrives: just there; starting as one flat average colour and sharpening, tile by tile or in quarters, through finer and finer blocks; or starting black with each tile flipping over to its part of the picture. Quarters with a flip takes a random order."
        case .layerTime: "How long a layer takes to arrive. A layer can have its own, set in the Cue tab. A layer taken off again goes in half the time."
        case .baseLevel: "How far up the whole picture sits under the layers, as a percentage. Faint lets the audience read the composition from the first second; none starts on black."
        case .context: "What happens to the layers already standing while a new one arrives: nothing, dimmed, drained of colour, or darkened round the new part. A layer can have its own, set in the Cue tab."
        case .strength: "How far the treatment of the layers already standing goes, as a percentage."
        case .length: "How long that treatment lasts, in steps of the clock, before everything comes back."
        case .entrance: "What the arriving layer does: simply fades up, has its edge drawn as a brass line, settles in slightly magnified, or blooms past its level and back."
        case .push: "What the frame does as layers arrive: holds still on the whole picture, pulls back out and in on each new part, or travels straight from one part to the next. Every move happens on a GO."
        case .move: "How long a move of the frame takes."
        case .transition: "How the stage changes to this cue: a fade through black, a crossfade from the cue before, a wipe across it from one side or corner, or a snap."
        case .fade: "How long each half of a fade takes: out, then in. A crossfade or a wipe takes this long in all."
        case .wipeFrom: "The side or corner of the stage a wipe starts from. The new cue is uncovered from there, and the old picture wiped off ahead of it."
        }
    }

    /// How long a hold lasts, at the clock it runs with. Nil for no hold.
    public static func holdLength(holdTicks: Int, clockMs: Int) -> String? {
        holdTicks == 0 ? nil : fixedDecimal(Double(holdTicks * clockMs) / 1000, digits: 1) + " s"
    }

    /// How the stage's own type reads where a font is named.
    public static let stageFont = "SF Mono"

    /// Clock, wave and hold together, for the panels to show beside them.
    public static let timingExplanation = "Timing is counted in steps of the clock. Clock is how long a step takes; hold is how many steps a cue shows its ciphertext, first phrase or colour blocks before it starts to resolve; wave is how many steps apart neighbouring letters, or diagonals of tiles, start."

    public enum Control: Equatable, Sendable {
        case slider(ClosedRange<Int>, step: Int)
        case toggle
        case choice([String])
        /// One of the Mac's font families, or the stage's own type.
        case font
    }

    /// The slider ranges and steps.
    public var control: Control {
        switch self {
        case .clock: .slider(SettingRange.clockMs, step: 2)
        case .wave: .slider(SettingRange.waveTicks, step: 1)
        case .hold: .slider(SettingRange.holdTicks, step: 2)
        case .textScale: .slider(SettingRange.textScale, step: 2)
        case .grid: .slider(SettingRange.gridColumns, step: 1)
        case .flip: .slider(SettingRange.flipMs, step: 30)
        case .histogram, .sceneLine: .toggle
        case .order: .choice(["Wave", "Random", "Golden spiral", "Quarters"])
        case .reveal: .choice(["Just show it", "Sharpen from one colour", "Flip from black"])
        case .advance: .choice(["By itself", "Each anagram on GO", "Each step on GO"])
        case .pause: .slider(SettingRange.pauseTicks, step: 2)
        case .letters: .choice(["Cycling", "Dials"])
        case .bars: .choice(["Letters", "Digraphs"])
        case .font: .font
        case .morphTime: .slider(SettingRange.morphMs, step: 100)
        case .camera: .choice(["Follows the dot", "Holds still"])
        case .zoom: .slider(SettingRange.mapZoom, step: 1)
        case .trail: .slider(SettingRange.trailSeconds, step: 1)
        case .layerTime: .slider(SettingRange.layerMs, step: 100)
        case .baseLevel: .slider(SettingRange.baseLevel, step: 5)
        case .context: .choice(["None", "Dim", "Desaturate", "Spotlight"])
        case .strength: .slider(SettingRange.contextLevel, step: 5)
        case .length: .slider(SettingRange.contextTicks, step: 2)
        case .entrance: .choice(["Fade", "Outline", "Settle", "Bloom"])
        case .push: .choice(["Holds still", "Pulls back between parts", "Travels part to part"])
        case .move: .slider(SettingRange.cameraMs, step: 100)
        case .transition: .choice(["Fade through black", "Snap", "Crossfade", "Wipe"])
        case .wipeFrom: .choice(["Left", "Right", "Top", "Bottom", "Top left", "Top right", "Bottom left", "Bottom right"])
        case .fade: .slider(SettingRange.fadeMs, step: 100)
        }
    }

    /// For a choice, what its menu offers on a kind of cue. A morph's Advance
    /// has two choices: Each stage on GO stands for both of an anagram's GO
    /// choices.
    public func choices(for kind: Cue.Kind? = nil) -> [(label: String, value: SettingValue)] {
        if self == .advance, kind == .morph {
            return [("By itself", .advance(.byItself)), ("Each stage on GO", .advance(.eachStep))]
        }
        if self == .advance, kind == .map {
            return [("By itself", .advance(.byItself)), ("Each stop on GO", .advance(.eachStep))]
        }
        if self == .advance, kind == .layered {
            return [("By itself", .advance(.byItself)), ("Each step on GO", .advance(.eachStep))]
        }
        guard case .choice(let options) = control else { return [] }
        return options.indices.compactMap { i in choice(at: i).map { (options[i], $0) } }
    }

    /// Where a value sits in the menu `choices(for:)` gives.
    public func choiceIndex(of value: SettingValue, for kind: Cue.Kind?) -> Int? {
        if self == .advance, kind == .morph || kind == .map || kind == .layered, case .advance(let a) = value { return a == .byItself ? 0 : 1 }
        return choiceIndex(of: value)
    }

    /// How a value reads beside its control, on a kind of cue.
    public func format(_ value: SettingValue, for kind: Cue.Kind?) -> String {
        if self == .advance, kind == .morph, case .advance(let a) = value { return a == .byItself ? "by itself" : "each stage on GO" }
        if self == .advance, kind == .map, case .advance(let a) = value { return a == .byItself ? "by itself" : "each stop on GO" }
        if self == .advance, kind == .layered, case .advance(let a) = value { return a == .byItself ? "by itself" : "each step on GO" }
        return format(value)
    }

    /// For a choice, the value at each place in its menu.
    public func choice(at index: Int) -> SettingValue? {
        switch self {
        case .order: [SettingValue.order(.diagonal), .order(.random), .order(.spiral), .order(.quarters)][safe: index]
        case .reveal: [SettingValue.reveal(.show), .reveal(.sharpen), .reveal(.flip)][safe: index]
        case .advance: [SettingValue.advance(.byItself), .advance(.eachAnagram), .advance(.eachStep)][safe: index]
        case .camera: [SettingValue.camera(.follow), .camera(.still)][safe: index]
        case .letters: [SettingValue.letters(.cycle), .letters(.dials)][safe: index]
        case .bars: [SettingValue.bars(.letters), .bars(.digraphs)][safe: index]
        case .context: [SettingValue.context(.none), .context(.dim), .context(.desaturate), .context(.spotlight)][safe: index]
        case .entrance: [SettingValue.entrance(.fade), .entrance(.outline), .entrance(.settle), .entrance(.bloom)][safe: index]
        case .push: [SettingValue.push(.still), .push(.push), .push(.travel)][safe: index]
        case .transition: [SettingValue.style(.fade), .style(.snap), .style(.crossfade), .style(.wipe)][safe: index]
        case .wipeFrom: [SettingValue.edge(.left), .edge(.right), .edge(.top), .edge(.bottom),
                         .edge(.topLeft), .edge(.topRight), .edge(.bottomLeft), .edge(.bottomRight)][safe: index]
        default: nil
        }
    }

    /// For a choice, where a value sits in its menu.
    public func choiceIndex(of value: SettingValue) -> Int? {
        guard case .choice(let options) = control else { return nil }
        return options.indices.first { choice(at: $0) == value }
    }

    /// How a value reads beside its control.
    public func format(_ value: SettingValue) -> String {
        switch (self, value) {
        case (.clock, .number(let n)), (.flip, .number(let n)): "\(n) ms"
        case (.wave, .number(let n)), (.hold, .number(let n)), (.pause, .number(let n)): n == 0 ? "none" : "\(n)"
        case (.textScale, .number(let n)): "\(n)%"
        case (.zoom, .number(let n)): "\(n)\u{00D7}"
        case (.baseLevel, .number(let n)): n == 0 ? "black" : "\(n)%"
        case (.strength, .number(let n)): "\(n)%"
        case (.length, .number(let n)): n == 0 ? "none" : "\(n)"
        case (.layerTime, .number(let n)), (.move, .number(let n)): fixedDecimal(Double(n) / 1000, digits: 1) + " s"
        case (.trail, .number(let n)): n == 0 ? "none" : "\(n) s"
        case (.fade, .number(let n)), (.morphTime, .number(let n)): fixedDecimal(Double(n) / 1000, digits: 1) + " s"
        case (.grid, .number(let n)): "\(n) wide"
        case (_, .flag(let on)): on ? "on" : "off"
        case (_, .order(.diagonal)): "wave"
        case (_, .order(.random)): "random"
        case (_, .order(.spiral)): "golden spiral"
        case (_, .order(.quarters)): "quarters"
        case (_, .reveal(let reveal)):
            switch reveal {
            case .show: "just show it"
            case .sharpen: "sharpen from one colour"
            case .flip: "flip from black"
            }
        case (_, .letters(let letters)): letters == .cycle ? "cycling" : "dials"
        case (_, .bars(let bars)): bars == .letters ? "letters" : "digraphs"
        case (_, .font(let family)): family.isEmpty ? Self.stageFont : family
        case (_, .style(let style)):
            switch style {
            case .fade: "fade through black"
            case .snap: "snap"
            case .crossfade: "crossfade"
            case .wipe: "wipe"
            }
        case (_, .edge(let edge)):
            switch edge {
            case .left: "left"
            case .right: "right"
            case .top: "top"
            case .bottom: "bottom"
            case .topLeft: "top left"
            case .topRight: "top right"
            case .bottomLeft: "bottom left"
            case .bottomRight: "bottom right"
            }
        case (_, .advance(.byItself)): "by itself"
        case (_, .advance(.eachAnagram)): "each anagram on GO"
        case (_, .advance(.eachStep)): "each step on GO"
        case (_, .context(let c)):
            switch c {
            case .none: "none"
            case .dim: "dim"
            case .desaturate: "desaturate"
            case .spotlight: "spotlight"
            }
        case (_, .entrance(let e)): e.rawValue
        case (_, .push(.still)): "holds still"
        case (_, .push(.push)): "pulls back between parts"
        case (_, .push(.travel)): "travels part to part"
        case (_, .camera(.follow)): "follows the dot"
        case (_, .camera(.still)): "holds still"
        case (_, .number(let n)): "\(n)"
        }
    }

    /// The nearest allowed value: inside the range and on a step.
    public func snapped(_ value: SettingValue) -> SettingValue {
        guard case .number(let n) = value, case .slider(let range, let step) = control else { return value }
        let stepped = range.lowerBound + Int((Double(n - range.lowerBound) / Double(step)).rounded()) * step
        return .number(range.clamp(stepped))
    }

    // MARK: Cue values

    /// Whether a cue of this kind has this setting.
    public func applies(to kind: Cue.Kind) -> Bool {
        if Self.transitions.contains(self) { return true }
        return switch kind {
        case .title: Self.title.contains(self)
        case .anagram: Self.anagram.contains(self)
        case .morph: Self.morph.contains(self)
        case .map: Self.map.contains(self)
        case .image: Self.image.contains(self)
        case .layered: Self.layered.contains(self)
        case .keypad: Self.keypad.contains(self)
        case .video, .blank, .text, .feed: false
        }
    }

    /// The cue's value for this setting, or nil where its kind doesn't have
    /// it.
    public func value(in cue: Cue) -> SettingValue? {
        // The transition in belongs to the cue, not to its kind's content.
        switch self {
        case .transition: return .style(cue.transition.style)
        case .fade: return .number(cue.transition.fadeMs)
        case .wipeFrom: return .edge(cue.transition.wipeFrom)
        default: break
        }
        switch cue.content {
        case .title(let c):
            let o = c.settings
            switch self {
            case .clock: return .number(o.clockMs)
            case .wave: return .number(o.waveTicks)
            case .hold: return .number(o.holdTicks)
            case .histogram: return .flag(o.histogram)
            case .sceneLine: return .flag(o.sceneLine)
            case .letters: return .letters(o.letters)
            case .bars: return .bars(o.bars)
            default: return nil
            }
        case .anagram(let c):
            let o = c.settings
            switch self {
            case .clock: return .number(o.clockMs)
            case .wave: return .number(o.waveTicks)
            case .hold: return .number(o.holdTicks)
            case .advance: return .advance(o.advance)
            case .pause: return .number(o.pauseTicks)
            case .font: return .font(o.font)
            default: return nil
            }
        case .morph(let c):
            let o = c.settings
            switch self {
            case .clock: return .number(o.clockMs)
            case .hold: return .number(o.holdTicks)
            case .advance: return .advance(o.advance)
            case .pause: return .number(o.pauseTicks)
            case .morphTime: return .number(o.morphMs)
            default: return nil
            }
        case .map(let c):
            let o = c.settings
            switch self {
            case .clock: return .number(o.clockMs)
            case .hold: return .number(o.holdTicks)
            case .advance: return .advance(o.advance)
            case .pause: return .number(o.pauseTicks)
            case .camera: return .camera(o.camera)
            case .zoom: return .number(o.zoom)
            case .trail: return .number(o.trailSeconds)
            default: return nil
            }
        case .image(let c):
            let o = c.settings
            switch self {
            case .clock: return .number(o.clockMs)
            case .wave: return .number(o.waveTicks)
            case .hold: return .number(o.holdTicks)
            case .grid: return .number(o.gridColumns)
            case .flip: return .number(o.flipMs)
            case .order: return .order(o.order)
            case .reveal: return .reveal(o.reveal)
            default: return nil
            }
        case .layered(let c):
            let o = c.settings
            switch self {
            case .clock: return .number(o.clockMs)
            case .hold: return .number(o.holdTicks)
            case .advance: return .advance(o.advance)
            case .pause: return .number(o.pauseTicks)
            case .layerTime: return .number(o.layerMs)
            case .baseLevel: return .number(o.baseLevel)
            case .context: return .context(o.context)
            case .strength: return .number(o.contextLevel)
            case .length: return .number(o.contextTicks)
            case .entrance: return .entrance(o.entrance)
            case .push: return .push(o.camera)
            case .zoom: return .number(o.zoom)
            case .move: return .number(o.cameraMs)
            default: return nil
            }
        case .keypad(let c):
            let o = c.settings
            switch self {
            case .clock: return .number(o.clockMs)
            case .hold: return .number(o.holdTicks)
            case .pause: return .number(o.pauseTicks)
            default: return nil
            }
        case .video, .blank, .text, .feed:
            return nil
        }
    }

    /// Sets the cue's value, snapped to the setting's range and step. Does
    /// nothing for settings the cue's kind doesn't have, or a value of the
    /// wrong type.
    public func set(_ value: SettingValue, in cue: inout Cue) {
        let value = snapped(value)
        switch (self, value) {
        case (.transition, .style(let style)):
            cue.transition.style = style
            return
        case (.fade, .number(let n)):
            cue.transition.fadeMs = n
            return
        case (.wipeFrom, .edge(let edge)):
            cue.transition.wipeFrom = edge
            return
        default: break
        }
        switch cue.content {
        case .title(var c):
            switch (self, value) {
            case (.clock, .number(let n)): c.settings.clockMs = n
            case (.wave, .number(let n)): c.settings.waveTicks = n
            case (.hold, .number(let n)): c.settings.holdTicks = n
            case (.histogram, .flag(let on)): c.settings.histogram = on
            case (.sceneLine, .flag(let on)): c.settings.sceneLine = on
            case (.letters, .letters(let letters)): c.settings.letters = letters
            case (.bars, .bars(let bars)): c.settings.bars = bars
            default: return
            }
            cue.content = .title(c)
        case .anagram(var c):
            switch (self, value) {
            case (.clock, .number(let n)): c.settings.clockMs = n
            case (.wave, .number(let n)): c.settings.waveTicks = n
            case (.hold, .number(let n)): c.settings.holdTicks = n
            case (.advance, .advance(let advance)): c.settings.advance = advance
            case (.pause, .number(let n)): c.settings.pauseTicks = n
            case (.font, .font(let family)): c.settings.font = family
            default: return
            }
            cue.content = .anagram(c)
        case .morph(var c):
            switch (self, value) {
            case (.clock, .number(let n)): c.settings.clockMs = n
            case (.hold, .number(let n)): c.settings.holdTicks = n
            case (.advance, .advance(let advance)): c.settings.advance = advance
            case (.pause, .number(let n)): c.settings.pauseTicks = n
            case (.morphTime, .number(let n)): c.settings.morphMs = n
            default: return
            }
            cue.content = .morph(c)
        case .map(var c):
            switch (self, value) {
            case (.clock, .number(let n)): c.settings.clockMs = n
            case (.hold, .number(let n)): c.settings.holdTicks = n
            case (.advance, .advance(let advance)): c.settings.advance = advance
            case (.pause, .number(let n)): c.settings.pauseTicks = n
            case (.camera, .camera(let camera)): c.settings.camera = camera
            case (.zoom, .number(let n)): c.settings.zoom = n
            case (.trail, .number(let n)): c.settings.trailSeconds = n
            default: return
            }
            cue.content = .map(c)
        case .image(var c):
            switch (self, value) {
            case (.clock, .number(let n)): c.settings.clockMs = n
            case (.wave, .number(let n)): c.settings.waveTicks = n
            case (.hold, .number(let n)): c.settings.holdTicks = n
            case (.grid, .number(let n)): c.settings.gridColumns = n
            case (.flip, .number(let n)): c.settings.flipMs = n
            case (.order, .order(let order)): c.settings.order = order
            case (.reveal, .reveal(let reveal)): c.settings.reveal = reveal
            default: return
            }
            cue.content = .image(c)
        case .layered(var c):
            switch (self, value) {
            case (.clock, .number(let n)): c.settings.clockMs = n
            case (.hold, .number(let n)): c.settings.holdTicks = n
            case (.advance, .advance(let advance)): c.settings.advance = advance
            case (.pause, .number(let n)): c.settings.pauseTicks = n
            case (.layerTime, .number(let n)): c.settings.layerMs = n
            case (.baseLevel, .number(let n)): c.settings.baseLevel = n
            case (.context, .context(let context)): c.settings.context = context
            case (.strength, .number(let n)): c.settings.contextLevel = n
            case (.length, .number(let n)): c.settings.contextTicks = n
            case (.entrance, .entrance(let entrance)): c.settings.entrance = entrance
            case (.push, .push(let camera)): c.settings.camera = camera
            case (.zoom, .number(let n)): c.settings.zoom = n
            case (.move, .number(let n)): c.settings.cameraMs = n
            default: return
            }
            cue.content = .layered(c)
        case .keypad(var c):
            switch (self, value) {
            case (.clock, .number(let n)): c.settings.clockMs = n
            case (.hold, .number(let n)): c.settings.holdTicks = n
            case (.pause, .number(let n)): c.settings.pauseTicks = n
            default: return
            }
            cue.content = .keypad(c)
        case .video, .blank, .text, .feed:
            return
        }
    }
}
