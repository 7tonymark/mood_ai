import XCTest
#if canImport(ProximityCore)
@testable import ProximityCore
#else
@testable import Proximity
#endif

/// End-to-end: several simulated phones talking through one fake server.
@MainActor
final class AppModelTests: XCTestCase {
    private var server: FakeServer!

    override func setUp() async throws {
        server = FakeServer()
    }

    private func phone(_ name: String) async -> TestPhone {
        let phone = TestPhone(server: server)
        await phone.start(name: name)
        return phone
    }

    private let jpeg = Data((0..<2048).map { UInt8($0 % 251) })

    // MARK: Setup

    func testFirstLaunchCreatesKeysAndASignedCard() async {
        let phone = TestPhone(server: server)
        await phone.model.boot()
        XCTAssertEqual(phone.model.phase, .setup)
        XCTAssertNotNil(phone.keys.identity, "keys are saved before the player even picks a name")

        phone.model.saveProfile(Profile(name: "ALICE", color: .green, avatar: .invader))
        XCTAssertEqual(phone.model.phase, .ready)
        XCTAssertEqual(phone.model.myCard?.id, phone.keys.identity?.id)
        XCTAssertEqual(phone.model.myCard.flatMap { PlayerCard.decode($0.encoded) }, phone.model.myCard)
    }

