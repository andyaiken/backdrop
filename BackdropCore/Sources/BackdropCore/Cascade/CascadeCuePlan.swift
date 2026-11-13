import Foundation

/// What a cascade cue shows on one frame: the lit glyphs of the rain, and
/// the message's letters that have been left behind so far.
public struct CascadeFrame: Equatable, Sendable {
    /// A glyph of the rain, lit.
    public struct Glyph: Equatable, Sendable {
        public var column: Int
        public var row: Int
        /// Which of `CascadeContent.glyphs`.
        public var glyph: Int
        public var mirrored: Bool
        /// 1 at a streak's head, falling towards nothing at its tail, and
        /// lower again while the rain clears.
        public var level: Double
        /// The bright glyph at the foot of a streak.
        public var head: Bool
    }

    /// A letter of the message, left behind by the streak that passed it.
    public struct Letter: Equatable, Sendable {
        public var column: Int
        public var row: Int
        public var character: Character
        /// How far it has cooled from the white it is left in: 0 is white, 1
        /// is the cue's colour.
        public var cooled: Double
    }

    /// Row by row, from the top left.
    public var glyphs: [Glyph]
    public var letters: [Letter]
    /// The message is all there and the rain has gone.
    public var isSettled: Bool
}

/// When each streak falls, and when the message comes out of the rain, for a
/// cascade cue.
///
/// Nothing is kept from one frame to the next: every streak and every glyph
/// is rolled from the frame number and the column and row, with dice fixed
/// when the plan is made. So any frame can be painted on its own, the same
/// on every surface, a rain that runs all night costs no more on its last
/// frame than its first, and a jump straight to the message needs nothing
/// worked out on the way.
public struct CascadeCuePlan: Sendable {
    public let content: CascadeContent
    /// Glyphs across: as set, or more where a line of the message is longer.
    public let columns: Int
    /// Glyphs down, for the picture's shape.
    public let rows: Int
    /// The message's letters and where each stands.
    public let letters: [Placed]
    /// The frames from the message starting until it has settled.
    public let resolveTicks: Int

    /// A letter of the message on the grid.
    public struct Placed: Equatable, Sendable {
        public var column: Int
        public var row: Int
        public var character: Character
    }

    /// A cell is this many times taller than it is wide.
    public static let cellShape = 1.3
    /// The most glyphs across, however long the message.
    public static let widest = 240
    /// Each column is cut into slots this many frames long, and a streak may
    /// set off once in each.
    static let slotTicks = 12
    /// How long the rain takes to clear once the message starts.
    public static let drainTicks = 30
    /// How long a letter takes to cool from white to the cue's colour.
    public static let coolTicks = 10
    /// The streaks that leave the message set off this many frames apart at
    /// most, so the letters arrive unevenly.
    static let spreadTicks = 24
    /// Frames a glyph takes to fall a row: a streak falls at one of these
    /// speeds, most often the middle one.
    static let slownesses = [1, 2, 2, 3]

    private let dice: Dice
    /// For each column the message stands in, when its streak sets off after
    /// the message starts.
    private let delays: [Int: Int]

