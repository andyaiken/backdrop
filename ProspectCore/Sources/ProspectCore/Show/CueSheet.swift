import Foundation

/// The printed cue sheet, row by row: drawn from the same model the show
/// runs from, so the sheet can't disagree with what fires.
///
/// Two layouts. The DSM's carries cue points, for transcribing into the
/// prompt book. The operator's carries the settings each cue runs with, for
/// writing down what was dialled in on the rig and restoring it if a show is
/// ever lost.
public struct CueSheet: Equatable, Sendable {
    public enum Layout: String, CaseIterable, Sendable {
        /// Cue points, for the prompt book.
        case dsm
        /// Settings, for the projection operator. No cue points.
        case operatorSettings

        public var name: String {
            switch self {
            case .dsm: "DSM: cue points"
            case .operatorSettings: "Operator: settings"
            }
        }
    }

    public struct Setting: Equatable, Sendable {
        public var name: String
        public var value: String
        /// Set on this cue rather than taken from the show's defaults.
        public var overridden: Bool
    }

    public struct Row: Equatable, Sendable {
        /// As set: an identifier, not a position.
        public var number: String
        /// Title, Image, Video or Blank.
        public var type: String
        /// Fired by the cue before it continuing, not by GO. Printed as AUTO,
        /// so the DSM doesn't call it.
        public var auto: Bool
        /// The main line first: place and city, label and caption, or the
        /// blank's label and colour.
        public var content: [String]
        /// Empty when none is set, so the gap is obvious and gets filled in.
        public var cuePoint: String
        /// What the cue runs with. Empty in the DSM layout.
        public var settings: [Setting]
        /// A GO the cue above waits for partway, counted from 1, on a row of
        /// its own under it in the DSM layout: no number, its content what
        /// the GO brings on, and its cue point left for pencil.
        public var go: Int? = nil
    }

    public let title: String
    public let layout: Layout
    public let rows: [Row]

    /// Whether any value on the sheet is set for its cue, so the key to the
    /// marking is worth printing.
    public var hasOverrides: Bool {
        rows.contains { $0.settings.contains(where: \.overridden) }
    }

    public init(show: Show, title: String, layout: Layout) {
        self.title = title
        self.layout = layout
        rows = show.cues.enumerated().flatMap { i, cue -> [Row] in
            let row = Row(
                number: cue.number,
                type: cue.kind.heading,
                auto: i > 0 && show.cues[i - 1].continueMode.continues,
                content: Self.content(of: cue),
                cuePoint: layout == .dsm ? cue.line.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                settings: layout == .operatorSettings ? Self.settings(of: cue, defaults: show.settings) : []
            )
            // Every GO the DSM calls gets a row, so none is missed in the book.
            guard layout == .dsm else { return [row] }
            let goes = cue.goPoints(defaults: show.settings).enumerated().map { n, point in
                Row(number: "", type: "GO \(n + 1)", auto: false, content: [point.text], cuePoint: point.cuePoint, settings: [], go: n + 1)
            }
            return [row] + goes
        }
    }

