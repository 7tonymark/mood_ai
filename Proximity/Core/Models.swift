import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

enum PlayerColor: Int, Codable, CaseIterable, Identifiable {
    case cyan, magenta, yellow, green, orange, red

    var id: Int { rawValue }
}

/// The name and look a player picks. Signed into their card.
struct Profile: Codable, Equatable {
    static let maxNameLength = 12

    var name: String
    var color: PlayerColor
    var avatar: PixelAvatar

    /// The pixel font only has ASCII glyphs, so names are limited to what it can draw.
    private static let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_.!")

    /// Uppercases and strips what the user typed, as they type it.
    static func sanitize(_ input: String) -> String {
        let cleaned = input.uppercased().filter { allowed.contains($0) }
        return String(cleaned.prefix(maxNameLength))
    }

    static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && sanitize(name) == name
    }
}

/// A player's signed public card: their two public keys plus the name and look friends see.
///
/// Every card in the app is verified. The only ways to get one are `make`, which signs with
/// your own key, and `decode`/`read`, which reject anything not signed by the key inside it.
/// Because a player's id is derived from that key, a card can't impersonate anyone's id.
struct PlayerCard: Hashable {
    static let version: UInt8 = 1
    static let maxEncodedSize = 1 + 32 + 32 + 1 + 8 + 1 + Profile.maxNameLength + 64

    let signingKey: Data
    let agreementKey: Data
    let name: String
    let color: PlayerColor
    let avatar: PixelAvatar
    let signature: Data

    private init(signingKey: Data, agreementKey: Data, profile: Profile, signature: Data) {
        self.signingKey = signingKey
        self.agreementKey = agreementKey
        self.name = profile.name
        self.color = profile.color
        self.avatar = profile.avatar
        self.signature = signature
    }

    var id: UUID { PlayerID.derive(from: signingKey) }

    var profile: Profile { Profile(name: name, color: color, avatar: avatar) }

    var encoded: Data { Self.body(signingKey: signingKey, agreementKey: agreementKey, profile: profile) + signature }

    static func make(identity: Identity, profile: Profile) throws -> PlayerCard {
        guard Profile.isValidName(profile.name) else { throw WireError.invalid }
        let body = Self.body(signingKey: identity.signingPublicKey, agreementKey: identity.agreementPublicKey, profile: profile)
        let signature = try identity.sign(Domain.card + body)
        return PlayerCard(signingKey: identity.signingPublicKey, agreementKey: identity.agreementPublicKey, profile: profile, signature: signature)
    }

    /// Parses a whole message that is exactly one card.
    static func decode(_ data: Data) -> PlayerCard? {
        var reader = ByteReader(data)
        guard let card = try? read(from: &reader), reader.isAtEnd else { return nil }
        return card
    }

    /// Reads one card from the front of a longer message, verifying its signature.
    static func read(from reader: inout ByteReader) throws -> PlayerCard {
        guard try reader.u8() == version else { throw WireError.invalid }
        let signingKey = try reader.raw(32)
        let agreementKey = try reader.raw(32)
        let colorValue = try reader.u8()
        guard let color = PlayerColor(rawValue: Int(colorValue)) else { throw WireError.invalid }
        let avatar = PixelAvatar(bits: try reader.u64())
        guard let name = String(data: try reader.short(), encoding: .utf8), Profile.isValidName(name) else {
            throw WireError.invalid
        }
        let signature = try reader.raw(64)

        let profile = Profile(name: name, color: color, avatar: avatar)
        let body = Self.body(signingKey: signingKey, agreementKey: agreementKey, profile: profile)
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: signingKey)
        guard publicKey.isValidSignature(signature, for: Domain.card + body) else { throw CryptoFailure.badSignature }
        // Make sure the agreement key is a usable key, not just 32 arbitrary bytes.
        _ = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: agreementKey)
        return PlayerCard(signingKey: signingKey, agreementKey: agreementKey, profile: profile, signature: signature)
    }

    private static func body(signingKey: Data, agreementKey: Data, profile: Profile) -> Data {
        var writer = ByteWriter()
        writer.u8(version)
        writer.raw(signingKey)
        writer.raw(agreementKey)
        writer.u8(UInt8(profile.color.rawValue))
        writer.u64(profile.avatar.bits)
        writer.short(Data(profile.name.utf8))
        return writer.data
    }
}

extension PlayerCard: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let card = PlayerCard.decode(try container.decode(Data.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Card is malformed or its signature is invalid")
        }
        self = card
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encoded)
    }
}

/// What you learn about someone when you meet: their verified card and their mailbox.
struct Introduction: Equatable {
    var card: PlayerCard
    var inbox: Data
}

struct Friend: Codable, Identifiable, Hashable {
    enum Method: String, Codable {
        case bluetooth, qr
    }

    /// Their latest card. Its keys are pinned: any later card must be signed by the same key.
    var card: PlayerCard
    /// Their secret mailbox tag.
    var inbox: Data
    var addedAt: Date
    var method: Method

    var id: UUID { card.id }
    var name: String { card.name }
    var color: PlayerColor { card.color }
    var avatar: PixelAvatar { card.avatar }
}

enum DeliveryStatus: String, Codable {
    case sending, sent, failed
}

/// An encrypted photo stored on the server, plus the key to open it.
struct AttachmentRef: Codable, Hashable, Identifiable {
    var recordName: String
    var key: Data
    var width: Int
    var height: Int

    var id: String { recordName }

    static func newRecordName() -> String { "att-" + UUID().uuidString }

    /// Record names come from other people's phones, and are also used as cache file names.
    var isValid: Bool {
        recordName.hasPrefix("att-")
            && UUID(uuidString: String(recordName.dropFirst(4))) != nil
            && key.count == 32
            && (1...10_000).contains(width)
            && (1...10_000).contains(height)
    }
}

/// A photo straight from the camera, already resized and re-encoded (which strips its metadata).
struct CapturedPhoto: Equatable {
    var jpeg: Data
    var width: Int
    var height: Int
}

struct FeedPost: Codable, Identifiable, Equatable {
    var id: UUID
    var author: UUID
    var text: String
    var photo: AttachmentRef?
    var createdAt: Date
    var status: DeliveryStatus
}

struct ChatMessage: Codable, Identifiable, Equatable {
    var id: UUID
    /// The friend this conversation is with.
    var conversation: UUID
    var from: UUID
    var text: String
    var photo: AttachmentRef?
    var sentAt: Date
    var receivedAt: Date
    var status: DeliveryStatus
}
