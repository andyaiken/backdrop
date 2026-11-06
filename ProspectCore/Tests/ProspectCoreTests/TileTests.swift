import Testing
@testable import ProspectCore

@Suite("Image tiles, against recorded schedules")
struct TileTests {
    static let cases = (try? Fixtures.load("tiles", as: TilesFixture.self).tiles) ?? []

    @Test func fixturesLoaded() {
        #expect(!Self.cases.isEmpty)
    }

    @Test(arguments: cases)
    func schedule(_ c: TilesFixture.Case) throws {
        let grid = TileGrid(imageWidth: c.width, imageHeight: c.height, columns: c.settings.cols)
        #expect(grid.columns == c.cols)
        #expect(grid.rows == c.rows)

        var random = SeededRandom(seed: c.seed)
        let order = try #require(TileOrder(rawValue: c.settings.order))
        let schedule = TileSchedule(grid: grid, order: order, wave: c.settings.stagger, random: &random)
        #expect(schedule.starts == c.starts)
        #expect(schedule.lastStart == c.lastStart)
        #expect(schedule.settleFrame(flipMs: c.settings.flipMs, clockMs: c.settings.speed) == c.settledAt)
    }

    @Test(arguments: cases)
    func backColours(_ c: TilesFixture.Case) {
        #expect(c.pixels.count == c.cols * c.rows * 4)
        #expect(TileFaces.backColours(rgba: c.pixels).map(\.hex) == c.backColours.map { "#" + $0 })
    }

    @Test func everyOrderSpansTheSameDuration() {
        let grid = TileGrid(imageWidth: 1600, imageHeight: 900, columns: 12)
        let span = (grid.columns + grid.rows - 2) * 3
        var random = SystemUnitRandom()
        for _ in 0..<20 {
            let diagonal = TileSchedule(grid: grid, order: .diagonal, wave: 3, random: &random)
            let shuffled = TileSchedule(grid: grid, order: .random, wave: 3, random: &random)
            let spiral = TileSchedule(grid: grid, order: .spiral, wave: 3, random: &random)
            // The same span; only the jitter differs, up to 6 frames against up to 2.
            #expect((span...span + 6).contains(diagonal.lastStart))
            #expect((span...span + 2).contains(shuffled.lastStart))
            #expect(shuffled.starts.allSatisfy { (0...span + 2).contains($0) })
            #expect((span...span + 2).contains(spiral.lastStart))
            #expect(spiral.starts.allSatisfy { (0...span + 2).contains($0) })
        }
    }

    @Test("An 8 x 5 grid cuts into the Fibonacci squares 5, 3, 2, 1, 1, turning clockwise")
    func fibonacciRectangle() {
        #expect(SpiralSquare.cut(columns: 8, rows: 5) == [
            SpiralSquare(x: 0, y: 0, side: 5, cut: .left),
            SpiralSquare(x: 5, y: 0, side: 3, cut: .top),
            SpiralSquare(x: 6, y: 3, side: 2, cut: .right),
            SpiralSquare(x: 5, y: 4, side: 1, cut: .bottom),
            SpiralSquare(x: 5, y: 3, side: 1, cut: .left),
        ])
        // Upright, it starts from the top instead.
        #expect(SpiralSquare.cut(columns: 5, rows: 8).map(\.side) == [5, 3, 2, 1, 1])
        #expect(SpiralSquare.cut(columns: 5, rows: 8).first?.cut == .top)
    }

    @Test("Any grid cuts into squares that cover it exactly once")
    func spiralCoversAnyGrid() {
        for columns in 2...28 {
            for rows in 2...16 {
                var covered = [Int](repeating: 0, count: columns * rows)
                for square in SpiralSquare.cut(columns: columns, rows: rows) {
                    for y in square.y..<square.y + square.side {
                        for x in square.x..<square.x + square.side { covered[y * columns + x] += 1 }
                    }
                }
                #expect(covered.allSatisfy { $0 == 1 }, "\(columns) x \(rows)")
            }
        }
    }

    @Test("The quarter turn in the big square runs from its bottom-left corner round to its top right")
    func quarterTurn() {
        let square = SpiralSquare(x: 0, y: 0, side: 5, cut: .left)
        #expect(square.turn(column: 0, row: 4) < 0.1)
        #expect(abs(square.turn(column: 2, row: 2) - 0.5) < 1e-9, "the diagonal is halfway")
        #expect(square.turn(column: 4, row: 0) > 0.9)
    }

    @Test("The spiral starts in the smallest square and ends at the far edge of the largest")
    func spiralOrder() {
        struct Still: UnitRandom {
            mutating func next() -> Double { 0 }
        }
        var still = Still()
        let grid = TileGrid(imageWidth: 1600, imageHeight: 1000, columns: 8)
        #expect(grid.columns == 8 && grid.rows == 5)
        let schedule = TileSchedule(grid: grid, order: .spiral, wave: 3, random: &still)
        func start(_ x: Int, _ y: Int) -> Int { schedule.starts[y * 8 + x] }
        #expect(start(5, 3) == 0, "the eye of the spiral first")
        #expect(start(0, 4) == schedule.lastStart && schedule.lastStart == (8 + 5 - 2) * 3, "the bottom-left corner last")
        // Square by square, outward: every tile in a smaller square before any in a larger.
        let squares = SpiralSquare.cut(columns: 8, rows: 5).reversed().map { square in
            (square.y..<square.y + square.side).flatMap { y in (square.x..<square.x + square.side).map { start($0, y) } }
        }
        for (inner, outer) in zip(squares, squares.dropFirst()) {
            #expect(inner.max()! <= outer.min()!)
        }
        // Tiles on one line from the corner the big square turns about start together.
        #expect(start(4, 4) == start(3, 3) && start(3, 3) == start(1, 1))
    }
}