    private static func content(of cue: Cue) -> [String] {
        let lines: [String]
        switch cue.content {
        case .title(let c): lines = [c.text, c.sub]
        case .anagram(let c): lines = anagramLines(c)
        case .image(let c): lines = [c.text]
        case .morph(let c): lines = [c.text, c.pictures.map { MorphContent.name(of: $0.src) }.joined(separator: " \u{2192} ")]
        case .map(let c):
            // The stops in turn, a jump marked as one.
            let stops = c.stops.enumerated().map { n, i in
                let stop = c.stop(at: i)
                let name = [stop.place, stop.status].first { !$0.isEmpty } ?? (n == 0 ? "start" : "stop \(n)")
                return n > 0 && stop.arrival == .jump ? "\u{21AF} " + name : name
            }
            lines = [c.text, stops.joined(separator: " \u{2192} ")]
        case .layered(let c):
            // The steps in order, a withdrawal marked.
            lines = [c.text, c.steps.map(\.sheetName).joined(separator: " \u{2192} ")]
        case .video(let c): lines = [c.text, c.sub]
        case .blank(let c): lines = [c.text, c.colour.hex.uppercased()]
        }
        return lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Each anagram's phrase, its working after an ellipsis, and its answer
    /// after an arrow. One the cue doesn't solve is the one line it shows,
    /// saying so. The GOs the cue waits for have rows of their own.
    static func anagramLines(_ c: AnagramContent) -> [String] {
        c.anagrams.flatMap { a -> [String] in
            if a.isSolvedAlready { return [a.steps[0] + " (solved)"] }
            if a.ignored { return [(a.steps.first ?? "") + " (ignored)"] }
            let working = a.working.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { "\u{2026} " + $0 }
            return [a.text] + working + [a.answer.isEmpty ? "" : "\u{2192} " + a.answer]
        }
    }

    private static func settings(of cue: Cue, defaults: ShowSettings) -> [Setting] {
        func file(_ path: String, none: String) -> String { path.isEmpty ? none : (path as NSString).lastPathComponent }
        // Worded as the console words them, from the same definitions.
        func timing(_ keys: [SettingKey]) -> [Setting] {
            keys.map { key in
                let (value, overridden) = key.effective(for: cue, defaults: defaults)
                var reading = key.format(value, for: cue.kind)
                // A hold also in seconds, as the panels show it.
                let t = cue.timing(defaults: defaults)
                if key == .hold, let length = SettingKey.holdLength(holdTicks: t.holdTicks, clockMs: t.clockMs) {
                    reading += " \u{00B7} " + length
                }
                if key == .pause, case .number(let ticks) = value, let length = SettingKey.holdLength(holdTicks: ticks, clockMs: t.clockMs) {
                    reading += " \u{00B7} " + length
                }
                return Setting(name: key.label, value: reading, overridden: overridden)
            }
        }

        // Every cue's transition in, with its fade time only where it fades.
        let fades = cue.transitionIn(defaults: defaults).hasLength
        let transition = timing(fades ? SettingKey.transitions : [.transition])

        // When the show moves on from here by itself.
        let continues = cue.continueMode.continues
            ? [Setting(name: "Continue", value: cue.continueMode.summary, overridden: false)] : []

        return own(cue, file: file, timing: timing) + transition + continues
    }

    private static func own(_ cue: Cue, file: (String, String) -> String, timing: ([SettingKey]) -> [Setting]) -> [Setting] {
        switch cue.content {
        case .title:
            return timing(SettingKey.title)
        case .anagram:
            return timing(SettingKey.anagram)
        case .image(let c):
            return timing(SettingKey.image) + [Setting(name: "Picture", value: file(c.src, "none"), overridden: false)]
        case .morph(let c):
            guard !c.pictures.isEmpty else { return timing(SettingKey.morph) + [Setting(name: "Pictures", value: "none", overridden: false)] }
            // Each picture, and how the stage into it goes: its points, and
            // its own morph time if it has one.
            let pictures = c.pictures.enumerated().map { i, picture in
                let points = i == 0 ? [] : [picture.pairs.isEmpty ? "a dissolve" : "\(picture.pairs.count) point\(picture.pairs.count == 1 ? "" : "s")"]
                let time = picture.morphMs.map { [SettingKey.morphTime.format(.number($0))] } ?? []
                return Setting(name: "Picture \(i + 1)", value: ([file(picture.src, "none")] + points + time).joined(separator: " \u{00B7} "),
                               overridden: picture.morphMs != nil)
            }
            return timing(SettingKey.morph) + pictures
        case .map(let c):
            let stops = c.stops.count - 1, jumps = c.stops.dropFirst().filter { c.stop(at: $0).arrival == .jump }.count
            let route = stops < 1 ? "no stops" : "\(stops) stop\(stops == 1 ? "" : "s")" + (jumps > 0 ? ", \(jumps) by a jump" : "")
            return timing(SettingKey.map) + [
                Setting(name: "Map", value: file(c.src, "none"), overridden: false),
                Setting(name: "Route", value: route, overridden: false),
            ]
        case .layered(let c):
            // A line per layer, as a morph lists a line per picture.
            let layers = c.layers.enumerated().map { i, layer in
                var parts = [file(layer.src, "none")]
                if let level = layer.level { parts.append("\(level)%") }
                if layer.blend != .normal { parts.append(layer.blend.rawValue) }
                if layer.withPrevious { parts.append("with the one before") }
                switch layer.life {
                case .stays: break
                case .untilNextLayer: parts.append("goes as the next arrives")
                case .untilNextGo: parts.append("goes on its own GO")
                }
                if let fade = layer.fadeMs { parts.append(SettingKey.layerTime.format(.number(fade))) }
                return Setting(name: "Layer \(i + 1)", value: ([layer.displayName] + parts).joined(separator: " \u{00B7} "),
                               overridden: layer.fadeMs != nil || layer.level != nil)
            }
            return timing(SettingKey.layered) + [Setting(name: "Base", value: file(c.base, "black"), overridden: false)] + layers
        case .video(let c):
            let end = switch c.atEnd {
            case .hold: "hold the last frame"
            case .black: "cut to black"
            case .loop: "loop"
            }
            return [
                Setting(name: "At the end", value: end, overridden: false),
                Setting(name: "Clip", value: file(c.src, "none"), overridden: false),
            ]
        case .blank(let c):
            return [Setting(name: "Colour", value: c.colour.hex.uppercased(), overridden: false)]
        }
    }
}
