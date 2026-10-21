import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// What a phone on the "Add player" screen serves to anyone who connects: its signed card and
/// a fresh random nonce. Accepting someone means signing *their* nonce, which proves you hold
/// your private key right now, so a recorded acceptance can't be replayed later or elsewhere.
struct Hello: Equatable {
    var card: PlayerCard
    var nonce: Data

    var encoded: Data { card.encoded + nonce }

    static func newNonce() -> Data { Random.bytes(16) }

    static func decode(_ data: Data) -> Hello? {
        var reader = ByteReader(data)
        guard let card = try? PlayerCard.read(from: &reader),
              let nonce = try? reader.raw(16),
              reader.isAtEnd else { return nil }
        return Hello(card: card, nonce: nonce)
    }
}

/// "I accept you": my card, my inbox sealed so only you can read it, your id and your nonce,
/// all signed with my key. About 330 bytes, well inside one Bluetooth attribute (512 bytes).
enum AcceptMessage {
    static let version: UInt8 = 1

    static func make(identity: Identity, card: PlayerCard, to peer: Hello) throws -> Data {
        var writer = ByteWriter()
        writer.u8(version)
        writer.raw(card.encoded)
        writer.raw(peer.card.id.bytes)
        writer.raw(peer.nonce)
        writer.short(try AnonymousBox.seal(identity.inbox, to: peer.card.agreementKey, domain: Domain.inboxBox))
        writer.raw(try identity.sign(Domain.accept + writer.data))
        return writer.data
    }

    /// Verifies an acceptance addressed to me, for my current nonce, and returns who sent it.
    static func open(_ data: Data, identity: Identity, myNonce: Data) -> Introduction? {
        var reader = ByteReader(data)
        guard let version = try? reader.u8(), version == Self.version,
              let card = try? PlayerCard.read(from: &reader),
              let recipient = try? reader.raw(16), recipient == identity.id.bytes,
              let nonce = try? reader.raw(16), nonce == myNonce,
              let sealedInbox = try? reader.short() else { return nil }
        let signed = reader.consumed
        guard let signature = try? reader.raw(64), reader.isAtEnd,
              let signer = try? Curve25519.Signing.PublicKey(rawRepresentation: card.signingKey),
              signer.isValidSignature(signature, for: Domain.accept + signed),
              let inbox = try? AnonymousBox.open(sealedInbox, with: identity.agreementKey, domain: Domain.inboxBox),
              inbox.count == 16 else { return nil }
        return Introduction(card: card, inbox: inbox)
    }
}

/// The rules of a Bluetooth friend request, kept free of CoreBluetooth so they can be unit tested.
///
/// A friendship only completes when *both* players accepted each other: I sent my acceptance
/// (`iAccepted`) and theirs reached me (`theirInbox`, which only arrives inside an acceptance).
struct HandshakeLedger {
    struct Entry: Equatable {
        var card: PlayerCard
        var theirInbox: Data?
        var iAccepted = false
        var completed = false

        var theyAccepted: Bool { theirInbox != nil }
    }

    private(set) var entries: [UUID: Entry] = [:]

    mutating func discovered(_ card: PlayerCard) {
        if entries[card.id] == nil {
            entries[card.id] = Entry(card: card)
        } else {
            entries[card.id]?.card = card
        }
    }

    /// Returns the new friend when this acceptance completes the friendship.
    @discardableResult
    mutating func markIAccepted(_ id: UUID) -> Introduction? {
        guard entries[id] != nil else { return nil }
        entries[id]?.iAccepted = true
        return completeIfReady(id)
    }

    /// Returns the new friend when this acceptance completes the friendship.
    @discardableResult
    mutating func markTheyAccepted(_ introduction: Introduction) -> Introduction? {
        discovered(introduction.card)
        entries[introduction.card.id]?.theirInbox = introduction.inbox
        return completeIfReady(introduction.card.id)
    }

    private mutating func completeIfReady(_ id: UUID) -> Introduction? {
        guard let entry = entries[id], entry.iAccepted, let inbox = entry.theirInbox, !entry.completed else { return nil }
        entries[id]?.completed = true
        return Introduction(card: entry.card, inbox: inbox)
    }
}