@Suite("Quarters")
struct QuarterTests {
    @Test("Every rectangle splits once, in an order picked at random, each only after its parent")
    func splits() {
        var random = SeededRandom(seed: 3)
        let s = QuarterSchedule(depth: 3, step: 2, random: &random)
        // 1 + 4 + 16 rectangles can split; the 64 smallest cannot.
        #expect(s.splits.count == 21 && Set(s.splits).count == 21)
        #expect(s.splits.first == 0 && s.starts == (0..<21).map { $0 * 2 } && s.lastStart == 40)
        for (i, node) in s.splits.enumerated() where node > 0 {
            #expect(s.splits.firstIndex(of: (node - 1) / 4)! < i, "a rectangle exists before it splits")
        }
        #expect(QuarterSchedule.nodeCount(depth: 3) == 85)
        // Another seed, another order, the same set.
        var other = SeededRandom(seed: 4)
        let t = QuarterSchedule(depth: 3, step: 2, random: &other)
        #expect(t.splits != s.splits && Set(t.splits) == Set(s.splits))
    }

    @Test("A split leaves three rectangles more: one, then four, then seven")
    func rectangleCount() {
        var random = SeededRandom(seed: 9)
        let s = QuarterSchedule(depth: 3, step: 1, random: &random)
        func showing(at f: Int) -> Int {
            (0..<QuarterSchedule.nodeCount(depth: 3)).filter { s.birthFrame(of: $0) <= f && f < (s.splitFrame(of: $0) ?? Int.max) }.count
        }
        #expect((-5, showing(at: -5)) == (-5, 1), "the whole picture before anything splits")
        #expect([0, 1, 2, 3].map(showing) == [4, 7, 10, 13])
        #expect(showing(at: s.lastStart) == 64, "ends as the smallest rectangles")
    }

    @Test("Rectangles tile the picture exactly, quarter by quarter")
    func geometry() {
        let r = QuarterSchedule.rect(of: 0)
        #expect(r.x == 0 && r.y == 0 && r.width == 1 && r.height == 1)
        let q = QuarterSchedule.children(of: 0).map(QuarterSchedule.rect(of:))
        #expect(q.map(\.x) == [0, 0.5, 0, 0.5] && q.map(\.y) == [0, 0, 0.5, 0.5] && q.allSatisfy { $0.width == 0.5 && $0.height == 0.5 })
        let leaves = (0..<QuarterSchedule.nodeCount(depth: 3)).filter { QuarterSchedule.level(of: $0) == 3 }
        #expect(leaves.count == 64 && abs(leaves.map { QuarterSchedule.rect(of: $0) }.reduce(0) { $0 + $1.width * $1.height } - 1) < 1e-9)
    }

    @Test("More columns, deeper splitting")
    func depth() {
        #expect([4, 12, 20, 28].map(QuarterSchedule.depth(forColumns:)) == [1, 3, 3, 4])
    }
}
