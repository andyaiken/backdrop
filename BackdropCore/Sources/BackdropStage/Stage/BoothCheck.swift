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

extension BoothConditions {
    /// What the console warns of, most urgent first, the projector's own
    /// warning among them. Mirroring and the projector are about where the
    /// picture goes, so they speak up in either mode. The rest only matter
    /// during a performance, so they speak up only in show mode, and a
    /// designer working on battery in edit mode isn't nagged.
    public func warnings(mode: ShowController.Mode, projector: ProjectorState) -> [String] {
        var said: [String] = []
        if consoleMirrored {
            // The projector's own warning would say a display isn't
            // connected, or that there is only one, when the truth is that
            // every display is mirroring the console.
            let then = projector == .windowed(.noSecondDisplay) ? ", then close the projector and open it again" : ""
            said.append("The display this window is on is mirrored, so the projector has no display of its own and the audience may be seeing this window. Turn mirroring off in System Settings \u{203A} Displays\(then).")
        } else if let warning = projector.warning {
            said.append(warning)
        }
        // In either mode, so it is seen while show control is being set up.
        switch showControl {
        case nil: break
        case .oscPortInUse(let port):
            said.append("Backdrop can\u{2019}t take OSC on port \(port), because another app is using it. Choose another port in Backdrop\u{2019}s Settings, and send to that.")
        case .oscPortUnavailable(let port):
            said.append("Backdrop can\u{2019}t take OSC on port \(port). Choose another port in Backdrop\u{2019}s Settings, and send to that.")
        }
        guard mode == .show else { return said }

        if inBackground {
            said.append("Another app is in front, so Space won\u{2019}t fire GO. Click this window to bring Backdrop back.")
        }
        if case .battery(let percent) = power {
            let left = percent.map { " (\($0)%)" } ?? ""
            said.append("This Mac is running on battery\(left). Plug it in: if the battery runs down, the Mac sleeps and the projector goes dark.")
        }
        switch heat {
        case .normal: break
        case .throttled:
            said.append("This Mac is running hot, and macOS is slowing it down to cool it, so animation and video may stutter. Give it room to breathe.")
        case .critical:
            said.append("This Mac is overheating, and macOS is slowing it down sharply, so animation and video will stutter. Give it room to breathe now.")
        }
        if lowPowerMode {
            said.append("Low Power Mode is on, which can make animation and video stutter. Turn it off in System Settings.")
        }
        switch showDisk {
        case nil: break
        case .external(let name):
            said.append("The show is on \u{201C}\(name)\u{201D}, not this Mac\u{2019}s internal disk. If that drive is unplugged or sleeps, cues can\u{2019}t load their pictures and clips. Copy the show onto this Mac.")
        case .network(let name):
            said.append("The show is on the server \u{201C}\(name)\u{201D}. If the network drops, cues can\u{2019}t load their pictures and clips. Copy the show onto this Mac.")
        }
        return said
    }
}
