import Testing
@testable import BackdropCore

@Suite("Shows and cues outside the console")
struct ShowSearchTests {
    @Test("A cue is named by its number and words, or its kind when it has none")
    func cueTitles() {
        #expect(Cue(number: "12", content: .title(TitleContent(text: "THE LOUVRE"))).title == "Cue 12: THE LOUVRE")
        #expect(Cue(number: " 4.5 ", content: .blank(BlankContent())).title == "Cue 4.5: Blank cue")
        #expect(Cue(number: "", content: .image(ImageContent(text: "Mona Lisa"))).title == "Mona Lisa")
        #expect(Cue(number: "P1", content: .anagram(AnagramContent(text: "O, Draconian devil!", answer: "Leonardo da Vinci!"))).title
                == "Cue P1: O, Draconian devil!")
    }

    @Test("A show is found by its cues' words, subtext and cue points, each once")
    func searchableText() {
        var louvre = Cue(number: "1", content: .title(TitleContent(text: "THE LOUVRE", sub: "PARIS")))
        louvre.line = "SOPHIE: \u{201C}Come with me.\u{201D}"
        let again = Cue(number: "2", content: .image(ImageContent(text: "the louvre")))
        let blank = Cue(number: "3", content: .blank(BlankContent()))
        let anagram = Cue(number: "4", content: .anagram(AnagramContent(text: "Oh, lame saint!", answer: "The Mona Lisa!")))
        let show = Show(title: "The Da Vinci Code", cues: [louvre, again, blank, anagram])
        #expect(show.searchableText == "THE LOUVRE\nPARIS\nSOPHIE: \u{201C}Come with me.\u{201D}\nOh, lame saint!\nThe Mona Lisa!")
        #expect(Show(title: "Empty", cues: []).searchableText.isEmpty)
    }
}
