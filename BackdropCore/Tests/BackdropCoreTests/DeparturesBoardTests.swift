import Testing
@testable import BackdropCore

@Suite("Letters on a departures board")
struct DeparturesBoardTests {
    func plan(_ text: String = "SOFIA", key: String = "SANGREAL", wave: Int = 3) -> TravelPlan {
        var random = SeededRandom(seed: 9)
        return TravelPlan(text: text, key: key, wave: wave, random: &random)
    }

    @Test("Before it moves a card shows the ciphertext; once home, the letter")
    func endsMatch() {
        let p = plan()
        let before = p.board(-1), after = p.board(p.duration)
        for (c, (b, a)) in zip(p.characters, zip(before, after)) {
            #expect(b.glyph == c.cipher && b.flap == Double(Cipher.ringPosition(c.cipher)!) && b.progress == 0)
            #expect(a.glyph == c.plain && a.flap == Double(Cipher.ringPosition(c.plain)!) && a.isSettled)
            #expect(b.dial == nil && a.dial == nil, "a card is not a dial")
        }
    }

    @Test("A card only ever flips forwards, round to its letter, slowing as it goes")
    func flipsForwards() {
        let p = plan()
        let n = Double(Cipher.ring.count)
        for (i, c) in p.characters.enumerated() {
            let from = Cipher.ringPosition(c.cipher)!, to = Cipher.ringPosition(c.plain)!
            let ahead = Double((to - from + Cipher.ring.count) % Cipher.ring.count)
            var flipped = 0.0, steps: [Double] = []
            var last = p.board(c.start)[i].flap!
            for f in c.start + 1...c.start + c.total {
                let now = p.board(f)[i].flap!
                var step = now - last
                if step < 0 { step += n }
                steps.append(step)
                flipped += step
                last = now
            }
            #expect(abs(flipped - (ahead == 0 ? n : ahead)) < 1e-9, "\(c.plain): forwards to its letter, a whole turn if already there")
            #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 >= $1 - 1e-9 }, "\(c.plain): never speeding up")
        }
    }

    @Test("A card already on its letter goes a whole turn, so every letter is seen to move")
    func wholeTurn() {
        // A key of A shifts nothing: every ciphertext letter is its plaintext.
        let p = plan("SOFIA", key: "A")
        for (i, c) in p.characters.enumerated() {
            #expect(c.cipher == c.plain)
            let middle = p.board(c.start + c.total / 2)[i]
            #expect(middle.flap! != Double(Cipher.ringPosition(c.plain)!) && !middle.isSettled, "\(c.plain): turning")
        }
    }

    @Test("A board settles on the same frame cycling glyphs do, and rolls no dice")
    func sameTimingNoDice() {
        let cycling = TitleSettings(clockMs: 44, waveTicks: 3, holdTicks: 44, histogram: true, sceneLine: true)
        var board = cycling
        board.letters = .departuresBoard
        var seeded = SeededRandom(seed: 4), alsoSeeded = SeededRandom(seed: 4)
        let a = TitleReveal(text: "SOFIA", scene: "THE CRYPTEX", key: "APPLE", settings: cycling, random: &seeded)
        let b = TitleReveal(text: "SOFIA", scene: "THE CRYPTEX", key: "APPLE", settings: board, random: &alsoSeeded)
        #expect(a.titlePlan == b.titlePlan, "the same plan either way")
        var noDice = NoDice()
        for f in -5...200 {
            #expect(a.frame(f, random: &seeded).isSettled == b.frame(f, random: &noDice).isSettled, "frame \(f)")
        }
        #expect(b.frame(200, random: &noDice).title.map(\.glyph) == Array("SOFIA"))
        #expect(b.frame(200, random: &noDice).scene.map(\.glyph) == Array("THE CRYPTEX"), "a settled space is a real gap")
    }

    @Test("Characters outside the ring stand still, off the board's ring")
    func outsideTheRing() {
        let p = plan("SOFIA\u{2019}S", key: "APPLE")
        let apostrophe = p.board(5)[5]
        #expect(apostrophe.glyph == "\u{2019}" && apostrophe.flap == nil && apostrophe.isSettled)
    }
}
