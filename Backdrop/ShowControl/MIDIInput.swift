import BackdropCore
import CoreMIDI
import Foundation
import Synchronization

/// Every MIDI source on the Mac, listened to for system exclusive messages:
/// interfaces and USB devices, Network MIDI sessions, and other apps'
/// virtual sources, such as QLab's. Sources are picked up as they come.
@MainActor
final class MIDIInput {
    /// A complete system exclusive message, without its F0 and F7, and the
    /// name of the source it came from.
    var onMessage: (_ message: [UInt8], _ source: String) -> Void = { _, _ in }
    /// The sources changed.
    var onSourcesChange: () -> Void = {}

    /// The sources listened to, by name.
    private(set) var sources: [String] = []

    private nonisolated(unsafe) var client = MIDIClientRef()
    private nonisolated(unsafe) var port = MIDIPortRef()
    private var connected: Set<MIDIEndpointRef> = []
    private let assemblers = Assemblers()

    /// Messages in progress, by source. CoreMIDI delivers on a thread of its
    /// own, and a message can arrive over several deliveries.
    final class Assemblers: Sendable {
        private let bySource = Mutex<[MIDIEndpointRef: SysEx7Assembler]>([:])

        func receive(_ words: some Collection<UInt32>, from source: MIDIEndpointRef) -> [[UInt8]] {
            bySource.withLock { $0[source, default: SysEx7Assembler()].receive(words) }
        }
    }

    /// Nil if CoreMIDI won't have Backdrop as a client.
    ///
    /// CoreMIDI calls both blocks on threads of its own, so they are marked
    /// Sendable: left to inference they would be taken as the main actor's,
    /// and trap when called anywhere else. Each hops to the main thread
    /// before touching anything of the app's.
    init?() {
        let setupChanged = MIDIClientCreateWithBlock("Backdrop" as CFString, &client) { @Sendable [weak self] notification in
            guard notification.pointee.messageID == .msgSetupChanged else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.connectSources() } }
        }
        guard setupChanged == noErr else { return nil }
        let assemblers = self.assemblers
        let created = MIDIInputPortCreateWithProtocol(client, "Backdrop" as CFString, ._1_0, &port) { @Sendable [weak self] list, refCon in
            let source = MIDIEndpointRef(truncatingIfNeeded: Int(bitPattern: refCon))
            var messages: [[UInt8]] = []
            for packet in list.unsafeSequence() {
                messages += assemblers.receive(packet.words(), from: source)
            }
            guard !messages.isEmpty else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.deliver(messages, from: source) }
            }
        }
        guard created == noErr else {
            MIDIClientDispose(client)
            return nil
        }
        connectSources()
    }

    deinit {
        MIDIPortDispose(port)
        MIDIClientDispose(client)
    }

    /// Connects any source not yet connected. Sources that have gone need
    /// nothing: CoreMIDI drops them.
    private func connectSources() {
        let current = (0..<MIDIGetNumberOfSources()).map(MIDIGetSource).filter { $0 != 0 }
        for source in current where !connected.contains(source) {
            // The source rides along with each delivery, to keep its
            // messages apart from other sources'.
            MIDIPortConnectSource(port, source, UnsafeMutableRawPointer(bitPattern: UInt(source)))
        }
        connected = Set(current)
        let names = current.map(Self.name(of:))
        if names != sources {
            sources = names
            onSourcesChange()
        }
    }

    private func deliver(_ messages: [[UInt8]], from source: MIDIEndpointRef) {
        let name = Self.name(of: source)
        for message in messages { onMessage(message, name) }
    }

    static func name(of endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == noErr, let name else {
            return "a MIDI source"
        }
        return name.takeRetainedValue() as String
    }
}
