import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Labels mixed into every signature and key derivation, so something signed for one purpose
/// can never be passed off as another (an "accept" can't be replayed as a post, and so on).
enum Domain {
    static let playerID = Data("PRXY-ID-v1".utf8)
    static let card = Data("PRXY-CARD-v1".utf8)
    static let accept = Data("PRXY-ACCEPT-v1".utf8)
    static let qr = Data("PRXY-QR-v1".utf8)
    static let envelope = Data("PRXY-ENV-v1".utf8)
    static let inboxBox = Data("PRXY-INBOX-BOX-v1".utf8)
    static let envelopeBox = Data("PRXY-ENV-BOX-v1".utf8)
}

enum CryptoFailure: Error {
    case malformed
    case badSignature
}

/// A player's long-term keys.
///
/// The private keys never leave the device except through iCloud Keychain, which Apple
/// end-to-end encrypts between the owner's own devices. That's what lets a player keep
/// their identity, and their friends, on a replacement phone.
struct Identity {
    /// Ed25519: signs cards, accepts and every envelope.
    let signingKey: Curve25519.Signing.PrivateKey
    /// X25519: friends encrypt to this.
    let agreementKey: Curve25519.KeyAgreement.PrivateKey
    /// Secret mailbox tag that friends deliver to. Only ever handed to people you add in person.
    let inbox: Data
    /// Secret mailbox tag for copies of what you send, used to restore history on a new phone.
    let archive: Data

    var id: UUID { PlayerID.derive(from: signingPublicKey) }
    var signingPublicKey: Data { signingKey.publicKey.rawRepresentation }
    var agreementPublicKey: Data { agreementKey.publicKey.rawRepresentation }

    static func generate() -> Identity {
        Identity(
            signingKey: Curve25519.Signing.PrivateKey(),
            agreementKey: Curve25519.KeyAgreement.PrivateKey(),
            inbox: Random.bytes(16),
            archive: Random.bytes(16)
        )
    }

    func sign(_ message: Data) throws -> Data {
        try signingKey.signature(for: message)
    }
}

extension Identity {
    private struct Stored: Codable {
        var signing: Data
        var agreement: Data
        var inbox: Data
        var archive: Data
    }

    func exported() throws -> Data {
        try JSONEncoder().encode(Stored(
            signing: signingKey.rawRepresentation,
            agreement: agreementKey.rawRepresentation,
            inbox: inbox,
            archive: archive
        ))
    }

    init(exported data: Data) throws {
        let stored = try JSONDecoder().decode(Stored.self, from: data)
        guard stored.inbox.count == 16, stored.archive.count == 16 else { throw CryptoFailure.malformed }
        self.init(
            signingKey: try Curve25519.Signing.PrivateKey(rawRepresentation: stored.signing),
            agreementKey: try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: stored.agreement),
            inbox: stored.inbox,
            archive: stored.archive
        )
    }
}

enum PlayerID {
    /// Player ids are derived from the signing key, so nobody can claim someone else's id
    /// without also holding their private key.
    static func derive(from signingPublicKey: Data) -> UUID {
        let digest = Array(SHA256.hash(data: Domain.playerID + signingPublicKey))
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]
        ))
    }
}

/// Public-key encryption to someone's agreement key: ephemeral X25519, HKDF-SHA256, ChaCha20-Poly1305.
/// The box says nothing about who made it; senders prove who they are with a signature inside.
enum AnonymousBox {
    /// Ephemeral public key + nonce + tag.
    static let overhead = 32 + 12 + 16

    static func seal(_ plaintext: Data, to recipientPublicKey: Data, domain: Data) throws -> Data {
        let recipient = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientPublicKey)
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let secret = try ephemeral.sharedSecretFromKeyAgreement(with: recipient)
        let ephemeralPublicKey = ephemeral.publicKey.rawRepresentation
        let key = derive(secret, ephemeral: ephemeralPublicKey, recipient: recipientPublicKey, domain: domain)
        let sealed = try ChaChaPoly.seal(plaintext, using: key)
        return ephemeralPublicKey + sealed.combined
    }

    static func open(_ box: Data, with privateKey: Curve25519.KeyAgreement.PrivateKey, domain: Data) throws -> Data {
        let box = Data(box)
        guard box.count >= overhead else { throw CryptoFailure.malformed }
        let ephemeralPublicKey = Data(box.prefix(32))
        let ephemeral = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralPublicKey)
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: ephemeral)
        let key = derive(secret, ephemeral: ephemeralPublicKey, recipient: privateKey.publicKey.rawRepresentation, domain: domain)
        let sealed = try ChaChaPoly.SealedBox(combined: Data(box.dropFirst(32)))
        return try ChaChaPoly.open(sealed, using: key)
    }

    private static func derive(_ secret: SharedSecret, ephemeral: Data, recipient: Data, domain: Data) -> SymmetricKey {
        secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: ephemeral + recipient,
            sharedInfo: domain,
            outputByteCount: 32
        )
    }
}

/// Photos are encrypted once with a random key; that key then travels inside each envelope.
enum AttachmentCrypto {
    static func encrypt(_ plaintext: Data) throws -> (ciphertext: Data, key: Data) {
        let key = SymmetricKey(size: .bits256)
        let sealed = try ChaChaPoly.seal(plaintext, using: key)
        return (sealed.combined, key.withUnsafeBytes { Data($0) })
    }

    static func decrypt(_ ciphertext: Data, key: Data) throws -> Data {
        guard key.count == 32 else { throw CryptoFailure.malformed }
        let sealed = try ChaChaPoly.SealedBox(combined: ciphertext)
        return try ChaChaPoly.open(sealed, using: SymmetricKey(data: key))
    }
}

enum Random {
    static func bytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

extension UUID {
    var bytes: Data {
        withUnsafeBytes(of: uuid) { Data($0) }
    }
}

extension Data {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
