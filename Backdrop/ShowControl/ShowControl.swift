import BackdropCore
import BackdropStage
import Foundation
import Observation

/// Cues from other machines in the booth, by MIDI Show Control and OSC, as
/// this Mac's Settings ask. One for the app: whatever comes in goes to the
/// show open, which acts on it only in show mode.
@MainActor
@Observable
final class ShowControl {
    static let shared = ShowControl()
    /// Posted when anything here changes, for what isn't SwiftUI.
    static let didChange = Notification.Name("BackdropShowControlDidChange")

    /// Where commands go, with where they came from for the status line.
    @ObservationIgnored var onCommand: (_ command: RemoteCommand, _ source: String) -> Void = { _, _ in }

    /// The device ID MSC is taken for, while it is taken.
    private(set) var mscDeviceID: Int?
    /// The MIDI sources MSC is listened for on.
    private(set) var midiSources: [String] = []
    /// The port OSC is taken on, while it is taken.
    private(set) var oscPort: Int?
    private(set) var oscState: OSCInput.State?

    @ObservationIgnored private var midi: MIDIInput?
    @ObservationIgnored private var osc: OSCInput?
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?

    /// Show control that is asked for and can't be had, for the console.
    var problem: BoothConditions.ShowControlProblem? {
        guard let oscPort else { return nil }
        switch oscState {
        case .portInUse: return .oscPortInUse(oscPort)
        case .unavailable: return .oscPortUnavailable(oscPort)
        case .starting, .listening, nil: return nil
        }
    }

    /// Follows the Settings, now and whenever they change.
    func start() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.followSettings() }
        }
        followSettings()
    }

    private func followSettings() {
        let defaults = UserDefaults.standard
        configure(msc: defaults.bool(forKey: Preferences.takeMSC) ? defaults.integer(forKey: Preferences.mscDeviceID) : nil,
                  osc: defaults.bool(forKey: Preferences.takeOSC) ? defaults.integer(forKey: Preferences.oscPort) : nil)
    }

    /// Takes MSC for a device ID, and OSC on a port; nil for either turns it
    /// off. Anything already as asked is left alone.
    func configure(msc deviceID: Int?, osc port: Int?) {
        let deviceID = deviceID.map { min(max($0, MSC.deviceIDs.lowerBound), MSC.deviceIDs.upperBound) }
        var changed = false
        if deviceID != mscDeviceID {
            mscDeviceID = deviceID
            changed = true
        }
        if deviceID == nil, midi != nil {
            midi = nil
            midiSources = []
            changed = true
        } else if deviceID != nil, midi == nil, let input = MIDIInput() {
            input.onMessage = { [weak self] message, source in self?.received(msc: message, from: source) }
            input.onSourcesChange = { [weak self, weak input] in
                guard let self, let input else { return }
                self.midiSources = input.sources
                self.announce()
            }
            midi = input
            midiSources = input.sources
            changed = true
        }
        if port != oscPort {
            oscPort = port
            osc = port.map { port in
                let input = OSCInput(port: port)
                input.onPacket = { [weak self] packet, sender in self?.received(osc: packet, from: sender) }
                input.onStateChange = { [weak self, weak input] in
                    guard let self, let input else { return }
                    self.oscState = input.state
                    self.announce()
                }
                return input
            }
            oscState = osc?.state
            changed = true
        }
        if changed { announce() }
    }

    private func announce() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private func received(msc message: [UInt8], from source: String) {
        guard let deviceID = mscDeviceID, let command = MSC.command(in: message, deviceID: deviceID) else { return }
        onCommand(command, "MIDI Show Control from \(source)")
    }

    private func received(osc packet: [UInt8], from sender: String) {
        for message in OSCMessage.parse(packet) ?? [] {
            if let command = RemoteCommand(osc: message) { onCommand(command, "OSC from \(sender)") }
        }
    }
}
