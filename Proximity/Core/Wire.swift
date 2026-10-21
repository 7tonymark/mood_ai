import Foundation

enum WireError: Error {
    case truncated
    case invalid
}

/// Builds the compact binary messages sent over Bluetooth and QR, where every byte counts.
struct ByteWriter {
    private(set) var data = Data()

    mutating func u8(_ value: UInt8) {
        data.append(value)
    }

    mutating func u64(_ value: UInt64) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    mutating func raw(_ bytes: Data) {
        data.append(bytes)
    }

    /// Up to 255 bytes, prefixed with their length.
    mutating func short(_ bytes: Data) {
        precondition(bytes.count <= 255, "short fields hold at most 255 bytes")
        u8(UInt8(bytes.count))
        data.append(bytes)
    }
}

struct ByteReader {
    private let data: Data
    private(set) var offset = 0

    init(_ data: Data) {
        // Re-base so indices start at zero even when given a slice.
        self.data = Data(data)
    }

    var isAtEnd: Bool { offset == data.count }

    /// Everything read so far, which is what a trailing signature covers.
    var consumed: Data { data.prefix(offset) }

    mutating func u8() throws -> UInt8 {
        try raw(1)[0]
    }

    mutating func u64() throws -> UInt64 {
        try raw(8).reduce(0) { $0 << 8 | UInt64($1) }
    }

    mutating func raw(_ count: Int) throws -> Data {
        guard count >= 0, data.count - offset >= count else { throw WireError.truncated }
        defer { offset += count }
        return data.subdata(in: offset..<offset + count)
    }

    mutating func short() throws -> Data {
        try raw(Int(u8()))
    }

    mutating func rest() -> Data {
        defer { offset = data.count }
        return data.subdata(in: offset..<data.count)
    }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
