import AppKit
import BackdropCore
import BackdropStage
import SwiftUI

/// Where each of Backdrop's settings is kept in the user defaults.
enum Preferences {
    /// Open the most recent show on launch. On unless turned off.
    static let reopenLastShow = "ReopenLastShow"
    /// What the projector does when a show's display isn't connected: a
    /// `MissingDisplay` raw value. A window unless set otherwise.
    static let missingDisplay = "MissingProjectorDisplay"
    /// Listen for cues from MIDI Show Control. Off unless turned on.
    static let takeMSC = "TakeMSC"
    /// The device ID MSC is taken for. 1 unless set otherwise.
    static let mscDeviceID = "MSCDeviceID"
    /// Listen for cues from OSC. Off unless turned on.
    static let takeOSC = "TakeOSC"
    /// The UDP port OSC is taken on. 53100 unless set otherwise: clear of
    /// QLab's own 53000 and 53001, in case it runs on the same Mac.
    static let oscPort = "OSCPort"
}

/// Backdrop's settings. Almost nothing belongs here: everything that varies
/// by production is in the show document, so it travels with the show. What
/// is left belongs to the Mac.
///
/// The window is AppKit's, as every window in Backdrop is; what is in it is
/// SwiftUI. Each control reads and writes its setting in the user defaults
/// directly, so the window always shows what is set, with nothing to refresh.
@MainActor
final class PreferencesWindowController: NSWindowController {
    init() {
        let content = NSHostingController(rootView: PreferencesView())
        // Turning show control on adds lines, and the window grows to fit.
        content.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: content)
        window.styleMask = [.titled, .closable]
        window.setContentSize(content.view.fittingSize)
        window.title = "Settings"
        window.isRestorable = false
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct PreferencesView: View {
    // The defaults here only show until the app registers its own, at launch.
    @AppStorage(Preferences.reopenLastShow) private var reopenLastShow = true
    @AppStorage(Preferences.missingDisplay) private var missingDisplay = MissingDisplay.window
    @AppStorage(Preferences.takeMSC) private var takeMSC = false
    @AppStorage(Preferences.mscDeviceID) private var mscDeviceID = 1
    @AppStorage(Preferences.takeOSC) private var takeOSC = false
    @AppStorage(Preferences.oscPort) private var oscPort = 53100
    private let control = ShowControl.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $reopenLastShow) {
                    Text("Reopen the last show when Backdrop starts")
                    Text("So the first thing to do on the night is press GO, not find a file.")
                }
            }

            Section {
                Picker("When a show\u{2019}s projector display isn\u{2019}t connected", selection: $missingDisplay) {
                    Text("Open the projector in a window on this Mac\u{2019}s own display").tag(MissingDisplay.window)
                    Text("Use another connected display until it returns").tag(MissingDisplay.anotherDisplay)
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text("Either way, the projector moves to the show\u{2019}s display as soon as it is connected.")
            }

            Section {
                Toggle(isOn: $takeMSC) {
                    Text("Listen for cues from MIDI Show Control")
                    Text("Sent by QLab\u{2019}s MIDI cues, a lighting desk, or anything else that sends MSC, by cable, USB or Network MIDI.")
                }
                LabeledContent("Device ID") {
                    Stepper(value: $mscDeviceID, in: MSC.deviceIDs) {
                        Text("\(mscDeviceID)").monospacedDigit()
                    }
                }
                .disabled(!takeMSC)
                if takeMSC {
                    Text(mscStatus).foregroundStyle(.secondary)
                }
            } header: {
                Text("Show control")
            } footer: {
                Text("GO fires the cue standing by, or the cue it names. LOAD stands a cue by. ALL OFF blacks out, and RESTORE brings the picture back. Backdrop answers to its own device ID and to All Devices, in the video command formats and All Types.")
            }

            Section {
                Toggle(isOn: $takeOSC) {
                    Text("Listen for cues from OSC")
                    Text("Sent by QLab\u{2019}s Network cues, a lighting desk, or a remote app.")
                }
                TextField("Port", value: $oscPort, format: .number.grouping(.never))
                    .disabled(!takeOSC)
                if takeOSC {
                    Text(oscStatus).foregroundStyle(.secondary)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    // A table, so no address breaks at a slash.
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                        ForEach(Self.oscAddresses, id: \.address) { row in
                            GridRow {
                                Text(row.address).monospaced()
                                Text(row.meaning)
                            }
                        }
                    }
                    Text("Backdrop only acts on cues from other machines in show mode.")
                    Text("These belong to this Mac. Everything else is kept with the show.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }

    private static let oscAddresses: [(address: String, meaning: String)] = [
        ("/backdrop/go", "fires the cue standing by"),
        ("/backdrop/go/12", "fires cue 12"),
        ("/backdrop/standby/12", "stands cue 12 by"),
        ("/backdrop/blackout/on", "blacks out"),
        ("/backdrop/blackout/off", "brings the picture back"),
    ]

    private var mscStatus: String {
        guard !control.midiSources.isEmpty else {
            return "No MIDI sources are connected. For Network MIDI, turn on a session in Audio MIDI Setup \u{203A} MIDI Network Setup."
        }
        return "Listening on \(Self.list(control.midiSources, joinedBy: "and"))."
    }

    /// Everything QLab needs to know to send here.
    private var oscStatus: String {
        let port = control.oscPort ?? oscPort
        switch control.oscState {
        case .portInUse: return "Another app is using port \(port). Choose another."
        case .unavailable: return "Port \(port) can\u{2019}t be used. Choose another."
        case .starting, nil: return "Starting\u{2026}"
        case .listening:
            let addresses = OSCInput.addresses()
            guard !addresses.isEmpty else { return "Listening on port \(port), but this Mac isn\u{2019}t on a network." }
            return "Send to \(Self.list(addresses, joinedBy: "or")), port \(port)."
        }
    }

    private static func list(_ items: [String], joinedBy word: String) -> String {
        guard let last = items.last else { return "" }
        return items.count == 1 ? last : items.dropLast().joined(separator: ", ") + " \(word) " + last
    }
}
