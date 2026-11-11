import Foundation

/// A text message cue: one message bubble with a "from" line, popping onto
/// the screen and settling, as a notification of a phone's does.
///
/// It's a still picture once it has landed, and stays up until the next cue
/// replaces it.
public struct SMSContent: Equatable, Sendable {
    /// The message.
    public var text: String
    /// Who it's from, on the line above the bubble.
    public var sub: String
    public var settings: SMSSettings

    public init(text: String = "", sub: String = "", settings: SMSSettings = .init()) {
        self.text = text
        self.sub = sub
        self.settings = settings
    }
}

/// How a message looks. Named for what they look like rather than for any
/// messaging app, as an app may not borrow another's name. The raw values
/// are what show.json has always held, so older shows read back the same.
public enum SMSStyle: String, Codable, Sendable, CaseIterable {
    /// Blue sent bubbles and grey received ones, round, with a tail at the
    /// corner nearest the sender, and the sender small above in grey.
    case blueBubbles = "imessage"
    /// The same bubbles with the sent ones green, as a phone shows a text
    /// to or from a phone of another make.
    case greenBubbles = "greenbubbles"
    /// Green sent messages on a chat wallpaper's colour, in rectangles with
    /// small corners, a tail at the top where a run of messages starts, and
    /// the status as ticks inside.
    case greenRectangles = "whatsapp"
    /// Plain rounded bubble, no platform's look to it.
    case generic

    public var name: String {
        switch self {
        case .blueBubbles: "Blue bubbles"
        case .greenBubbles: "Green bubbles"
        case .greenRectangles: "Green rectangles"
        case .generic: "Generic"
        }
    }

    /// Round bubbles with a tail, blue or green, alike but for the colour.
    public var isRound: Bool { self == .blueBubbles || self == .greenBubbles }
}

/// How a message arrives.
public enum SMSEntrance: String, Codable, Sendable, CaseIterable {
    /// Zooms in from small, overshoots a little, and settles.
    case pop
    /// Fades up in place.
    case fade
    /// Is there at once.
    case cut

    public var name: String {
        switch self {
        case .pop: "Zoom and settle"
        case .fade: "Fade"
        case .cut: "Cut"
        }
    }
}

/// How far a sent message has got, as the phone reports it.
public enum SMSStatus: String, Codable, Sendable, CaseIterable {
    case none, sending, sent, delivered, read

    public var name: String { rawValue.capitalized }

    /// The order a message goes through, from sending to read.
    public static let flow: [SMSStatus] = [.sending, .sent, .delivered, .read]

    /// The line beneath the bubble in the styles that write it.
    public var line: String {
        switch self {
        case .none: ""
        case .sending: "Sending\u{2026}"
        case .sent: "Sent"
        case .delivered: "Delivered"
        case .read: "Read"
        }
    }
}

/// A message cue's settings.
public struct SMSSettings: Codable, Equatable, Sendable {
    public var style: SMSStyle
    public var entrance: SMSEntrance
    /// A dark screen, or a light one.
    public var dark: Bool
    /// How long the arrival takes, in milliseconds.
    public var entranceMs: Int
    /// The bubble was sent by the person on stage (right, in colour) rather
    /// than received (left, grey).
    public var sent: Bool
    /// How far the message has got. Only a message sent has one.
    public var status: SMSStatus

    /// The status that shows: none for a message received.
    public var shownStatus: SMSStatus { sent ? status : .none }
    /// Whether each GO moves the status on a step, from where it starts
    /// towards read.
    public var advances: Bool

    /// The statuses the GOs bring on, in turn.
    public var goStatuses: [SMSStatus] {
        guard advances, let at = SMSStatus.flow.firstIndex(of: shownStatus) else { return [] }
        return Array(SMSStatus.flow[(at + 1)...])
    }

    public init(style: SMSStyle = .blueBubbles, entrance: SMSEntrance = .pop, dark: Bool = true,
                entranceMs: Int = 900, sent: Bool = false, status: SMSStatus = .none, advances: Bool = false) {
        self.style = style
        self.entrance = entrance
        self.dark = dark
        self.entranceMs = SettingRange.smsEntranceMs.clamp(entranceMs)
        self.sent = sent
        self.status = status
        self.advances = advances
    }

    private enum CodingKeys: String, CodingKey {
        case style, entrance, dark, entranceMs, sent, status, advances
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SMSSettings()
        // A hand-edited value that isn't one of the choices is the default.
        style = (try? c.decodeIfPresent(SMSStyle.self, forKey: .style)) ?? d.style
        entrance = (try? c.decodeIfPresent(SMSEntrance.self, forKey: .entrance)) ?? d.entrance
        dark = try c.value(.dark, d.dark)
        entranceMs = try c.value(.entranceMs, d.entranceMs, in: SettingRange.smsEntranceMs)
        sent = try c.value(.sent, d.sent)
        status = (try? c.decodeIfPresent(SMSStatus.self, forKey: .status)) ?? d.status
        advances = try c.value(.advances, d.advances)
    }
}
