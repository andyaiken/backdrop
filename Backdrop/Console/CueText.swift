import Foundation
import BackdropCore
import BackdropStage

/// What the console says about a cue, in one place, so the rail, the
/// standby card, the GO plate and the Studio all say the same thing.
enum CueText {
    /// The cue's name on one line, each line break shown as ⏎, or a dash
    /// for a cue with none.
    static func name(_ cue: Cue) -> String {
        cue.text.isEmpty ? "\u{2014}" : cue.text.replacingOccurrences(of: "\n", with: " \u{23CE} ")
    }

    /// What the cue shows under its name in the rail: its subtitle, or what
    /// it still needs, such as "no picture", or how many boxes or stops it has.
    static func summary(_ cue: Cue) -> String {
        switch cue.content {
        case .title(let c): c.sub
        case .anagram(let c):
            [c.anagrams.first.map { $0.answer.isEmpty ? "" : "\u{2192} " + $0.answer } ?? "",
             c.anagrams.count > 1 ? "and \(c.anagrams.count - 1) more" : ""].filter { !$0.isEmpty }.joined(separator: "   ")
        case .image(let c): c.src.isEmpty ? "no picture" : ""
        case .morph(let c):
            c.pictures.count < 2 ? "needs two pictures"
                : c.pictures.count > 2 ? "\(c.pictures.count) pictures"
                : "\(c.pictures[1].pairs.count) point\(c.pictures[1].pairs.count == 1 ? "" : "s")"
        case .map(let c):
            c.src.isEmpty ? "no map"
                : c.stops.count < 2 ? "no stops" : "\(c.stops.count - 1) stop\(c.stops.count == 2 ? "" : "s")"
        case .video(let c): [c.sub, c.atEnd == .hold ? "" : c.atEnd.rawValue].filter { !$0.isEmpty }.joined(separator: "   ")
        case .feed(let c):
            [c.sub, c.settings.device.isEmpty ? "no camera" : c.settings.deviceName].filter { !$0.isEmpty }.joined(separator: "   ")
        case .blank(let c): c.colour.hex
        case .conversation(let c):
            c.messages.isEmpty ? "no messages" : "\(c.messages.count) message\(c.messages.count == 1 ? "" : "s")"
        case .sms(let c):
            [c.sub.isEmpty ? "no sender" : "from \(c.sub)",
             c.settings.shownStatus == .none ? (c.settings.sent ? "sent" : "")
                : "sent, \(c.settings.shownStatus.name.lowercased())" + (c.settings.goStatuses.isEmpty ? "" : " \u{2192} read")]
                .filter { !$0.isEmpty }.joined(separator: "   ")
        case .keypad(let c): c.script.isEmpty ? "no keys" : "\(c.boxCount) boxes"
        case .cascade(let c): c.hasMessage ? (c.settings.messageOnGO ? "message on GO" : "") : "rain only"
        case .text: ""
        case .layered(let c):
            c.layers.isEmpty ? "no layers" : "\(c.layers.count) layer\(c.layers.count == 1 ? "" : "s")"
        }
    }

    /// The cue's transition in, as the console says it: "fade 0.5 s",
    /// "crossfade 1.0 s", "wipe from left 0.5 s" or "snap".
    static func transitionNote(_ cue: Cue) -> String {
        transitionNote(cue.transition)
    }

    static func transitionNote(_ transition: Transition) -> String {
        let length = SettingKey.fade.format(.number(transition.fadeMs))
        return switch transition.style {
        case .snap: "snap"
        case .fade: "fade " + length
        case .crossfade: "crossfade " + length
        case .wipe: "wipe from " + SettingKey.wipeFrom.format(.edge(transition.wipeFrom)) + " " + length
        }
    }

    /// What GO will do: fire the cue standing by, carry the live cue on to
    /// a step, fire a cue straight at a step, or nothing at the end.
    static func goTip(goPoint: ShowController.StandingByGoPoint?, live: UUID?, next: Cue?) -> String {
        goPoint.map { $0.cue.id == live ? "Carry cue \($0.cue.number) on" : "Fire cue \($0.cue.number) at GO \($0.number)" }
            ?? next.map { "Fire cue \($0.number)" } ?? "End of the cue sheet"
    }

    /// What one GO runs, when it runs more than the one cue: "One GO runs 5,
    /// then 6 after 3.0 s". Nil when it runs only the cue itself.
    static func reach(_ reach: [Reach]) -> String? {
        guard let first = reach.first, reach.count > 1 else { return nil }
        let then = reach.dropFirst().map { step -> String in
            let number = step.cue.number
            return switch step.via {
            case .go: number
            case .after(0): "\(number) at once"
            case .after(let ms): "\(number) after \(seconds(ms))"
            case .whenFinished(0): "\(number) when that finishes"
            case .whenFinished(let ms): "\(number) \(seconds(ms)) after that finishes"
            }
        }
        return "One GO runs \(first.cue.number), then " + then.joined(separator: ", then ")
    }

    /// Seconds to a tenth, as the console gives lengths: "3.0 s".
    static func seconds(_ ms: Int) -> String {
        fixedDecimal(Double(ms) / 1000, digits: 1) + " s"
    }

    /// "waits for 1 GO partway", for a cue with steps.
    static func partway(_ steps: Int) -> String {
        "waits for \(steps) GO\(steps == 1 ? "" : "s") partway"
    }
}
