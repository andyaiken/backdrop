import Foundation

/// Which side of the conversation a message is on.
public enum ConversationSide: Equatable, Sendable {
    /// Arrives from the other person: on the left.
    case received
    /// Sent by the person whose phone it is: on the right.
    case sent
}

/// One message in the script.
public struct ConversationMessage: Equatable, Sendable {
    public var side: ConversationSide
    public var text: String
}

/// The messages between one GO and the next.
public struct ConversationStage: Equatable, Sendable {
    public var messages: [ConversationMessage]
    /// The line or action the GO before this stage waits for. Empty for the
    /// first stage, which runs when the cue fires.
    public var cuePoint: String
}

/// A conversation cue: a whole text exchange, set up beforehand and released
/// by GO. The messages arrive one after another within a stage, and the cue
/// waits for GO between stages.
public struct ConversationContent: Equatable, Sendable {
    /// The cue's name.
    public var text: String
    /// The contact's name, across the top of the conversation.
    public var sub: String
    /// The messages, a line to each. `<` starts a message received and `>` one
    /// sent. A line of `GO` makes the cue wait for GO before what follows;
    /// anything written after it is the line or action GO waits for. Other
    /// lines are ignored, so they can be notes.
    public var script: String
    public var settings: ConversationSettings

    public init(text: String = "", sub: String = "", script: String = "", settings: ConversationSettings = .init()) {
        self.text = text
        self.sub = sub
        self.script = script
        self.settings = settings
    }

    /// The script in stages. Always at least one.
    public var stages: [ConversationStage] {
        var stages = [ConversationStage(messages: [], cuePoint: "")]
        for raw in script.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.count >= 2, line.prefix(2).uppercased() == "GO", line.count == 2 || line.dropFirst(2).first?.isWhitespace == true {
                stages.append(ConversationStage(messages: [], cuePoint: line.dropFirst(2).trimmingCharacters(in: .whitespaces)))
            } else if let first = line.first, first == "<" || first == ">" {
                let text = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { stages[stages.count - 1].messages.append(ConversationMessage(side: first == ">" ? .sent : .received, text: text)) }
            }
        }
        return stages
    }

    /// Every message in order.
    public var messages: [ConversationMessage] { stages.flatMap(\.messages) }

    /// Whether any message is sent, so there is a compose bar to show.
    public var hasSent: Bool { messages.contains { $0.side == .sent } }

    /// Where the cue waits for GO: before each stage after the first.
    public func goPoints() -> [GoPoint] {
        stages.dropFirst().map { stage in
            GoPoint(unit: .stage, text: stage.messages.first?.text ?? "(nothing)", cuePoint: stage.cuePoint)
        }
    }
}

/// A conversation cue's settings.
public struct ConversationSettings: Codable, Equatable, Sendable {
    public var style: SMSStyle
    public var dark: Bool
    /// Shows the dots while a message is on its way, and the compose bar
    /// while one is typed. Off, the bubbles just arrive.
    public var showTyping: Bool
    /// Steps of the clock between one message finishing and the next
    /// starting.
    public var pauseTicks: Int

    public init(style: SMSStyle = .imessage, dark: Bool = true, showTyping: Bool = true, pauseTicks: Int = 16) {
        self.style = style
        self.dark = dark
        self.showTyping = showTyping
        self.pauseTicks = SettingRange.pauseTicks.clamp(pauseTicks)
    }

    private enum CodingKeys: String, CodingKey {
        case style, dark, showTyping, pauseTicks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ConversationSettings()
        style = (try? c.decodeIfPresent(SMSStyle.self, forKey: .style)) ?? d.style
        dark = try c.value(.dark, d.dark)
        showTyping = try c.value(.showTyping, d.showTyping)
        pauseTicks = try c.value(.pauseTicks, d.pauseTicks, in: SettingRange.pauseTicks)
    }
}

/// When each message of a conversation cue arrives, and what is on the
/// screen at any moment. Times are in frames of the standard clock.
public struct ConversationCuePlan: Sendable {
    public let content: ConversationContent
    let stages: [ConversationStage]

    /// Frames a bubble takes to grow into place.
    public static let arriveFrames = 10.0
    /// Frames the dots take to open before they pulse.
    public static let dotsOpenFrames = 6.0

    public init(_ content: ConversationContent) {
        self.content = content
        stages = content.stages
    }

    /// Frames the dots show before a received message arrives.
    func typingFrames(_ m: ConversationMessage) -> Double {
        content.settings.showTyping ? Double(min(70, 20 + m.text.count)) : 0
    }

    /// Frames a sent message spends being typed into the bar.
    func composeFrames(_ m: ConversationMessage) -> Double {
        content.settings.showTyping ? Double(min(90, max(8, m.text.count * 2))) : 0
    }

    /// How long a message takes from its start until it has settled.
    func duration(_ m: ConversationMessage) -> Double {
        (m.side == .received ? typingFrames(m) : composeFrames(m)) + Self.arriveFrames
    }

    /// Where each of a stage's messages starts, within it.
    func offsets(_ stage: ConversationStage) -> [Double] {
        var at = 0.0
        var result: [Double] = []
        for m in stage.messages {
            result.append(at)
            at += duration(m) + Double(content.settings.pauseTicks)
        }
        return result
    }

    /// The frames each stage takes, from its GO until its last message has settled.
    public var parts: [Int] {
        stages.map { stage in
            guard let last = stage.messages.last, let at = offsets(stage).last else { return 0 }
            return Int((at + duration(last)).rounded(.up))
        }
    }

    /// Where one message is in its arrival.
    public enum Phase: Equatable, Sendable {
        /// The dots, this many frames in.
        case typing(Double)
        /// Growing into place, 0 to 1, from the dots if they were showing.
        case arriving(Double, fromDots: Bool)
        case settled
    }

    public struct Item: Equatable, Sendable {
        /// Its place in the whole script.
        public var index: Int
        public var side: ConversationSide
        public var text: String
        /// Whether it ends a run from one side, so it takes the tail.
        public var hasTail: Bool
        /// Whether the message before it, if there is one, is from the same side.
        public var joinsPrevious: Bool
        public var phase: Phase
    }

    public struct State: Equatable, Sendable {
        /// The messages on the screen so far, oldest first.
        public var items: [Item] = []
        /// What the compose bar holds, while a message is being typed into it.
        public var composing: String?
    }

    /// What the screen shows at frame `f`.
    public func state(at f: Double, timeline: GoTimeline) -> State {
        var state = State()
        let all = content.messages
        var index = 0
        for (p, stage) in stages.enumerated() {
            let offsets = offsets(stage)
            let base = timeline.start(part: p, offset: 0).map(Double.init)
            for (i, m) in stage.messages.enumerated() {
                defer { index += 1 }
                guard let base, f >= base + offsets[i] else { continue }
                let local = f - base - offsets[i]
                let lead = m.side == .received ? typingFrames(m) : composeFrames(m)
                var item = Item(index: index, side: m.side, text: m.text,
                                hasTail: index + 1 >= all.count || all[index + 1].side != m.side,
                                joinsPrevious: index > 0 && all[index - 1].side == m.side,
                                phase: .settled)
                if local < lead {
                    if m.side == .received {
                        item.phase = .typing(local)
                    } else {
                        state.composing = String(m.text.prefix(Int(local / lead * Double(m.text.count))))
                        continue
                    }
                } else if local < lead + Self.arriveFrames {
                    item.phase = .arriving((local - lead) / Self.arriveFrames, fromDots: m.side == .received && lead > 0)
                }
                state.items.append(item)
            }
        }
        return state
    }
}