    /// - Parameters:
    ///   - aspect: The picture's width over its height.
    ///   - random: Where the dice come from. Tests pass a seeded generator.
    public init(_ content: CascadeContent, aspect: Double, random: inout some UnitRandom) {
        self.content = content
        dice = Dice(seed: UInt64(random.next() * 9_007_199_254_740_992))
        let lines = content.hasMessage ? content.lines : []
        let longest = lines.map(\.count).max() ?? 0
        let columns = min(max(content.settings.columns, longest + 4), Self.widest)
        self.columns = columns
        let shape = aspect.isFinite && aspect > 0 ? aspect : 16.0 / 9
        let rows = max(4, Int((Double(columns) / shape / Self.cellShape).rounded()))
        self.rows = rows

        // A blank row between lines where there is room, none where there
        // isn't, and lines that won't fit at all left off.
        let spacing = lines.count * 2 - 1 <= rows - 2 ? 2 : 1
        let shown = min(lines.count, (rows - 1) / spacing + 1)
        let top = (rows - (shown - 1) * spacing - 1) / 2
        var letters: [Placed] = []
        for (i, line) in lines.prefix(shown).enumerated() {
            let characters = Array(line.prefix(columns))
            let left = (columns - characters.count) / 2
            for (k, character) in characters.enumerated() where !character.isWhitespace {
                letters.append(Placed(column: left + k, row: top + i * spacing, character: character))
            }
        }
        self.letters = letters

        var delays: [Int: Int] = [:]
        for column in Set(letters.map(\.column)) {
            delays[column] = Int(dice.unit(column, 0, 0, 7) * Double(Self.spreadTicks))
        }
        self.delays = delays

        // Settled once every letter has cooled, every streak that left one
        // has fallen off the bottom, and the rest of the rain has cleared.
        let streak = content.settings.streak
        let falls = delays.values.map { $0 + rows + streak }.max() ?? 0
        let cools = letters.map { delays[$0.column, default: 0] + $0.row + 1 + Self.coolTicks }.max() ?? 0
        resolveTicks = letters.isEmpty ? 0 : max(falls, cools, Self.drainTicks) + 1
    }

    /// Whether the rain resolves into anything. Without a message it never
    /// settles.
    public var hasMessage: Bool { !letters.isEmpty }

    /// The parts the cue runs in, for its GO timeline: the message, from the
    /// end of the hold; or the rain and then the message on GO; or rain
    /// alone, which never finishes.
    public var parts: [Int] {
        guard hasMessage else { return [0] }
        return content.settings.messageOnGO ? [0, resolveTicks] : [resolveTicks]
    }

    /// The part that brings the message on.
    private var messagePart: Int { content.settings.messageOnGO ? 1 : 0 }

    /// Frames long enough for any streak to have fallen all the way: rain
    /// this far in fills the picture as steadily as it ever will.
    public var steadyTicks: Int {
        (rows + content.settings.streak * 2) * (Self.slownesses.max() ?? 1) + Self.slotTicks
    }

    /// The rain's own clock: frames since the cue fired, the hold included.
    func rainTime(_ f: Int, steady: Bool) -> Int {
        f + content.settings.holdTicks + (steady ? steadyTicks : 0)
    }

