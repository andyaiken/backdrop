/// What the Mac is doing that could spoil a performance. The app reads it
/// from macOS as it changes; `warnings` turns it into what the console says,
/// so every rule can be tested without the hardware.
public struct BoothConditions: Equatable, Sendable {
    /// Every connected display shows the console's picture, so the projector
    /// has no display of its own.
    public var consoleMirrored: Bool
    /// Another app is in front, so the show keys go to it.
    public var inBackground: Bool
    /// Where the Mac's power is coming from.
    public var power: Power
    /// Low Power Mode, which slows the Mac to save energy.
    public var lowPowerMode: Bool
    /// How hard macOS is slowing the Mac to cool it.
    public var heat: Heat
    /// Where the show is, when that isn't the Mac's internal disk.
    public var showDisk: ShowDisk?
    /// Show control that Settings asks for and Backdrop can't have.
    public var showControl: ShowControlProblem?

    public init(consoleMirrored: Bool = false, inBackground: Bool = false, power: Power = .mains,
                lowPowerMode: Bool = false, heat: Heat = .normal, showDisk: ShowDisk? = nil,
                showControl: ShowControlProblem? = nil) {
        self.consoleMirrored = consoleMirrored
        self.inBackground = inBackground
        self.power = power
        self.lowPowerMode = lowPowerMode
        self.heat = heat
        self.showDisk = showDisk
        self.showControl = showControl
    }

    public enum ShowControlProblem: Equatable, Sendable {
        /// Another app has the port Backdrop was to take OSC on.
        case oscPortInUse(Int)
        /// The port can't be used for some other reason.
        case oscPortUnavailable(Int)
    }

    public enum Power: Equatable, Sendable {
        case mains
        /// On a battery or a UPS, with how much is left when that is known.
        case battery(percent: Int?)
    }

    public enum Heat: Equatable, Sendable {
        case normal
        /// macOS is slowing the Mac to cool it.
        case throttled
        /// macOS is slowing it sharply, and will soon do more than that.
        case critical
    }

    public enum ShowDisk: Equatable, Sendable {
        /// A drive plugged into the Mac, by name.
        case external(String)
        /// A server, by name.
        case network(String)
    }
}

/// A warning the console gives, with how much it matters.
public struct BoothWarning: Equatable, Sendable {
    /// Which condition it is.
    public enum ID: Equatable, Sendable {
        case inBackground, mirrored, overheating
        case hot, battery, lowPower, externalDrive, server
        case bannersOnProjector, standInDisplay, inAWindow, disconnected, oscPort
    }

    public enum Tier: Equatable, Sendable {
        /// Stop: the show can't go on as it is. A red band across the console.
        case stop
        /// Caution: worth seeing, not worth stopping for. An amber lamp.
        case caution
    }

    public var id: ID
    public var tier: Tier
    /// The caution lamp's short label. Nil for a stop, which has only its band.
    public var lamp: String?
    /// What the console says, in full.
    public var message: String

    public init(id: ID, tier: Tier, lamp: String?, message: String) {
        self.id = id
        self.tier = tier
        self.lamp = lamp
        self.message = message
    }

    static func stop(_ id: ID, _ message: String) -> BoothWarning {
        BoothWarning(id: id, tier: .stop, lamp: nil, message: message)
    }

    static func caution(_ id: ID, _ lamp: String, _ message: String) -> BoothWarning {
        BoothWarning(id: id, tier: .caution, lamp: lamp, message: message)
    }
}

/// One row of Beginners, the checks before the first GO.
public struct BoothCheck: Equatable, Sendable {
    public enum ID: Equatable, Sendable {
        case projector, mirroring, inFront, power, heat, lowPower, showDisk, msc, osc, cueSheet, armed
    }

    public enum State: Equatable, Sendable {
        case fine, caution, stop
    }

    public var id: ID
    public var state: State
    public var text: String
    /// More, as a tooltip: the warning in full, or the sheet's issues.
    public var detail: String?

    public init(id: ID, state: State, text: String, detail: String? = nil) {
        self.id = id
        self.state = state
        self.text = text
        self.detail = detail
    }
}

