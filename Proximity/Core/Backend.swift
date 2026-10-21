import Foundation

/// An envelope ready to upload. It's sealed before it's queued, so retries send identical bytes.
struct OutgoingEnvelope: Codable, Equatable {
    var recordName: String
    /// The recipient's mailbox tag, in hex.
    var inbox: String
    var blob: Data
}

struct ReceivedEnvelope: Equatable {
    var recordName: String
    var blob: Data
    /// Server time, which (unlike a sender's clock) can't be faked.
    var createdAt: Date
}

/// The profile copy kept in the player's private iCloud database.
struct CloudProfile: Equatable {
    var playerID: UUID
    var profile: Profile
}

enum BackendError: Error {
    case noAccount
    case notFound
}

/// Everything the app needs from a server. On iOS this is CloudKit; tests use an in-memory fake.
protocol CloudBackend: AnyObject {
    func checkAccount() async throws

    // Private database: only the owner's own devices can read these.
    func fetchProfile() async throws -> CloudProfile?
    func saveProfile(_ profile: CloudProfile) async throws
    func fetchFriends() async throws -> [Friend]
    func saveFriends(_ friends: [Friend]) async throws
    func deleteFriends(_ ids: [UUID]) async throws

    // Public database: readable by any signed-in user, so everything in it is encrypted.
    /// Saves envelopes. Saving the same record name twice must not create a duplicate.
    func send(_ envelopes: [OutgoingEnvelope]) async throws
    /// Envelopes in a mailbox created at or after `since`, oldest first.
    func fetchEnvelopes(inbox: String, since: Date?) async throws -> [ReceivedEnvelope]
    func uploadAttachment(recordName: String, ciphertext: Data) async throws
    func downloadAttachment(recordName: String) async throws -> Data
    func deleteAttachment(recordName: String) async throws
    /// Asks the server to push a notification when something lands in this mailbox.
    func subscribe(inbox: String) async throws
}

/// Where the player's private keys live. On iOS this is iCloud Keychain.
protocol IdentityStoring {
    func load() -> Identity?
    func save(_ identity: Identity) throws
}
