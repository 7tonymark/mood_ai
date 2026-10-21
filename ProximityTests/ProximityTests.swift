import XCTest
@testable import Proximity

final class PixelAvatarTests: XCTestCase {
    func testHexRoundTrip() {
        let avatar = PixelAvatar.invader
        XCTAssertEqual(avatar.hex.count, 16)
        XCTAssertEqual(PixelAvatar(hex: avatar.hex), avatar)
        XCTAssertNil(PixelAvatar(hex: "nothex"))
    }

    func testRandomAvatarIsSymmetricAndNeverBlank() {
        for _ in 0..<50 {
            let avatar = PixelAvatar.random()
            XCTAssertFalse(avatar.isEmpty)
            for y in 0..<PixelAvatar.size {
                for x in 0..<PixelAvatar.size {
                    XCTAssertEqual(avatar[x, y], avatar[PixelAvatar.size - 1 - x, y])
                }
            }
        }
    }

    func testSubscriptSetsAndClearsSinglePixel() {
        var avatar = PixelAvatar()
        avatar[7, 7] = true
        XCTAssertEqual(avatar.bits, 1 << 63)
        avatar[7, 7] = false
        XCTAssertTrue(avatar.isEmpty)
    }
}

final class PlayerCardTests: XCTestCase {
    private func card(name: String = "PLAYER ONE!!") -> PlayerCard {
        PlayerCard(id: UUID(), name: name, color: .magenta, avatar: .invader)
    }

    func testRoundTrip() {
        let original = card()
        XCTAssertEqual(PlayerCard.decode(original.encoded()), original)
    }

    func testFitsInOneBluetoothWrite() {
        // iOS-to-iOS connections usually negotiate a 185-byte MTU; stay under one packet.
        XCTAssertLessThan(card().encoded().count, 180)
    }

    func testRejectsInvalidNames() {
        XCTAssertNil(PlayerCard.decode(card(name: "").encoded()))
        XCTAssertNil(PlayerCard.decode(card(name: "lowercase").encoded()))
        XCTAssertNil(PlayerCard.decode(card(name: "WAY TOO LONG NAME").encoded()))
    }

    func testRejectsOtherVersions() {
        var future = card()
        future.v = 99
        XCTAssertNil(PlayerCard.decode(future.encoded()))
    }

    func testSanitize() {
        XCTAssertEqual(Profile.sanitize("ana🙂 maría"), "ANA MARA")
        XCTAssertEqual(Profile.sanitize("abcdefghijklmnop"), "ABCDEFGHIJKL")
    }
}

final class HandshakeLedgerTests: XCTestCase {
    private let alex = PlayerCard(id: UUID(), name: "ALEX", color: .cyan, avatar: .invader)

    func testNeedsBothSides() {
        var ledger = HandshakeLedger()
        ledger.discovered(alex)
        XCTAssertNil(ledger.markIAccepted(alex.id))
        XCTAssertEqual(ledger.markTheyAccepted(alex), alex)
    }

    func testOrderDoesNotMatter() {
        var ledger = HandshakeLedger()
        XCTAssertNil(ledger.markTheyAccepted(alex))
        XCTAssertEqual(ledger.markIAccepted(alex.id), alex)
    }

    func testCompletesOnlyOnce() {
        var ledger = HandshakeLedger()
        ledger.markTheyAccepted(alex)
        ledger.markIAccepted(alex.id)
        XCTAssertNil(ledger.markTheyAccepted(alex))
        XCTAssertNil(ledger.markIAccepted(alex.id))
    }

    func testCannotAcceptSomeoneNeverSeen() {
        var ledger = HandshakeLedger()
        XCTAssertNil(ledger.markIAccepted(alex.id))
        XCTAssertNil(ledger.entries[alex.id])
    }
}

final class QRPayloadTests: XCTestCase {
    private let card = PlayerCard(id: UUID(), name: "SAM", color: .green, avatar: .invader)

    func testRoundTripWithinWindow() {
        let now = Date()
        let code = QRPayload.current(for: card, now: now).string()
        XCTAssertEqual(try QRPayload.parse(code, now: now).get(), card)
    }

    func testExpires() {
        let now = Date()
        let code = QRPayload.current(for: card, now: now).string()
        let later = now.addingTimeInterval(QRPayload.window + QRPayload.grace + 1)
        XCTAssertEqual(QRPayload.parse(code, now: later), .failure(.expired))
    }

    func testRejectsCodesClaimingToLiveTooLong() {
        let payload = QRPayload(card: card, exp: Date().addingTimeInterval(3600))
        XCTAssertEqual(QRPayload.parse(payload.string()), .failure(.expired))
    }

    func testRejectsForeignCodes() {
        XCTAssertEqual(QRPayload.parse("https://example.com"), .failure(.notOurs))
        XCTAssertEqual(QRPayload.parse("PRXY1:!!!"), .failure(.malformed))
    }
}

@MainActor
final class AppModelTests: XCTestCase {
    private func makeModel() -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return AppModel(store: LocalStore(directory: directory), cloud: nil)
    }

    func testAddFriendThenUpdateOnSecondMeeting() async {
        let model = makeModel()
        await model.boot()
        model.saveProfile(Profile(id: UUID(), name: "ME", color: .cyan, avatar: .invader))

        var card = PlayerCard(id: UUID(), name: "KAI", color: .red, avatar: .invader)
        XCTAssertEqual(model.addFriend(card, via: .bluetooth), .added)
        card.name = "KAI2"
        XCTAssertEqual(model.addFriend(card, via: .qr), .alreadyFriends)
        XCTAssertEqual(model.friends.map(\.name), ["KAI2"])
    }

    func testCannotAddYourself() async {
        let model = makeModel()
        await model.boot()
        let me = Profile(id: UUID(), name: "ME", color: .cyan, avatar: .invader)
        model.saveProfile(me)
        XCTAssertEqual(model.addFriend(me.card, via: .qr), .isMe)
        XCTAssertTrue(model.friends.isEmpty)
    }
}
