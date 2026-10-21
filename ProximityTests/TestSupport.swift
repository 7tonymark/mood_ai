import Foundation
#if canImport(ProximityCore)
@testable import ProximityCore
#else
@testable import Proximity
#endif

/// The shared public database every test player talks to. Main-actor isolated, because the
/// app calls its backend concurrently (CloudKit is thread-safe; a plain dictionary is not).
@MainActor
final class FakeServer {
    struct StoredEnvelope {
        var inbox: String
        var blob: Data
        var createdAt: Date
    }

    var envelopes: [String: StoredEnvelope] = [:]
    var attachments: [String: Data] = [:]
    var subscriptions: Set<String> = []
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    /// Server timestamps strictly increase, like CloudKit's creation dates in practice.
    func timestamp() -> Date {
        clock = clock.addingTimeInterval(1)
        return clock
    }

    /// Puts a raw blob into someone's mailbox, the way an attacker with the tag could.
    func inject(_ blob: Data, inbox: String) {
        envelopes["env-" + UUID().uuidString] = StoredEnvelope(inbox: inbox, blob: blob, createdAt: timestamp())
    }
}

/// One player's iCloud account: their private database.
@MainActor
final class FakeAccount {
    var profile: CloudProfile?
    var friends: [UUID: Friend] = [:]
}

struct OfflineError: Error {}

@MainActor
final class InMemoryBackend: CloudBackend {
    let server: FakeServer
    let account: FakeAccount
    var offline = false

    init(server: FakeServer, account: FakeAccount? = nil) {
        self.server = server
        self.account = account ?? FakeAccount()
    }

    private func checkOnline() throws {
        if offline { throw OfflineError() }
    }

    func checkAccount() async throws { try checkOnline() }

    func fetchProfile() async throws -> CloudProfile? {
        try checkOnline()
        return account.profile
    }

    func saveProfile(_ profile: CloudProfile) async throws {
        try checkOnline()
        account.profile = profile
    }

    func fetchFriends() async throws -> [Friend] {
        try checkOnline()
        return Array(account.friends.values)
    }

    func saveFriends(_ friends: [Friend]) async throws {
        try checkOnline()
        for friend in friends { account.friends[friend.id] = friend }
    }

    func deleteFriends(_ ids: [UUID]) async throws {
        try checkOnline()
        for id in ids { account.friends[id] = nil }
    }

    func send(_ envelopes: [OutgoingEnvelope]) async throws {
        try checkOnline()
        for envelope in envelopes where server.envelopes[envelope.recordName] == nil {
            server.envelopes[envelope.recordName] = FakeServer.StoredEnvelope(
                inbox: envelope.inbox, blob: envelope.blob, createdAt: server.timestamp()
            )
        }
    }

    func fetchEnvelopes(inbox: String, since: Date?) async throws -> [ReceivedEnvelope] {
        try checkOnline()
        return server.envelopes
            .filter { $0.value.inbox == inbox && $0.value.createdAt >= (since ?? .distantPast) }
            .map { ReceivedEnvelope(recordName: $0.key, blob: $0.value.blob, createdAt: $0.value.createdAt) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func uploadAttachment(recordName: String, ciphertext: Data) async throws {
        try checkOnline()
        server.attachments[recordName] = ciphertext
    }

    func downloadAttachment(recordName: String) async throws -> Data {
        try checkOnline()
        guard let data = server.attachments[recordName] else { throw BackendError.notFound }
        return data
    }

    func deleteAttachment(recordName: String) async throws {
        try checkOnline()
        server.attachments[recordName] = nil
    }

    func subscribe(inbox: String) async throws {
        try checkOnline()
        server.subscriptions.insert(inbox)
    }
}

final class MemoryIdentityStore: IdentityStoring {
    var identity: Identity?

    init(_ identity: Identity? = nil) {
        self.identity = identity
    }

    func load() -> Identity? { identity }

    func save(_ identity: Identity) throws {
        self.identity = identity
    }
}

/// One simulated phone.
@MainActor
struct TestPhone {
    let model: AppModel
    let backend: InMemoryBackend
    let keys: MemoryIdentityStore
    let directory: URL

    init(server: FakeServer, account: FakeAccount? = nil, keys: MemoryIdentityStore = MemoryIdentityStore()) {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("proximity-tests-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        backend = InMemoryBackend(server: server, account: account)
        self.keys = keys
        model = AppModel(store: LocalStore(directory: directory), backend: backend, identityStore: keys)
    }

    /// Boots the phone and creates a player, if it doesn't have one yet.
    func start(name: String, color: PlayerColor = .cyan) async {
        await model.boot()
        if model.phase == .setup {
            model.saveProfile(Profile(name: name, color: color, avatar: .invader))
        }
        await model.sync(full: true)
    }

    var introduction: Introduction {
        Introduction(card: model.myCard!, inbox: model.identity!.inbox)
    }
}

@MainActor
func befriend(_ a: TestPhone, _ b: TestPhone) {
    a.model.addFriend(b.introduction, via: .bluetooth)
    b.model.addFriend(a.introduction, via: .bluetooth)
}

func makeCard(name: String = "TESTER", identity: Identity = .generate()) -> PlayerCard {
    try! PlayerCard.make(identity: identity, profile: Profile(name: name, color: .magenta, avatar: .invader))
}
