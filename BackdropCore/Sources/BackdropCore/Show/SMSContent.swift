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

/// How a message looks.
public enum SMSStyle: String, Codable, Sendable, CaseIterable {
    /// Blue-grey bubbles on iMessage lines: a tail, and the sender small
    /// above in grey.
    case imessage
    /// Plain rounded bubble, no platform's look to it.
    case generic
    /// Green sent bubbles on a chat wallpaper's colour, small corners and a
    /// tail at the top, where the run of messages starts.
    case whatsapp

    public var name: String {
        switch self {
        case .imessage: "iMessage"
        case .generic: "Generic"
        case .whatsapp: "WhatsApp"
        }
    }
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

    public init(style: SMSStyle = .imessage, entrance: SMSEntrance = .pop, dark: Bool = true,
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
