import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Everything friends send each other travels as an envelope: signed by the sender, sealed to
/// one recipient's key, and dropped in that recipient's mailbox on the server. The server only
/// ever sees a mailbox tag and an opaque blob, never who wrote it or what it says.
struct Envelope: Codable, Equatable {
    enum Body: Codable, Equatable {
        case post(PostBody)
        case deletePost(UUID)
        case chat(ChatBody)
        /// A friend changed their name or look. Must be signed by the same key as before.
        case profile(PlayerCard)
        /// A friend removed you. Your app quietly removes them too.
        case unfriend
    }

    var from: UUID
    var to: UUID
    var sentAt: Date
    var body: Body
}

struct PostBody: Codable, Equatable {
    var id: UUID
    var text: String
    var photo: AttachmentRef?
}

struct ChatBody: Codable, Equatable {
    var id: UUID
    /// Who the message is for. For the copy a sender keeps, this is the other person.
    var peer: UUID
    var text: String
    var photo: AttachmentRef?
}

enum EnvelopeCodec {
    static let version: UInt8 = 1

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()

    static func seal(_ envelope: Envelope, identity: Identity, recipientKey: Data) throws -> Data {
        let payload = try encoder.encode(envelope)
        var writer = ByteWriter()
        writer.u8(version)
        writer.raw(try identity.sign(Domain.envelope + payload))
        writer.raw(payload)
        return try AnonymousBox.seal(writer.data, to: recipientKey, domain: Domain.envelopeBox)
    }

    /// Opens an envelope addressed to me. `signingKey` returns the pinned key for the people I
    /// accept mail from (friends, and myself); anything else, or anything forged, comes back nil.
    static func open(_ sealed: Data, identity: Identity, signingKey: (UUID) -> Data?) -> Envelope? {
        guard let inner = try? AnonymousBox.open(sealed, with: identity.agreementKey, domain: Domain.envelopeBox) else {
            return nil
        }
        var reader = ByteReader(inner)
        guard let version = try? reader.u8(), version == Self.version,
              let signature = try? reader.raw(64) else { return nil }
        let payload = reader.rest()
        guard let envelope = try? decoder.decode(Envelope.self, from: payload),
              envelope.to == identity.id,
              let keyData = signingKey(envelope.from),
              let signer = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              signer.isValidSignature(signature, for: Domain.envelope + payload) else { return nil }
        return envelope
    }
}
