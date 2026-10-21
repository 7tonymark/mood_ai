import CloudKit
import Foundation

/// Mirrors the profile and friend list to the user's *private* iCloud database.
///
/// Nothing is written to a public database: no one can look players up, and only the
/// owner's own devices can read their friend list. This is what lets a friend list
/// survive a lost or replaced phone.
final class CloudSync {
    enum CloudError: Error {
        case noAccount
    }

    private enum Key {
        static let profileRecord = "profile"
        static let profileType = "Profile"
        static let friendType = "Friend"
        static let playerID = "playerID"
        static let name = "name"
        static let color = "color"
        static let avatar = "avatar"
        static let addedAt = "addedAt"
        static let method = "method"
    }

    private let container: CKContainer
    private var database: CKDatabase { container.privateCloudDatabase }

    /// Only call this when the iCloud entitlement is present (the CLOUDKIT build flag);
    /// `CKContainer.default()` crashes without it.
    init() {
        container = CKContainer.default()
    }

    func ensureAvailable() async throws {
        guard try await container.accountStatus() == .available else { throw CloudError.noAccount }
    }

    // MARK: Profile

    func fetchProfile() async throws -> Profile? {
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: Key.profileRecord))
            guard let idString = record[Key.playerID] as? String, let id = UUID(uuidString: idString),
                  let name = record[Key.name] as? String,
                  let colorValue = record[Key.color] as? Int, let color = PlayerColor(rawValue: colorValue),
                  let avatarHex = record[Key.avatar] as? String, let avatar = PixelAvatar(hex: avatarHex)
            else { return nil }
            return Profile(id: id, name: name, color: color, avatar: avatar)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func save(_ profile: Profile) async throws {
        let record = CKRecord(recordType: Key.profileType, recordID: CKRecord.ID(recordName: Key.profileRecord))
        record[Key.playerID] = profile.id.uuidString
        record[Key.name] = profile.name
        record[Key.color] = profile.color.rawValue
        record[Key.avatar] = profile.avatar.hex
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    // MARK: Friends

    func fetchFriends() async throws -> [Friend] {
        let query = CKQuery(recordType: Key.friendType, predicate: NSPredicate(value: true))
        var friends: [Friend] = []
        var (results, cursor) = try await database.records(matching: query)
        while true {
            for (_, result) in results {
                if let record = try? result.get(), let friend = Self.friend(from: record) {
                    friends.append(friend)
                }
            }
            guard let next = cursor else { break }
            (results, cursor) = try await database.records(continuingMatchFrom: next)
        }
        return friends
    }

    func save(_ friends: [Friend]) async throws {
        guard !friends.isEmpty else { return }
        let records = friends.map { friend in
            let record = CKRecord(recordType: Key.friendType, recordID: Self.recordID(for: friend.id))
            record[Key.name] = friend.name
            record[Key.color] = friend.color.rawValue
            record[Key.avatar] = friend.avatar.hex
            record[Key.addedAt] = friend.addedAt
            record[Key.method] = friend.method.rawValue
            return record
        }
        _ = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
    }

    func deleteFriend(_ id: UUID) async throws {
        _ = try await database.modifyRecords(saving: [], deleting: [Self.recordID(for: id)])
    }

    private static func recordID(for friendID: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "friend-\(friendID.uuidString)")
    }

    private static func friend(from record: CKRecord) -> Friend? {
        let prefix = "friend-"
        let recordName = record.recordID.recordName
        guard recordName.hasPrefix(prefix),
              let id = UUID(uuidString: String(recordName.dropFirst(prefix.count))),
              let name = record[Key.name] as? String,
              let colorValue = record[Key.color] as? Int, let color = PlayerColor(rawValue: colorValue),
              let avatarHex = record[Key.avatar] as? String, let avatar = PixelAvatar(hex: avatarHex),
              let addedAt = record[Key.addedAt] as? Date,
              let methodValue = record[Key.method] as? String, let method = Friend.Method(rawValue: methodValue)
        else { return nil }
        let card = PlayerCard(id: id, name: name, color: color, avatar: avatar)
        return Friend(card: card, method: method, addedAt: addedAt)
    }
}
