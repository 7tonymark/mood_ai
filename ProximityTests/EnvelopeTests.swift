import XCTest
#if canImport(ProximityCore)
@testable import ProximityCore
#else
@testable import Proximity
#endif

final class QRPayloadTests: XCTestCase {
    private let identity = Identity.generate()
    private lazy var card = makeCard(name: "SAM", identity: identity)

    func testRoundTripWithinWindow() throws {
        let now = Date()
        let code = try QRPayload.make(identity: identity, card: card, now: now)
        let introduction = try QRPayload.parse(code, now: now).get()
        XCTAssertEqual(introduction.card, card)
        XCTAssertEqual(introduction.inbox, identity.inbox)
    }

    func testExpires() throws {
        let now = Date()
        let code = try QRPayload.make(identity: identity, card: card, now: now)
        let later = now.addingTimeInterval(QRPayload.window + QRPayload.grace + 1)
        XCTAssertEqual(QRPayload.parse(code, now: later).failure, .expired)
    }

    func testExpiryCannotBeEdited() throws {
        let code = try QRPayload.make(identity: identity, card: card)
        var data = try XCTUnwrap(Base64URL.decode(String(code.dropFirst(QRPayload.prefix.count))))
        // The expiry sits right after the card; bump it by a minute.
        let expiryIndex = 1 + card.encoded.count + 6
        data[expiryIndex] = data[expiryIndex] &+ 1
        XCTAssertEqual(QRPayload.parse(QRPayload.prefix + Base64URL.encode(data)).failure, .malformed)
    }

    func testRejectsSignedCodesClaimingToLiveTooLong() throws {
        // Even a correctly signed code (from a modified app) can't stay valid for an hour.
        var writer = ByteWriter()
        writer.u8(QRPayload.version)
        writer.raw(card.encoded)
        writer.u64(UInt64(Date().timeIntervalSince1970 + 3600))
        writer.raw(identity.inbox)
        writer.raw(try identity.sign(Domain.qr + writer.data))
        XCTAssertEqual(QRPayload.parse(QRPayload.prefix + Base64URL.encode(writer.data)).failure, .expired)
    }

    func testRejectsForeignCodes() {
        XCTAssertEqual(QRPayload.parse("https://example.com").failure, .notOurs)
        XCTAssertEqual(QRPayload.parse("PRXY2:!!!").failure, .malformed)
    }
}

final class EnvelopeTests: XCTestCase {
    private let alice = Identity.generate()
    private let bob = Identity.generate()

    private func envelope(from: Identity, to: Identity, text: String = "hello") -> Envelope {
        Envelope(from: from.id, to: to.id, sentAt: Date(), body: .chat(ChatBody(id: UUID(), peer: to.id, text: text, photo: nil)))
    }

    private func keys(_ identities: Identity...) -> (UUID) -> Data? {
        { id in identities.first { $0.id == id }?.signingPublicKey }
    }

    func testRoundTrip() throws {
        let original = envelope(from: alice, to: bob)
        let sealed = try EnvelopeCodec.seal(original, identity: alice, recipientKey: bob.agreementPublicKey)
        let opened = EnvelopeCodec.open(sealed, identity: bob, signingKey: keys(alice))
        XCTAssertEqual(opened?.body, original.body)
        XCTAssertEqual(opened?.from, alice.id)
    }

    func testCiphertextHidesTheText() throws {
        let sealed = try EnvelopeCodec.seal(envelope(from: alice, to: bob, text: "MEET AT NOON"), identity: alice, recipientKey: bob.agreementPublicKey)
        XCTAssertNil(sealed.range(of: Data("MEET AT NOON".utf8)))
        XCTAssertNil(sealed.range(of: alice.id.uuidString.data(using: .utf8)!))
    }

    func testStrangersAreIgnored() throws {
        let sealed = try EnvelopeCodec.seal(envelope(from: alice, to: bob), identity: alice, recipientKey: bob.agreementPublicKey)
        XCTAssertNil(EnvelopeCodec.open(sealed, identity: bob, signingKey: keys()))
    }

    func testImpersonationIsRejected() throws {
        // Mallory knows Bob's public key and claims to be Alice, but can't sign as her.
        let mallory = Identity.generate()
        let forged = Envelope(from: alice.id, to: bob.id, sentAt: Date(), body: .unfriend)
        let sealed = try EnvelopeCodec.seal(forged, identity: mallory, recipientKey: bob.agreementPublicKey)
        XCTAssertNil(EnvelopeCodec.open(sealed, identity: bob, signingKey: keys(alice)))
    }

    func testEnvelopeForSomeoneElseIsRejectedEvenIfEncryptedToMe() throws {
        // A friend re-encrypts a message Alice addressed to Carol and forwards it to Bob.
        let carol = Identity.generate()
        let sealed = try EnvelopeCodec.seal(envelope(from: alice, to: carol), identity: alice, recipientKey: bob.agreementPublicKey)
        XCTAssertNil(EnvelopeCodec.open(sealed, identity: bob, signingKey: keys(alice)))
    }

    func testOnlyTheRecipientCanOpen() throws {
        let sealed = try EnvelopeCodec.seal(envelope(from: alice, to: bob), identity: alice, recipientKey: bob.agreementPublicKey)
        XCTAssertNil(EnvelopeCodec.open(sealed, identity: alice, signingKey: keys(alice, bob)))
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
