import Foundation

/// The on-device copy of the profile and friend list, so the app works offline and starts instantly.
struct LocalStore {
    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            self.directory = (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )) ?? FileManager.default.temporaryDirectory
        }
    }

    func loadProfile() -> Profile? {
        load(Profile.self, from: "profile.json")
    }

    func save(_ profile: Profile) {
        save(profile, to: "profile.json")
    }

    func loadFriends() -> [Friend] {
        load([Friend].self, from: "friends.json") ?? []
    }

    func save(_ friends: [Friend]) {
        save(friends, to: "friends.json")
    }

    private func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
    }
}