/// Show control as Settings has it, for Beginners.
public struct ShowControlStatus: Equatable, Sendable {
    /// The MIDI Show Control device Backdrop answers to, while MSC is on.
    public var mscDevice: Int?
    /// The port Backdrop takes OSC on, while OSC is on. Whether it can is
    /// one of the conditions, `BoothConditions.showControl`.
    public var oscPort: Int?

    public init(mscDevice: Int? = nil, oscPort: Int? = nil) {
        self.mscDevice = mscDevice
        self.oscPort = oscPort
    }
}

extension ArmState {
    /// What the console says of a clip or camera standing by.
    public func text(isFeed: Bool) -> String {
        switch self {
        case .armed: isFeed ? "Camera ready" : "Video armed"
        case .arming: isFeed ? "Camera connecting \u{2014} not armed yet" : "Video loading \u{2014} not armed yet"
        case .failed(let message): isFeed ? "No signal \u{2014} \(message)" : "No clip \u{2014} this cue goes to black"
        }
    }
}

extension BoothConditions {
    /// What the console warns of, most urgent first: stops, then cautions,
    /// each in the order below. Mirroring and the projector are about where
    /// the picture goes, so they speak up in either mode, as does show
    /// control, so it is seen while it is being set up. The rest only matter
    /// during a performance, so they speak up only in show mode, and a
    /// designer working on battery in edit mode isn't nagged.
    public func warnings(mode: ShowController.Mode, projector: ProjectorState) -> [BoothWarning] {
        var said: [BoothWarning] = []
        if consoleMirrored {
            // The projector's own warning would say a display isn't
            // connected, or that there is only one, when the truth is that
            // every display is mirroring the console.
            let then = projector == .windowed(.noSecondDisplay) ? ", then close the projector and open it again" : ""
            said.append(.stop(.mirrored, "The display this window is on is mirrored, so the projector has no display of its own and the audience may be seeing this window. Turn mirroring off in System Settings \u{203A} Displays\(then)."))
        } else if let warning = projector.warning {
            let (id, lamp): (BoothWarning.ID, String) = switch projector {
            case .standIn: (.standInDisplay, "Stand-in display")
            case .windowed: (.inAWindow, "In a window")
            case .waiting: (.disconnected, "Disconnected")
            case .fullScreen, .closed: (.bannersOnProjector, "Banners")
            }
            said.append(.caution(id, lamp, warning))
        }
        switch showControl {
        case nil: break
        case .oscPortInUse(let port):
            said.append(.caution(.oscPort, "OSC port", "Backdrop can\u{2019}t take OSC on port \(port), because another app is using it. Choose another port in Backdrop\u{2019}s Settings, and send to that."))
        case .oscPortUnavailable(let port):
            said.append(.caution(.oscPort, "OSC port", "Backdrop can\u{2019}t take OSC on port \(port). Choose another port in Backdrop\u{2019}s Settings, and send to that."))
        }
        guard mode == .show else { return Self.stopsFirst(said) }

        if inBackground {
            said.append(.stop(.inBackground, Self.inBackgroundMessage))
        }
        if case .battery(let percent) = power {
            let left = percent.map { " (\($0)%)" } ?? ""
            said.append(.caution(.battery, percent.map { "Battery \($0)%" } ?? "Battery",
                                 "This Mac is running on battery\(left). Plug it in: if the battery runs down, the Mac sleeps and the projector goes dark."))
        }
        switch heat {
        case .normal: break
        case .throttled:
            said.append(.caution(.hot, "Hot", Self.hotMessage))
        case .critical:
            said.append(.stop(.overheating, Self.overheatingMessage))
        }
        if lowPowerMode {
            said.append(.caution(.lowPower, "Low Power", Self.lowPowerMessage))
        }
        switch showDisk {
        case nil: break
        case .external(let name):
            said.append(.caution(.externalDrive, "On \(name)", "The show is on \u{201C}\(name)\u{201D}, not this Mac\u{2019}s internal disk. If that drive is unplugged or sleeps, cues can\u{2019}t load their pictures and clips. Copy the show onto this Mac."))
        case .network(let name):
            said.append(.caution(.server, "On a server", "The show is on the server \u{201C}\(name)\u{201D}. If the network drops, cues can\u{2019}t load their pictures and clips. Copy the show onto this Mac."))
        }
        return Self.stopsFirst(said)
    }

