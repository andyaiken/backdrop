import Testing
@testable import BackdropCore

@Suite("Letters fading")
struct FadeTests {
    func plan(_ text: String = "SOFIA", key: String = "SANGREAL", wave: Int = 3) -> TravelPlan {
        var random = SeededRandom(seed: 9)
        return TravelPlan(text: text, key: key, wave: wave, random: &random)
    }

    @Test("Before it moves a fade shows the ciphertext alone; once home, the letter alone")
    func endsMatch() {
        let p = plan()
        let before = p.blends(-1), after = p.blends(p.duration)
        for (c, (b, a)) in zip(p.characters, zip(before, after)) {
            #expect(b.glyph == c.cipher && b.progress == 0)
            #expect(b.blend == GlyphBlend(from: c.cipher, to: c.plain, amount: 0))
            #expect(a.glyph == c.plain && a.isSettled && a.blend == nil)
            #expect(b.dial == nil && b.flap == nil, "neither a dial nor a card")
        }
    }

    @Test("A fade goes one way only, between the same two glyphs, slow at each end")
    func oneWay() {
        let p = plan()
        for (i, c) in p.characters.enumerated() {
            let amounts = (c.start...c.start + c.total - 1).map { f -> Double in
                let blend = p.blends(f)[i].blend!
                #expect(blend.from == c.cipher && blend.to == c.plain, "\(c.plain): nothing between")
                return blend.amount
            }
            let steps = zip(amounts, amounts.dropFirst()).map { $1 - $0 }
            #expect(steps.allSatisfy { $0 >= 0 }, "\(c.plain): never back")
            let middle = steps[steps.count / 2]
            #expect(steps.first! < middle && steps.last! < middle, "\(c.plain): easing in and out")
        }
    }

    @Test("The glyph is whichever of the two is nearer")
    func nearer() {
        let p = plan()
        for (i, c) in p.characters.enumerated() where c.cipher != c.plain {
            for f in c.start..<c.start + c.total {
                let g = p.blends(f)[i]
                #expect(g.glyph == (g.blend!.amount < 0.5 ? c.cipher : c.plain), "\(c.plain) on frame \(f)")
            }
        }
    }

    @Test("A space fades to nothing, and a ciphertext space is its open box")
    func spaces() throws {
        let p = plan("THE CRYPTEX", key: "APPLE")
        let gap = try #require(p.characters.firstIndex { $0.plain == " " })
        let c = p.characters[gap]
        let fading = try #require(p.blends(c.start + c.total / 2)[gap].blend)
        #expect(fading.to == " ", "the gap it is")
        // A shift of one takes a hyphen round to the ring's space, so its
        // fade starts from the box.
        let boxed = plan("-", key: "B")
        #expect(boxed.characters[0].cipher == " " && boxed.blends(0)[0].blend?.from == Cipher.spaceMark)
    }

    @Test("A fade settles on the same frame cycling glyphs do, and rolls no dice")
    func sameTimingNoDice() {
        let cycling = TitleSettings(clockMs: 44, waveTicks: 3, holdTicks: 44, histogram: true, sceneLine: true)
        var fade = cycling
        fade.letters = .fade
        var seeded = SeededRandom(seed: 4), alsoSeeded = SeededRandom(seed: 4)
        let a = TitleReveal(text: "SOFIA", scene: "THE CRYPTEX", key: "APPLE", settings: cycling, random: &seeded)
        let b = TitleReveal(text: "SOFIA", scene: "THE CRYPTEX", key: "APPLE", settings: fade, random: &alsoSeeded)
        #expect(a.titlePlan == b.titlePlan, "the same plan either way")
        var noDice = NoDice()
        for f in -5...200 {
            #expect(a.frame(f, random: &seeded).isSettled == b.frame(f, random: &noDice).isSettled, "frame \(f)")
        }
        #expect(b.frame(200, random: &noDice).title.map(\.glyph) == Array("SOFIA"))
        #expect(b.frame(200, random: &noDice).scene.map(\.glyph) == Array("THE CRYPTEX"), "a settled space is a real gap")
    }

    @Test("Between frames, a blend is where it would be by then, and on a frame, just where the frame puts it")
    func betweenFrames() {
        let p = plan()
        for f in -2...p.duration + 1 {
            #expect(p.blends(at: Double(f)) == p.blends(f), "frame \(f)")
        }
        for (i, c) in p.characters.enumerated() {
            let f = c.start + c.total / 2
            let before = p.blends(f)[i].blend!.amount, between = p.blends(at: Double(f) + 0.5)[i].blend!.amount
            let after = p.blends(f + 1)[i].blend!.amount
            #expect(before < between && between < after, "\(c.plain): partway, between the frames either side")
        }
    }

    @Test("Characters outside the ring stand still, never fading")
    func outsideTheRing() {
        let p = plan("SOFIA\u{2019}S", key: "APPLE")
        let apostrophe = p.blends(5)[5]
        #expect(apostrophe.glyph == "\u{2019}" && apostrophe.blend == nil && apostrophe.isSettled)
    }
}
