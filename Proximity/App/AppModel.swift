import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Phase {
        case loading, setup, ready
    }

    enum AddResult: Equatable {
        case added, alreadyFriends, listFull, isMe
    }

    /// Keeps the circle close-knit (roughly Dunbar's number).
    static let maxFriends = 150

    private(set) var phase: Phase = .loading
    private(set) var profile: Profile?
    private(set) var friends: [Friend] = []
    /// Shown on the home screen when iCloud isn't backing up the friend list.
    private(set) var cloudWarning: String?

    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private let cloud: CloudSync?

    init(store: LocalStore = LocalStore(), cloud: CloudSync? = AppModel.defaultCloud()) {
        self.store = store
        self.cloud = cloud
    }

    nonisolated static func defaultCloud() -> CloudSync? {
        #if CLOUDKIT
        return CloudSync()
        #else
        return nil
        #endif
    }

    func boot() async {
        guard phase == .loading else { return }
        profile = store.loadProfile()
        friends = sorted(store.loadFriends())

        // With a local profile we can start right away and sync in the background.
        // Without one, first try to restore from iCloud, in case this is a new phone.
        if profile != nil {
            phase = .ready
            await syncWithCloud()
        } else {
            await syncWithCloud()
            phase = profile == nil ? .setup : .ready
        }
    }

    func saveProfile(_ newProfile: Profile) {
        profile = newProfile
        store.save(newProfile)
        phase = .ready
        Task { try? await cloud?.save(newProfile) }
    }

    func isFriend(_ id: UUID) -> Bool {
        friends.contains { $0.id == id }
    }

    @discardableResult
    func addFriend(_ card: PlayerCard, via method: Friend.Method) -> AddResult {
        guard card.id != profile?.id else { return .isMe }
        if let index = friends.firstIndex(where: { $0.id == card.id }) {
            friends[index].refresh(from: card)
            persist(friends[index])
            return .alreadyFriends
        }
        guard friends.count < Self.maxFriends else { return .listFull }
        let friend = Friend(card: card, method: method)
        friends = sorted(friends + [friend])
        persist(friend)
        return .added
    }

    func removeFriend(_ id: UUID) {
        friends.removeAll { $0.id == id }
        store.save(friends)
        Task { try? await cloud?.deleteFriend(id) }
    }

    private func persist(_ friend: Friend) {
        store.save(friends)
        Task { try? await cloud?.save([friend]) }
    }

    private func sorted(_ list: [Friend]) -> [Friend] {
        list.sorted { $0.addedAt > $1.addedAt }
    }

    private func syncWithCloud() async {
        guard let cloud else {
            cloudWarning = "NO ICLOUD BACKUP IN THIS BUILD"
            return
        }
        do {
            try await cloud.ensureAvailable()

            if profile == nil, let restored = try await cloud.fetchProfile() {
                profile = restored
                store.save(restored)
            } else if let profile {
                try await cloud.save(profile)
            }

            // Union both lists. A friendship is never deleted by a sync, only by "remove".
            let remote = try await cloud.fetchFriends()
            let remoteIDs = Set(remote.map(\.id))
            let localOnly = friends.filter { !remoteIDs.contains($0.id) }
            var merged = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for friend in friends {
                merged[friend.id] = friend
            }
            friends = sorted(Array(merged.values))
            store.save(friends)
            try await cloud.save(localOnly)
            cloudWarning = nil
        } catch CloudSync.CloudError.noAccount {
            cloudWarning = "SIGN IN TO ICLOUD TO BACK UP FRIENDS"
        } catch {
            cloudWarning = "ICLOUD SYNC FAILED - SAVED ON THIS PHONE"
        }
    }
}
