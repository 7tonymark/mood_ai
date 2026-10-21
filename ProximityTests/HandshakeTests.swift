import XCTest
#if canImport(ProximityCore)
@testable import ProximityCore
#else
@testable import Proximity
#endif

final class PlayerCardTests: XCTestCase {
    func testRoundTripAndSize() throws {
        let card = makeCard(name: "PLAYER ONE!!")
        XCTAssertLessThanOrEqual(card.encoded.count, PlayerCard.maxEncodedSize)
        XCTAssertEqual(PlayerCard.decode(card.encoded), card)
    }

    func testIdComesFromTheSigningKey() {
        let identity = Identity.generate()
        XCTAssertEqual(makeCard(identity: identity).id, identity.id)
    }

    func testAnyChangedByteIsRejected() {
        let encoded = makeCard(name: "ALEX").encoded
        for index in encoded.indices {
            var tampered = encoded
            tampered[index] ^= 0x01
            XCTAssertNil(PlayerCard.decode(tampered), "byte \(index) was changed but the card still verified")
        }
    }

    func testCannotClaimSomeoneElsesKey() {
        // Mallory copies Alice's card but swaps in her own signing key: the signature no longer matches.
        let alice = makeCard(name: "ALICE")
        let mallory = Identity.generate()
        var forged = alice.encoded
        forged.replaceSubrange(1..<33, with: mallory.signingPublicKey)
        XCTAssertNil(PlayerCard.decode(forged))
    }

    func testRejectsInvalidNamesWhenMaking() {
        let profile = Profile(name: "lowercase", color: .cyan, avatar: .invader)
        XCTAssertThrowsError(try PlayerCard.make(identity: .generate(), profile: profile))
    }

    func testCodableVerifiesOnDecode() throws {
        let card = makeCard()
        let json = try JSONEncoder().encode([card])
        XCTAssertEqual(try JSONDecoder().decode([PlayerCard].self, from: json), [card])

        var tampered = card.encoded
        tampered[tampered.count - 1] ^= 1
        let badJSON = try JSONEncoder().encode([tampered])
        XCTAssertThrowsError(try JSONDecoder().decode([PlayerCard].self, from: badJSON))
    }
}

final class AcceptMessageTests: XCTestCase {
    private let alice = Identity.generate()
    private let bob = Identity.generate()
    private lazy var aliceHello = Hello(card: makeCard(name: "ALICE", identity: alice), nonce: Hello.newNonce())
    private lazy var bobCard = makeCard(name: "BOB", identity: bob)

    func testHelloRoundTrip() {
        XCTAssertEqual(Hello.decode(aliceHello.encoded), aliceHello)
        XCTAssertNil(Hello.decode(aliceHello.encoded.dropLast()))
    }

    func testAcceptHappyPath() throws {
        let accept = try AcceptMessage.make(identity: bob, card: bobCard, to: aliceHello)
        XCTAssertLessThan(accept.count, 512, "must fit in one Bluetooth attribute")
        let introduction = AcceptMessage.open(accept, identity: alice, myNonce: aliceHello.nonce)
        XCTAssertEqual(introduction?.card, bobCard)
        XCTAssertEqual(introduction?.inbox, bob.inbox)
    }

    func testReplayIntoANewSessionIsRejected() throws {
        let accept = try AcceptMessage.make(identity: bob, card: bobCard, to: aliceHello)
        XCTAssertNil(AcceptMessage.open(accept, identity: alice, myNonce: Hello.newNonce()))
    }

    func testAcceptForSomeoneElseIsRejected() throws {
        let carol = Identity.generate()
        let accept = try AcceptMessage.make(identity: bob, card: bobCard, to: aliceHello)
        XCTAssertNil(AcceptMessage.open(accept, identity: carol, myNonce: aliceHello.nonce))
    }

    func testAcceptSignedByTheWrongKeyIsRejected() throws {
        // Mallory presents Bob's (genuine, public) card but can only sign with her own key.
        let mallory = Identity.generate()
        let forged = try AcceptMessage.make(identity: mallory, card: bobCard, to: aliceHello)
        XCTAssertNil(AcceptMessage.open(forged, identity: alice, myNonce: aliceHello.nonce))
    }

    func testAnyChangedByteIsRejected() throws {
        let accept = try AcceptMessage.make(identity: bob, card: bobCard, to: aliceHello)
        for index in stride(from: 0, to: accept.count, by: 7) {
            var tampered = accept
            tampered[index] ^= 0x01
            XCTAssertNil(AcceptMessage.open(tampered, identity: alice, myNonce: aliceHello.nonce), "byte \(index)")
        }
    }
}

final class HandshakeLedgerTests: XCTestCase {
    private let alex = Introduction(card: makeCard(name: "ALEX"), inbox: Random.bytes(16))

    func testNeedsBothSides() {
        var ledger = HandshakeLedger()
        ledger.discovered(alex.card)
        XCTAssertNil(ledger.markIAccepted(alex.card.id))
        XCTAssertEqual(ledger.markTheyAccepted(alex), alex)
    }

    func testOrderDoesNotMatter() {
        var ledger = HandshakeLedger()
        XCTAssertNil(ledger.markTheyAccepted(alex))
        XCTAssertEqual(ledger.markIAccepted(alex.card.id), alex)
    }

    func testCompletesOnlyOnce() {
        var ledger = HandshakeLedger()
        ledger.markTheyAccepted(alex)
        ledger.markIAccepted(alex.card.id)
        XCTAssertNil(ledger.markTheyAccepted(alex))
        XCTAssertNil(ledger.markIAccepted(alex.card.id))
    }

    func testCannotAcceptSomeoneNeverSeen() {
        var ledger = HandshakeLedger()
        XCTAssertNil(ledger.markIAccepted(alex.card.id))
        XCTAssertNil(ledger.entries[alex.card.id])
    }
}
