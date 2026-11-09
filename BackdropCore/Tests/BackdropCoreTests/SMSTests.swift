import Foundation
import Testing
@testable import BackdropCore

@Suite("Text message cues")
struct SMSTests {
    func message(_ settings: SMSSettings = .init()) -> Cue {
        Cue(number: "12", content: .sms(SMSContent(text: "Are you coming tonight?", sub: "Mum", settings: settings)))
    }

    @Test("A message round trips through show.json, and raises the version beyond any other cue")
    func roundTrip() throws {
        let cue = message(SMSSettings(style: .generic, entrance: .fade, dark: false, entranceMs: 1200, sent: true, status: .read))
        let show = Show(title: "T", cues: [cue])
        #expect(show.version == 10 && Show.formatVersion >= 10)
        let back = try JSONDecoder().decode(Show.self, from: try JSONEncoder().encode(show))
        #expect(back.cues == [cue])
        #expect(Show(title: "T", cues: [Cue(content: .feed(FeedContent()))]).version == 9)
    }

    @Test("show.json reads by hand, and a missing or unknown setting is the default")
    func lenient() throws {
        let json = #"{"kind":"sms","num":"4","text":"Hi","sub":"Dad","settings":{"style":"telegram","entranceMs":5,"sent":true}}"#
        let cue = try JSONDecoder().decode(Cue.self, from: Data(json.utf8))
        guard case .sms(let m) = cue.content else { Issue.record("not a message"); return }
        #expect(m.text == "Hi" && m.sub == "Dad")
        #expect(m.settings.style == .imessage && m.settings.sent)
        #expect(m.settings.entranceMs == SettingRange.smsEntranceMs.lowerBound, "clamped")
        let bare = try JSONDecoder().decode(Cue.self, from: Data(#"{"kind":"sms"}"#.utf8))
        #expect(bare.content == .sms(SMSContent()))
    }

    @Test("Its message and sender are the cue's text and sub, and it is in the Add Cue menus")
    func labels() {
        var cue = message()
        #expect(cue.text == "Are you coming tonight?" && cue.sub == "Mum")
        cue.text = "Yes"
        cue.sub = "Sam"
        #expect(cue.content == .sms(SMSContent(text: "Yes", sub: "Sam")))
        #expect(Cue.Kind.sms.heading == "Text Message")
        #expect(Cue.Kind.common.contains(.sms) || Cue.Kind.others.contains(.sms))
        #expect(cue.finishes && !cue.neverFinishes && cue.timing.isInstant)
    }

    @Test("A status belongs to a sent message, and reads leniently")
    func status() throws {
        #expect(SMSSettings(sent: false, status: .read).shownStatus == .none)
        #expect(SMSSettings(sent: true, status: .read).shownStatus == .read)
        #expect(SMSStatus.sending.line == "Sending\u{2026}" && SMSStatus.read.name == "Read")
        let bare = try JSONDecoder().decode(SMSSettings.self, from: Data(#"{"sent":true,"status":"seen"}"#.utf8))
        #expect(bare.status == .none)
    }

    @Test("Each GO moves a sent message's status on a step, towards read")
    func advancing() {
        #expect(SMSSettings(sent: true, status: .sending, advances: true).goStatuses == [.sent, .delivered, .read])
        #expect(SMSSettings(sent: true, status: .delivered, advances: true).goStatuses == [.read])
        #expect(SMSSettings(sent: true, status: .read, advances: true).goStatuses.isEmpty)
        #expect(SMSSettings(sent: true, status: .sending, advances: false).goStatuses.isEmpty)
        #expect(SMSSettings(sent: false, status: .sending, advances: true).goStatuses.isEmpty, "nothing to report on a message received")
        let cue = Cue(content: .sms(SMSContent(text: "Hi", settings: SMSSettings(sent: true, status: .sent, advances: true))))
        #expect(cue.goPoints() == [GoPoint(unit: .step, text: "Delivered"), GoPoint(unit: .step, text: "Read")])
        #expect(message().goPoints().isEmpty)
    }

    @Test("A status that moves on with GO round trips")
    func advancingRoundTrip() throws {
        let cue = message(SMSSettings(sent: true, status: .sending, advances: true))
        let back = try JSONDecoder().decode(Cue.self, from: try JSONEncoder().encode(cue))
        #expect(back == cue)
    }

    @Test("WhatsApp is a style by name, and reads back from show.json")
    func whatsapp() throws {
        #expect(SMSStyle.whatsapp.name == "WhatsApp" && SMSStyle.allCases.contains(.whatsapp))
        let cue = message(SMSSettings(style: .whatsapp))
        let back = try JSONDecoder().decode(Cue.self, from: try JSONEncoder().encode(cue))
        #expect(back == cue)
    }
}
