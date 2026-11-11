import Foundation
import Network

/// Listens for OSC on a UDP port, and hands on each packet with who sent it.
@MainActor
final class OSCInput {
    enum State: Equatable {
        case starting
        case listening
        /// Another app has the port.
        case portInUse
        /// The port can't be used for some other reason, such as being one
        /// only the system may have.
        case unavailable
    }

    let port: Int
    private(set) var state = State.starting {
        didSet { if state != oldValue { onStateChange() } }
    }

    /// A packet, and who sent it: an IP address, or "this Mac".
    var onPacket: (_ packet: [UInt8], _ sender: String) -> Void = { _, _ in }
    var onStateChange: () -> Void = {}

    private let listener: NWListener?
    /// Each sender is a connection of its own, kept while it sends.
    private nonisolated(unsafe) var connections: [ObjectIdentifier: NWConnection] = [:]
    /// Senders kept at once. A sender that uses a new port for every
    /// message would otherwise leave a trail of them.
    private static let mostSenders = 16

    init(port: Int) {
        self.port = port
        guard (1...65535).contains(port), let nwPort = NWEndpoint.Port(rawValue: UInt16(port)),
              let listener = try? NWListener(using: .udp, on: nwPort) else {
            listener = nil
            state = .unavailable
            return
        }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] new in
            MainActor.assumeIsolated { self?.listenerChanged(to: new) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.start(queue: .main)
    }

    deinit {
        listener?.cancel()
        for connection in connections.values { connection.cancel() }
    }

    private func listenerChanged(to new: NWListener.State) {
        switch new {
        case .ready:
            state = .listening
        case .failed(let error), .waiting(let error):
            if case .posix(.EADDRINUSE) = error { state = .portInUse } else { state = .unavailable }
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        if connections.count >= Self.mostSenders, let oldest = connections.first {
            oldest.value.cancel()
            connections.removeValue(forKey: oldest.key)
        }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .failed, .cancelled: self?.connections.removeValue(forKey: id)
                default: break
                }
            }
        }
        connection.start(queue: .main)
        receive(on: connection, from: Self.describe(connection.endpoint))
    }

    private func receive(on connection: NWConnection, from sender: String) {
        connection.receiveMessage { [weak self, weak connection] data, _, _, error in
            MainActor.assumeIsolated {
                guard let self, let connection else { return }
                if let data, !data.isEmpty { self.onPacket([UInt8](data), sender) }
                if error == nil { self.receive(on: connection, from: sender) }
            }
        }
    }

    /// Who sent a packet, as the status line says it.
    static func describe(_ endpoint: NWEndpoint) -> String {
        guard case .hostPort(let host, _) = endpoint else { return "\(endpoint)" }
        switch host {
        case .ipv4(let address):
            return address.isLoopback ? "this Mac" : "\(address)"
        case .ipv6(let address):
            if address.isLoopback { return "this Mac" }
            if let v4 = address.asIPv4 { return v4.isLoopback ? "this Mac" : "\(v4)" }
            return "\(address)"
        case .name(let name, _):
            return name
        @unknown default:
            return "\(host)"
        }
    }

    /// This Mac's IPv4 addresses on its networks: what to type into QLab.
    static func addresses() -> [String] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [] }
        defer { freeifaddrs(first) }
        var found: [String] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            // Self-assigned addresses reach nothing worth naming.
            if !text.hasPrefix("169.254."), !found.contains(text) { found.append(text) }
        }
        return found
    }
}
