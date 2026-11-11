import Foundation

/// An Open Sound Control message: an address and its arguments, as QLab's
/// Network cues, lighting desks and remote apps send them over UDP.
public struct OSCMessage: Equatable, Sendable {
    public var address: String
    public var arguments: [Argument]

    public init(_ address: String, _ arguments: [Argument] = []) {
        self.address = address
        self.arguments = arguments
    }

    public enum Argument: Equatable, Sendable {
        case int(Int)
        case float(Float)
        case double(Double)
        case string(String)
        case bool(Bool)
        /// Anything Backdrop has no use for: a blob, a time tag, a colour.
        case other
    }

    /// The messages in a packet: the one it is, or every one in a bundle,
    /// however deeply bundled. Nil when the packet isn't OSC.
    public static func parse(_ packet: [UInt8]) -> [OSCMessage]? {
        var reader = Reader(bytes: packet[...])
        return reader.packet()
    }

    /// The message as bytes to send, with its arguments' type tags.
    public func encoded() -> [UInt8] {
        var bytes = Self.padded(address)
        var tags = ","
        var data: [UInt8] = []
        for argument in arguments {
            switch argument {
            case .int(let i):
                tags += "i"
                data += Self.bigEndian(UInt32(bitPattern: Int32(truncatingIfNeeded: i)))
            case .float(let f):
                tags += "f"
                data += Self.bigEndian(f.bitPattern)
            case .double(let d):
                tags += "d"
                data += Self.bigEndian(UInt32(truncatingIfNeeded: d.bitPattern >> 32))
                data += Self.bigEndian(UInt32(truncatingIfNeeded: d.bitPattern))
            case .string(let s):
                tags += "s"
                data += Self.padded(s)
            case .bool(let b):
                tags += b ? "T" : "F"
            case .other:
                tags += "N"
            }
        }
        bytes += Self.padded(tags)
        bytes += data
        return bytes
    }

    /// A string with its terminating zero, padded to a multiple of four.
    private static func padded(_ s: String) -> [UInt8] {
        var bytes = Array(s.utf8) + [0]
        while bytes.count % 4 != 0 { bytes.append(0) }
        return bytes
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    /// Reads one packet. Every read checks there is enough left, so a
    /// truncated or garbled packet is refused rather than misread.
    private struct Reader {
        var bytes: ArraySlice<UInt8>

        mutating func packet() -> [OSCMessage]? {
            if bytes.first == UInt8(ascii: "#") { return bundle() }
            return message().map { [$0] }
        }

        /// `#bundle`, a time tag, then elements, each preceded by its size.
        /// The time tag is ignored: everything is done as it arrives.
        private mutating func bundle() -> [OSCMessage]? {
            guard string() == "#bundle", take(8) != nil else { return nil }
            var messages: [OSCMessage] = []
            while !bytes.isEmpty {
                guard let size = int32(), size >= 0, let element = take(Int(size)) else { return nil }
                var inner = Reader(bytes: element)
                guard let found = inner.packet() else { return nil }
                messages += found
            }
            return messages
        }

        private mutating func message() -> OSCMessage? {
            guard let address = string(), address.hasPrefix("/") else { return nil }
            // A message from before type tags has none, and no arguments
            // Backdrop could read.
            guard !bytes.isEmpty else { return OSCMessage(address) }
            guard let tags = string(), tags.hasPrefix(",") else { return OSCMessage(address) }
            var arguments: [Argument] = []
            for tag in tags.dropFirst() {
                switch tag {
                case "i": guard let v = int32() else { return nil }; arguments.append(.int(Int(v)))
                case "f": guard let v = uint32() else { return nil }; arguments.append(.float(Float(bitPattern: v)))
                case "h": guard let hi = uint32(), let lo = uint32() else { return nil }
                    arguments.append(.int(Int(Int64(bitPattern: UInt64(hi) << 32 | UInt64(lo)))))
                case "d": guard let hi = uint32(), let lo = uint32() else { return nil }
                    arguments.append(.double(Double(bitPattern: UInt64(hi) << 32 | UInt64(lo))))
                case "s", "S": guard let v = string() else { return nil }; arguments.append(.string(v))
                case "T": arguments.append(.bool(true))
                case "F": arguments.append(.bool(false))
                case "N", "I": arguments.append(.other)
                case "c", "r", "m": guard take(4) != nil else { return nil }; arguments.append(.other)
                case "t": guard take(8) != nil else { return nil }; arguments.append(.other)
                case "b":
                    guard let size = int32(), size >= 0, take(Int(size)) != nil else { return nil }
                    _ = take((4 - Int(size) % 4) % 4)
                    arguments.append(.other)
                case "[", "]": continue
                default: return nil
                }
            }
            return OSCMessage(address, arguments)
        }

        private mutating func take(_ count: Int) -> ArraySlice<UInt8>? {
            guard count >= 0, bytes.count >= count else { return nil }
            let taken = bytes.prefix(count)
            bytes = bytes.dropFirst(count)
            return taken
        }

        private mutating func uint32() -> UInt32? {
            take(4).map { $0.reduce(0) { $0 << 8 | UInt32($1) } }
        }

        private mutating func int32() -> Int32? {
            uint32().map { Int32(bitPattern: $0) }
        }

        /// A zero-terminated string padded to a multiple of four.
        private mutating func string() -> String? {
            guard let end = bytes.firstIndex(of: 0) else { return nil }
            let text = String(decoding: bytes[bytes.startIndex..<end], as: UTF8.self)
            let length = end - bytes.startIndex + 1
            guard take(length + (4 - length % 4) % 4) != nil else { return nil }
            return text
        }
    }
}