    /// The cue on frame `f`. With `steady`, the rain is as it is once it
    /// has filled the picture, rather than starting from the top: for rain
    /// put up already running.
    public func frame(_ f: Int, timeline: GoTimeline, steady: Bool = false) -> CascadeFrame {
        let r = rainTime(f, steady: steady)
        let start = hasMessage ? timeline.start(part: messagePart, offset: 0).map { rainTime($0, steady: steady) } : nil
        // The rain thins as it clears, and stops starting new streaks.
        let drain = start.map { min(1, max(0, 1 - Double(r - $0) / Double(Self.drainTicks))) } ?? 1

        var cells = [Cell](repeating: Cell(), count: rows * columns)
        func light(column: Int, head: Int, length: Int, scale: Double) {
            guard scale > 0 else { return }
            for d in 0..<length {
                let row = head - d
                if row < 0 { break }
                guard row < rows else { continue }
                let level = (1 - Double(d) / Double(length)) * scale
                let i = row * columns + column
                if d == 0 {
                    cells[i].head = true
                    cells[i].level = max(cells[i].level, level)
                } else if !cells[i].head {
                    cells[i].level = max(cells[i].level, level)
                }
            }
        }

        let streak = content.settings.streak
        let chance = Double(content.settings.density) / 100 * 0.5
        let slowest = Self.slownesses.max() ?? 1
        let longest = Int((Double(streak) * 1.4).rounded(.up))
        let life = (rows + longest) * slowest
        for column in 0..<columns {
            // Every slot whose streak could still be on the picture.
            let last = Self.floorDiv(r, Self.slotTicks)
            let first = Self.floorDiv(r - life, Self.slotTicks) - 1
            if last >= first {
                for slot in first...last {
                    guard dice.unit(column, slot, 0, 0) < chance else { continue }
                    let setsOff = slot * Self.slotTicks + Int(dice.unit(column, slot, 0, 1) * Double(Self.slotTicks))
                    guard setsOff >= 0, setsOff <= r else { continue }
                    if let start, setsOff >= start { continue }
                    let slowness = Self.slownesses[Int(dice.unit(column, slot, 0, 2) * Double(Self.slownesses.count))]
                    let length = max(2, Int((Double(streak) * (0.6 + 0.8 * dice.unit(column, slot, 0, 3))).rounded()))
                    light(column: column, head: (r - setsOff) / slowness, length: length, scale: drain)
                }
            }
            // The fast streak that leaves the message's letters in this column.
            if let start, let delay = delays[column], r >= start + delay {
                light(column: column, head: r - start - delay, length: streak, scale: 1)
            }
        }

        // The letters left so far, each in place of the rain on its cell.
        var letters: [CascadeFrame.Letter] = []
        if let start {
            for placed in self.letters {
                let left = start + delays[placed.column, default: 0] + placed.row + 1
                guard r >= left else { continue }
                letters.append(CascadeFrame.Letter(column: placed.column, row: placed.row, character: placed.character,
                                                   cooled: min(1, Double(r - left) / Double(Self.coolTicks))))
                cells[placed.row * columns + placed.column] = Cell()
            }
        }

        var glyphs: [CascadeFrame.Glyph] = []
        for (i, cell) in cells.enumerated() where cell.level > 0.01 {
            let column = i % columns, row = i / columns
            glyphs.append(glyph(column: column, row: row, at: r, level: cell.level, head: cell.head))
        }
        let settled = hasMessage && timeline.isFinished(at: f)
        return CascadeFrame(glyphs: settled ? [] : glyphs, letters: letters, isSettled: settled)
    }

    /// The glyph on a cell at rain time `r`. A head changes every frame; the
    /// glyphs it leaves behind each change now and then, at a pace of their
    /// own.
    private func glyph(column: Int, row: Int, at r: Int, level: Double, head: Bool) -> CascadeFrame.Glyph {
        let count = CascadeContent.glyphs.count
        let turn: Int
        if head {
            turn = r
        } else {
            let period = 6 + Int(dice.unit(column, row, 0, 12) * 34)
            let phase = Int(dice.unit(column, row, 0, 13) * Double(period))
            turn = Self.floorDiv(r + phase, period)
        }
        let glyph = min(count - 1, Int(dice.unit(column, row, turn, 14) * Double(count)))
        let mirrored = glyph < CascadeContent.katakanaCount && dice.unit(column, row, turn, 15) < 0.35
        return CascadeFrame.Glyph(column: column, row: row, glyph: glyph, mirrored: mirrored, level: level, head: head)
    }

    /// Rounded towards minus infinity, as frames before the start are.
    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        a >= 0 ? a / b : -((-a + b - 1) / b)
    }

    private struct Cell {
        var level = 0.0
        var head = false
    }

    /// Dice that give the same number for the same throw, so nothing has to
    /// be remembered between frames.
    struct Dice: Sendable {
        let seed: UInt64

        /// A number in `0..<1` for these four whole numbers.
        func unit(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Double {
            var x = Self.mix(seed ^ UInt64(bitPattern: Int64(a)))
            x = Self.mix(x ^ UInt64(bitPattern: Int64(b)))
            x = Self.mix(x ^ UInt64(bitPattern: Int64(c)))
            x = Self.mix(x ^ UInt64(bitPattern: Int64(d)))
            return Double(x >> 11) / 9_007_199_254_740_992
        }

        /// SplitMix64's step: every bit of the input stirs every bit out.
        private static func mix(_ v: UInt64) -> UInt64 {
            var z = v &+ 0x9E37_79B9_7F4A_7C15
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
