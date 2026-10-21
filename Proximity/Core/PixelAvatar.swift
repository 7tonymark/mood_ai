import Foundation

/// An 8×8 one-colour sprite, packed into 64 bits so it fits easily in a Bluetooth packet or QR code.
struct PixelAvatar: Hashable {
    static let size = 8

    var bits: UInt64

    init(bits: UInt64 = 0) {
        self.bits = bits
    }

    /// Builds a sprite from 8 rows of 8 characters, where "#" is a lit pixel.
    init(rows: [String]) {
        self.init()
        for (y, row) in rows.prefix(Self.size).enumerated() {
            for (x, char) in row.prefix(Self.size).enumerated() where char == "#" {
                self[x, y] = true
            }
        }
    }

    subscript(x: Int, y: Int) -> Bool {
        get { bits & Self.mask(x, y) != 0 }
        set {
            if newValue {
                bits |= Self.mask(x, y)
            } else {
                bits &= ~Self.mask(x, y)
            }
        }
    }

    var isEmpty: Bool { bits == 0 }

    private static func mask(_ x: Int, _ y: Int) -> UInt64 {
        1 << UInt64(y * size + x)
    }

    /// A random left/right-symmetric sprite, which reads as a little "space invader".
    static func random<G: RandomNumberGenerator>(using rng: inout G) -> PixelAvatar {
        var avatar = PixelAvatar()
        for y in 0..<size {
            for x in 0..<(size / 2) {
                let on = Bool.random(using: &rng)
                avatar[x, y] = on
                avatar[size - 1 - x, y] = on
            }
        }
        return avatar.isEmpty ? .invader : avatar
    }

    static func random() -> PixelAvatar {
        var rng = SystemRandomNumberGenerator()
        return random(using: &rng)
    }

    static let invader = PixelAvatar(rows: [
        "..#..#..",
        "...##...",
        "..####..",
        ".##..##.",
        "########",
        "#.####.#",
        "#.#..#.#",
        "...##...",
    ])
}

// MARK: - Hex encoding

extension PixelAvatar {
    var hex: String {
        let digits = String(bits, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }

    init?(hex: String) {
        guard hex.count == 16, let bits = UInt64(hex, radix: 16) else { return nil }
        self.init(bits: bits)
    }
}

extension PixelAvatar: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let avatar = PixelAvatar(hex: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Avatar must be 16 hex digits")
        }
        self = avatar
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
