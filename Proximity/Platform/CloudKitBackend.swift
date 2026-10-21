import CloudKit
import Foundation

/// The CloudKit server behind the app.
///
/// - The **private** database holds the player's profile and friend list. Only the owner's own
///   devices can read it, which is how a replacement phone gets friends back.
/// - The **public** database holds mailboxes of envelopes and encrypted photos. Any signed-in
///   user of the app could read these records, which is why everything in them is end-to-end
///   encrypted and addressed by random mailbox tags rather than names or ids.
final class CloudKitBackend: CloudBackend {
    private enum RecordType {
        static let profile = "Profile"
        static let friend = "Friend"
        static let envelope = "Envelope"
        static let attachment = "Attachment"
    }

    /// CloudKit rejects batches of more than 400 records.
    private static let batchSize = 400

    private let container: CKContainer
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var publicDB: CKDatabase { container.publicCloudDatabase }

    /// Only create this when the iCloud entitlement is present (the CLOUDKIT build flag):
    /// `CKContainer.default()` crashes without it.
    init(container: CKContainer = .default()) {
        self.container = container
    }

    func checkAccount() async throws {
        guard try await container.accountStatus() == .available else { throw BackendError.noAccount }
    }

    // MARK: Private database

    func fetchProfile() async throws -> CloudProfile? {
        do {
            let record = try await privateDB.record(for: CKRecord.ID(recordName: "profile"))
            guard let idString = record["playerID"] as? String, let id = UUID(uuidString: idString),
                  let name = record["name"] as? String, Profile.isValidName(name),
                  let colorValue = record["color"] as? Int, let color = PlayerColor(rawValue: colorValue),
                  let avatarHex = record["avatar"] as? String, let avatar = PixelAvatar(hex: avatarHex)
            else { return nil }
            return CloudProfile(playerID: id, profile: Profile(name: name, color: color, avatar: avatar))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func saveProfile(_ cloudProfile: CloudProfile) async throws {
        let record = CKRecord(recordType: RecordType.profile, recordID: CKRecord.ID(recordName: "profile"))
        record["playerID"] = cloudProfile.playerID.uuidString
        record["name"] = cloudProfile.profile.name
        record["color"] = cloudProfile.profile.color.rawValue
        record["avatar"] = cloudProfile.profile.avatar.hex
        try await save([record], in: privateDB)
    }

    func fetchFriends() async throws -> [Friend] {
        let query = CKQuery(recordType: RecordType.friend, predicate: NSPredicate(value: true))
        return try await records(matching: query, in: privateDB).compactMap { record in
            // Cards are re-verified on the way in, so a corrupted record can't plant a bad key.
            guard let cardData = record["card"] as? Data, let card = PlayerCard.decode(cardData),
                  let inbox = record["inbox"] as? Data, inbox.count == 16,
                  let addedAt = record["addedAt"] as? Date,
                  let methodValue = record["method"] as? String, let method = Friend.Method(rawValue: methodValue)
            else { return nil }
            return Friend(card: card, inbox: inbox, addedAt: addedAt, method: method)
        }
    }

    func saveFriends(_ friends: [Friend]) async throws {
        let records = friends.map { friend -> CKRecord in
            let record = CKRecord(recordType: RecordType.friend, recordID: Self.friendRecordID(friend.id))
            record["card"] = friend.card.encoded
            record["inbox"] = friend.inbox
            record["addedAt"] = friend.addedAt
            record["method"] = friend.method.rawValue
            return record
        }
        try await save(records, in: privateDB)
    }

    func deleteFriends(_ ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        _ = try await privateDB.modifyRecords(saving: [], deleting: ids.map(Self.friendRecordID))
    }

    private static func friendRecordID(_ id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "friend-" + id.uuidString)
    }

    // MARK: Public database

    func send(_ envelopes: [OutgoingEnvelope]) async throws {
        let records = envelopes.map { envelope -> CKRecord in
            let record = CKRecord(recordType: RecordType.envelope, recordID: CKRecord.ID(recordName: envelope.recordName))
            record["inbox"] = envelope.inbox
            record["blob"] = envelope.blob
            return record
        }
        try await save(records, in: publicDB)
    }

    func fetchEnvelopes(inbox: String, since: Date?) async throws -> [ReceivedEnvelope] {
        let predicate: NSPredicate
        if let since {
            predicate = NSPredicate(format: "inbox == %@ AND creationDate >= %@", inbox, since as NSDate)
        } else {
            predicate = NSPredicate(format: "inbox == %@", inbox)
        }
        let query = CKQuery(recordType: RecordType.envelope, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        return try await records(matching: query, in: publicDB, keys: ["blob"]).compactMap { record in
            guard let blob = record["blob"] as? Data else { return nil }
            return ReceivedEnvelope(recordName: record.recordID.recordName, blob: blob, createdAt: record.creationDate ?? Date())
        }
    }

    func uploadAttachment(recordName: String, ciphertext: Data) async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try ciphertext.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let record = CKRecord(recordType: RecordType.attachment, recordID: CKRecord.ID(recordName: recordName))
        record["data"] = CKAsset(fileURL: file)
        try await save([record], in: publicDB)
    }

    func downloadAttachment(recordName: String) async throws -> Data {
        let record = try await publicDB.record(for: CKRecord.ID(recordName: recordName))
        guard let asset = record["data"] as? CKAsset, let url = asset.fileURL else { throw BackendError.notFound }
        return try Data(contentsOf: url)
    }

    func deleteAttachment(recordName: String) async throws {
        _ = try await publicDB.modifyRecords(saving: [], deleting: [CKRecord.ID(recordName: recordName)])
    }

    func subscribe(inbox: String) async throws {
        let subscription = CKQuerySubscription(
            recordType: RecordType.envelope,
            predicate: NSPredicate(format: "inbox == %@", inbox),
            subscriptionID: "inbox-" + inbox,
            options: [.firesOnRecordCreation]
        )
        let info = CKSubscription.NotificationInfo()
        // The server can't read envelopes, so this is all a notification can ever say.
        info.alertBody = "INCOMING TRANSMISSION"
        info.soundName = "default"
        subscription.notificationInfo = info
        _ = try await publicDB.modifySubscriptions(saving: [subscription], deleting: [])
    }

    // MARK: Helpers

    private func save(_ records: [CKRecord], in database: CKDatabase) async throws {
        for start in stride(from: 0, to: records.count, by: Self.batchSize) {
            let batch = Array(records[start..<min(start + Self.batchSize, records.count)])
            // `.allKeys` overwrites, so re-sending a record after a failed attempt is harmless.
            let (results, _) = try await database.modifyRecords(saving: batch, deleting: [], savePolicy: .allKeys, atomically: false)
            for (_, result) in results {
                if case .failure(let error) = result { throw error }
            }
        }
    }

    private func records(matching query: CKQuery, in database: CKDatabase, keys: [CKRecord.FieldKey]? = nil) async throws -> [CKRecord] {
        var found: [CKRecord] = []
        var (results, cursor) = try await database.records(matching: query, desiredKeys: keys)
        while true {
            for (_, result) in results {
                if let record = try? result.get() { found.append(record) }
            }
            guard let next = cursor else { break }
            (results, cursor) = try await database.records(continuingMatchFrom: next, desiredKeys: keys)
        }
        return found
    }
}