    /// Stops before cautions, each kept in the order they were found.
    private static func stopsFirst(_ warnings: [BoothWarning]) -> [BoothWarning] {
        warnings.filter { $0.tier == .stop } + warnings.filter { $0.tier == .caution }
    }

    static let inBackgroundMessage = "Another app is in front, so Space won\u{2019}t fire GO. Click this window to bring Backdrop back."
    static let hotMessage = "This Mac is running hot, and macOS is slowing it down to cool it, so animation and video may stutter. Give it room to breathe."
    static let overheatingMessage = "This Mac is overheating, and macOS is slowing it down sharply, so animation and video will stutter. Give it room to breathe now."
    static let lowPowerMessage = "Low Power Mode is on, which can make animation and video stutter. Turn it off in System Settings."

    /// Beginners: every check before the first GO, in order, each fine or
    /// saying what is wrong in the console's own words.
    ///
    /// - Parameters:
    ///   - issues: The cue sheet's issues, as the console says them.
    ///   - arm: The clip or camera standing by, if one does: its cue number,
    ///     whether it is a camera, and how far it has got.
    public func checklist(mode: ShowController.Mode, projector: ProjectorState, showControl: ShowControlStatus,
                          issues: [String], arm: (number: String, isFeed: Bool, state: ArmState)?) -> [BoothCheck] {
        let warnings = self.warnings(mode: mode, projector: projector)
        func warning(_ ids: BoothWarning.ID...) -> BoothWarning? { warnings.first { ids.contains($0.id) } }
        func state(_ warning: BoothWarning) -> BoothCheck.State { warning.tier == .stop ? .stop : .caution }

        var checks: [BoothCheck] = []
        // The projector: live, or what the lamp says and why.
        if case .closed = projector {
            checks.append(BoothCheck(id: .projector, state: .stop, text: projector.lamp))
        } else if let w = warning(.bannersOnProjector, .standInDisplay, .inAWindow, .disconnected) {
            checks.append(BoothCheck(id: .projector, state: state(w), text: projector.lamp, detail: w.message))
        } else if let display = projector.display {
            checks.append(BoothCheck(id: .projector, state: .fine, text: "Projector live on \(display.identity.name)"))
        } else {
            checks.append(BoothCheck(id: .projector, state: .caution, text: projector.lamp))
        }
        func row(_ id: BoothCheck.ID, _ fine: String, _ warningID: BoothWarning.ID...) {
            if let w = warnings.first(where: { warningID.contains($0.id) }) {
                checks.append(BoothCheck(id: id, state: state(w), text: w.message))
            } else {
                checks.append(BoothCheck(id: id, state: .fine, text: fine))
            }
        }
        row(.mirroring, "Displays aren\u{2019}t mirrored", .mirrored)
        row(.inFront, "Backdrop is in front: Space fires GO", .inBackground)
        row(.power, "On mains power", .battery)
        row(.heat, "Running cool", .hot, .overheating)
        row(.lowPower, "Low Power Mode is off", .lowPower)
        row(.showDisk, "Show is on this Mac\u{2019}s internal disk", .externalDrive, .server)
        if let device = showControl.mscDevice {
            checks.append(BoothCheck(id: .msc, state: .fine, text: "MSC listening as device \(device)"))
        }
        if let port = showControl.oscPort {
            row(.osc, "OSC listening on port \(port)", .oscPort)
        }
        if issues.isEmpty {
            checks.append(BoothCheck(id: .cueSheet, state: .fine, text: "Cue sheet has no issues"))
        } else {
            let count = issues.count == 1 ? "1 issue" : "\(issues.count) issues"
            checks.append(BoothCheck(id: .cueSheet, state: .caution, text: "\(count) in the cue sheet",
                                     detail: issues.joined(separator: "\n")))
        }
        if let arm {
            checks.append(arm.state == .armed
                ? BoothCheck(id: .armed, state: .fine, text: "Cue \(arm.number) armed")
                : BoothCheck(id: .armed, state: .caution, text: arm.state.text(isFeed: arm.isFeed)))
        }
        return checks
    }
}
