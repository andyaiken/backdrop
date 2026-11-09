import Foundation

/// One press on the keypad.
public enum KeypadKey: Equatable, Sendable {
    case digit(Character)
    case delete
    /// The OK key, pressed to validate.
    case ok
}

/// How a keypad entry is judged.
public enum KeypadVerdict: Equatable, Sendable {
    case good, bad
}

/// One stage of a keypad cue's script: the keys pressed, then perhaps a verdict.
public struct KeypadStage: Equatable, Sendable {
    public var keys: [KeypadKey]
    public var verdict: KeypadVerdict?

    /// Every press the stage makes: its keys, then OK if it gives a verdict.
    public var presses: [KeypadKey] { verdict == nil ? keys : keys + [.ok] }
}

/// A keypad cue: a row of empty boxes and a numpad beneath, keyed in a stage
/// at a time. Each GO runs the next stage. A stage that says GOOD or BAD
/// ends by flashing the boxes green or red.
public struct KeypadContent: Equatable, Sendable {
    /// The cue's name.
    public var text: String
    /// The key presses, a stage to a line. A digit, * or # presses that
    /// key and `<` deletes. A stage containing `GOOD` or `BAD` presses OK after its keys,
    /// then flashes the boxes green or red. For example the lines `1332`,
    /// `<<<<`, `1123` and `GOOD`: enter four digits, delete them, enter four
    /// more, then validate. The first stage runs when the cue fires.
    public var script: String
    public var settings: KeypadSettings

    public init(text: String = "", script: String = "", settings: KeypadSettings = .init()) {
        self.text = text
        self.script = script
        self.settings = settings
    }

    /// A character the keypad has a key for: a digit, * or #.
    public static func isKey(_ c: Character) -> Bool { c == "*" || c == "#" || (c.isASCII && c.isNumber) }

    /// The script in stages. Always at least one.
    public var stages: [KeypadStage] {
        script.trimmingCharacters(in: .whitespacesAndNewlines).split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { raw in
            let stage = String(raw)
            let verdict: KeypadVerdict? = stage.localizedCaseInsensitiveContains("GOOD") ? .good
                : stage.localizedCaseInsensitiveContains("BAD") ? .bad : nil
            let keys = stage.compactMap { c -> KeypadKey? in
                if c == "<" { return .delete }
                return Self.isKey(c) ? .digit(c) : nil
            }
            return KeypadStage(keys: keys, verdict: verdict)
        }
    }

    /// The boxes on stage: as many as the most the script ever holds at once,
    /// or four when it types nothing.
    public var boxCount: Int {
        var held = 0, peak = 0
        for key in stages.flatMap(\.keys) {
            switch key {
            case .digit: held += 1; peak = max(peak, held)
            case .delete: held = max(held - 1, 0)
            case .ok: break
            }
        }
        return peak == 0 ? 4 : min(peak, SettingRange.keypadBoxes.upperBound)
    }

    static func press(_ key: KeypadKey, into entry: inout [Character], limit: Int) {
        switch key {
        case .digit(let c): if entry.count < limit { entry.append(c) }
        case .delete: if !entry.isEmpty { entry.removeLast() }
        case .ok: break
        }
    }

    /// Where the cue waits for GO: before each stage after the first.
    public func goPoints() -> [GoPoint] {
        stages.dropFirst().map { stage in
            var parts = stage.keys.map { key -> String in
                switch key {
                case .digit(let c): String(c)
                case .delete: "\u{232B}"
                case .ok: "OK"
                }
            }.joined()
            if let verdict = stage.verdict { parts += (parts.isEmpty ? "" : " ") + (verdict == .good ? "GOOD" : "BAD") }
            return GoPoint(unit: .stage, text: parts.isEmpty ? "(nothing)" : parts)
        }
    }
}

/// A keypad cue's settings.
public struct KeypadSettings: Codable, Equatable, Sendable {
    public var clockMs: Int
    public var holdTicks: Int
    /// Steps of the clock between one key press and the next.
    public var pauseTicks: Int

    public init(clockMs: Int = 44, holdTicks: Int = 44, pauseTicks: Int = 14) {
        self.clockMs = clockMs
        self.holdTicks = holdTicks
        self.pauseTicks = pauseTicks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = KeypadSettings()
        clockMs = try c.value(.clockMs, d.clockMs, in: SettingRange.clockMs)
        holdTicks = try c.value(.holdTicks, d.holdTicks, in: SettingRange.holdTicks)
        pauseTicks = try c.value(.pauseTicks, d.pauseTicks, in: SettingRange.pauseTicks)
    }
}

/// When each key goes down, and what the boxes hold, for a keypad cue.
public struct KeypadCuePlan: Sendable {
    public let content: KeypadContent
    /// Frames between presses, at least two.
    public let interval: Int
    /// How long a verdict's flash lasts, in frames.
    public static let flashTicks = 30

    public init(_ content: KeypadContent) {
        self.content = content
        interval = max(content.settings.pauseTicks, 2)
    }

    /// The frames each stage takes: its keys, then its flash.
    public var parts: [Int] {
        content.stages.map { $0.presses.count * interval + ($0.verdict == nil ? 0 : Self.flashTicks) }
    }

    /// How the keypad looks on frame `f`.
    public struct State: Equatable, Sendable {
        public var entry: [Character] = []
        /// The key held down now.
        public var pressed: KeypadKey?
        /// The verdict showing, until a later key is pressed.
        public var verdict: KeypadVerdict?
        /// The verdict's colour is on: it blinks while it flashes, then holds.
        public var lit = false
    }

    public func state(at f: Int, timeline: GoTimeline) -> State {
        var state = State()
        for (p, stage) in content.stages.enumerated() {
            guard let start = timeline.start(part: p, offset: 0), f >= start else { break }
            let into = f - start
            let presses = stage.presses
            let keysEnd = presses.count * interval
            let count = min(presses.count, into / interval + 1)
            if !presses.isEmpty {
                state.verdict = nil
                for key in presses.prefix(count) { KeypadContent.press(key, into: &state.entry, limit: content.boxCount) }
                // A key is down for the first half of its slot.
                if into < keysEnd, into % interval < max(interval / 2, 1) { state.pressed = presses[count - 1] }
            }
            if let verdict = stage.verdict, into >= keysEnd {
                state.verdict = verdict
                let flash = into - keysEnd
                // Three blinks, then colour for good.
                state.lit = flash >= Self.flashTicks || (flash / 5) % 2 == 0
            }
        }
        return state
    }
}