    func testOfflineBuildKeepsPostsLocal() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(store: LocalStore(directory: directory), backend: nil, identityStore: MemoryIdentityStore())
        await model.boot()
        model.saveProfile(Profile(name: "SOLO", color: .red, avatar: .invader))
        model.post(text: "JUST ME", photo: nil)
        XCTAssertEqual(model.feed.first?.status, .sent)
        XCTAssertNotNil(model.cloudWarning)
    }

    // MARK: Feed

    func testPostWithPhotoReachesFriendsAndOnlyFriends() async throws {
        let alice = await phone("ALICE")
        let bob = await phone("BOB")
        let carol = await phone("CAROL")
        befriend(alice, bob)

        alice.model.post(text: "LOOK AT THIS", photo: CapturedPhoto(jpeg: jpeg, width: 640, height: 480))
        await alice.model.flushOutbox()
        XCTAssertEqual(alice.model.feed.first?.status, .sent)

        await bob.model.sync()
        let post = try XCTUnwrap(bob.model.feed.first)
        XCTAssertEqual(post.author, alice.model.myID)
        XCTAssertEqual(post.text, "LOOK AT THIS")
        let photo = try XCTUnwrap(post.photo)
        let downloaded = await bob.model.photo(photo)
        XCTAssertEqual(downloaded, jpeg)

        await carol.model.sync()
        XCTAssertTrue(carol.model.feed.isEmpty, "not friends, so nothing arrives")
    }

    func testServerOnlyEverSeesCiphertext() async throws {
        let alice = await phone("ALICE")
        let bob = await phone("BOB")
        befriend(alice, bob)
        alice.model.post(text: "TOP SECRET PLANS", photo: CapturedPhoto(jpeg: jpeg, width: 10, height: 10))
        alice.model.sendMessage("SEE YOU AT 9", to: bob.model.myID!)
        await alice.model.flushOutbox()

        XCTAssertFalse(server.envelopes.isEmpty)
        for stored in server.envelopes.values {
            XCTAssertNil(stored.blob.range(of: Data("TOP SECRET".utf8)))
            XCTAssertNil(stored.blob.range(of: Data("SEE YOU".utf8)))
            XCTAssertNil(stored.blob.range(of: Data("ALICE".utf8)))
        }
        for ciphertext in server.attachments.values {
            XCTAssertNil(ciphertext.range(of: jpeg.prefix(64)))
        }
    }

    func testDeletedPostDisappearsForFriends() async throws {
        let alice = await phone("ALICE")
        let bob = await phone("BOB")
        befriend(alice, bob)
        alice.model.post(text: "OOPS", photo: CapturedPhoto(jpeg: jpeg, width: 10, height: 10))
        await alice.model.flushOutbox()
        await bob.model.sync()
        XCTAssertEqual(bob.model.feed.count, 1)

        let id = try XCTUnwrap(alice.model.feed.first?.id)
        alice.model.deletePost(id)
        await alice.model.flushOutbox()
        await bob.model.sync()
        XCTAssertTrue(bob.model.feed.isEmpty)
        XCTAssertTrue(alice.model.feed.isEmpty)
    }

    func testFailedPostIsRetried() async throws {
        let alice = await phone("ALICE")
        let bob = await phone("BOB")
        befriend(alice, bob)

        alice.backend.offline = true
        alice.model.post(text: "HELLO?", photo: nil)
        await alice.model.flushOutbox()
        XCTAssertEqual(alice.model.feed.first?.status, .failed)

        alice.backend.offline = false
        await alice.model.sync()
        XCTAssertEqual(alice.model.feed.first?.status, .sent)
        await bob.model.sync()
        XCTAssertEqual(bob.model.feed.first?.text, "HELLO?")
    }

    // MARK: Chat

    func testChatBothWaysWithUnreadCounts() async throws {
        let alice = await phone("ALICE")
        let bob = await phone("BOB")
        befriend(alice, bob)
        let aliceID = try XCTUnwrap(alice.model.myID)
        let bobID = try XCTUnwrap(bob.model.myID)

        alice.model.sendMessage("HI BOB", to: bobID)
        alice.model.sendMessage("", photo: CapturedPhoto(jpeg: jpeg, width: 20, height: 30), to: bobID)
        await alice.model.flushOutbox()
        await bob.model.sync()

        XCTAssertEqual(bob.model.messages(with: aliceID).map(\.text), ["HI BOB", ""])
        XCTAssertEqual(bob.model.unreadCount(with: aliceID), 2)
        let photo = try XCTUnwrap(bob.model.messages(with: aliceID).last?.photo)
        let downloaded = await bob.model.photo(photo)
        XCTAssertEqual(downloaded, jpeg)

        bob.model.markRead(aliceID)
        XCTAssertEqual(bob.model.totalUnread, 0)

        bob.model.sendMessage("HEY ALICE", to: aliceID)
        await bob.model.flushOutbox()
        await alice.model.sync()
        XCTAssertEqual(alice.model.messages(with: bobID).map(\.text), ["HI BOB", "", "HEY ALICE"])
        XCTAssertEqual(alice.model.unreadCount(with: bobID), 1)
    }

    // MARK: Attacks

    func testStrangersAndImpostorsCannotGetIn() async throws {
        let alice = await phone("ALICE")
        let bob = await phone("BOB")
        befriend(alice, bob)
        let aliceIdentity = try XCTUnwrap(alice.model.identity)
        let inbox = aliceIdentity.inbox.hex

        // Mallory learned Alice's mailbox tag and public key (say, from a leaked QR screenshot).
        let mallory = Identity.generate()
        let spam = Envelope(from: mallory.id, to: aliceIdentity.id, sentAt: Date(),
                            body: .post(PostBody(id: UUID(), text: "BUY NOW", photo: nil)))
        server.inject(try EnvelopeCodec.seal(spam, identity: mallory, recipientKey: aliceIdentity.agreementPublicKey), inbox: inbox)

        // She also tries to pass a message off as Bob's.
        let impostor = Envelope(from: bob.model.myID!, to: aliceIdentity.id, sentAt: Date(),
                                body: .chat(ChatBody(id: UUID(), peer: aliceIdentity.id, text: "SEND MONEY", photo: nil)))
        server.inject(try EnvelopeCodec.seal(impostor, identity: mallory, recipientKey: aliceIdentity.agreementPublicKey), inbox: inbox)

        // And a forged "unfriend" to break them up.
        let breakup = Envelope(from: bob.model.myID!, to: aliceIdentity.id, sentAt: Date(), body: .unfriend)
        server.inject(try EnvelopeCodec.seal(breakup, identity: mallory, recipientKey: aliceIdentity.agreementPublicKey), inbox: inbox)

        server.inject(Data("garbage".utf8), inbox: inbox)

        await alice.model.sync()
        XCTAssertTrue(alice.model.feed.isEmpty)
        XCTAssertTrue(alice.model.messages.isEmpty)
        XCTAssertTrue(alice.model.isFriend(bob.model.myID!))
    }

    func testReplayedEnvelopesAreDeduplicated() async throws {
        let alice = await phone("ALICE")
        let bob = await phone("BOB")
        befriend(alice, bob)
        alice.model.post(text: "ONCE", photo: nil)
        await alice.model.flushOutbox()
        await bob.model.sync()

        // Someone copies the envelope back into Bob's mailbox, as a new record.
        let bobInbox = bob.model.identity!.inbox.hex
        let original = try XCTUnwrap(server.envelopes.values.first { $0.inbox == bobInbox })
        server.inject(original.blob, inbox: bobInbox)
        await bob.model.sync()
        XCTAssertEqual(bob.model.feed.count, 1)
    }

    // MARK: Friends

    func testUnfriendRemovesBothSidesAndTheirContent() async throws {
        let alice = await phone("ALICE")
        let bob = await phone("BOB")
        befriend(alice, bob)
        alice.model.post(text: "HI ALL", photo: nil)
        await alice.model.flushOutbox()
        await bob.model.sync()
        XCTAssertEqual(bob.model.feed.count, 1)

        alice.model.removeFriend(bob.model.myID!)
        await alice.model.flushOutbox()
        XCTAssertFalse(alice.model.isFriend(bob.model.myID!))

        await bob.model.sync()
        XCTAssertFalse(bob.model.isFriend(alice.model.myID!))
        XCTAssertTrue(bob.model.feed.isEmpty)

        // Meeting again works, and the old "unfriend" isn't re-applied.
        befriend(alice, bob)
        await bob.model.sync()
        await bob.model.sync()
        XCTAssertTrue(bob.model.isFriend(alice.model.myID!))
    }

    func testProfileChangesReachFriends() async throws {
        let alice = await phone("ALICE")
        let bob = await phone("BOB")
        befriend(alice, bob)

        bob.model.saveProfile(Profile(name: "ROBERT", color: .orange, avatar: .invader))
        await bob.model.flushOutbox()
        await alice.model.sync()
        XCTAssertEqual(alice.model.friend(bob.model.myID!)?.name, "ROBERT")
        XCTAssertEqual(alice.model.friend(bob.model.myID!)?.color, .orange)
    }

    func testFriendListIsCapped() async throws {
        let alice = await phone("ALICE")
        for index in 0..<AppModel.maxFriends {
            let card = makeCard(name: "P\(index)")
            XCTAssertEqual(alice.model.addFriend(Introduction(card: card, inbox: Random.bytes(16)), via: .qr), .added)
        }
        XCTAssertEqual(alice.model.addFriend(Introduction(card: makeCard(name: "ONE MORE"), inbox: Random.bytes(16)), via: .qr), .listFull)
        XCTAssertEqual(alice.model.addFriend(alice.introduction, via: .qr), .isMe)
    }

    // MARK: New phone

    func testNewPhoneWithSyncedKeysGetsEverythingBack() async throws {
        let account = FakeAccount()
        let aliceKeys = MemoryIdentityStore()
        let alice = TestPhone(server: server, account: account, keys: aliceKeys)
        await alice.start(name: "ALICE")
        let bob = await phone("BOB")
        befriend(alice, bob)
        await alice.model.sync(full: true)

        alice.model.post(text: "MY POST", photo: nil)
        alice.model.sendMessage("FROM OLD PHONE", to: bob.model.myID!)
        await alice.model.flushOutbox()
        bob.model.sendMessage("TO ALICE", to: alice.model.myID!)
        await bob.model.flushOutbox()

        // Same iCloud account and keychain, empty phone.
        let newPhone = TestPhone(server: server, account: account, keys: MemoryIdentityStore(aliceKeys.identity))
        await newPhone.model.boot()
        XCTAssertEqual(newPhone.model.phase, .ready)
        XCTAssertEqual(newPhone.model.profile?.name, "ALICE")
        XCTAssertEqual(newPhone.model.myID, alice.model.myID)
        XCTAssertTrue(newPhone.model.isFriend(bob.model.myID!))
        XCTAssertEqual(newPhone.model.feed.map(\.text), ["MY POST"])
        XCTAssertEqual(newPhone.model.messages(with: bob.model.myID!).map(\.text), ["FROM OLD PHONE", "TO ALICE"])
    }

    func testNewPhoneWithoutKeysWaitsThenCanStartOver() async throws {
        let account = FakeAccount()
        let alice = TestPhone(server: server, account: account)
        await alice.start(name: "ALICE")
        let oldID = try XCTUnwrap(alice.model.myID)

        let keys = MemoryIdentityStore()
        let newPhone = TestPhone(server: server, account: account, keys: keys)
        await newPhone.model.boot()
        XCTAssertEqual(newPhone.model.phase, .restore)
        XCTAssertEqual(newPhone.model.pendingRestore?.profile.name, "ALICE")

        // iCloud Keychain catches up.
        keys.identity = alice.keys.identity
        await newPhone.model.retryRestore()
        XCTAssertEqual(newPhone.model.phase, .ready)
        XCTAssertEqual(newPhone.model.myID, oldID)

        // A third phone gives up waiting and starts over with new keys but the same look.
        let thirdPhone = TestPhone(server: server, account: account)
        await thirdPhone.model.boot()
        XCTAssertEqual(thirdPhone.model.phase, .restore)
        await thirdPhone.model.startAsNewPlayer()
        XCTAssertEqual(thirdPhone.model.phase, .ready)
        XCTAssertEqual(thirdPhone.model.profile?.name, "ALICE")
        XCTAssertNotEqual(thirdPhone.model.myID, oldID)
    }
}
