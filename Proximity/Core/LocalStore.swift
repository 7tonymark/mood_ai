import Foundation

/// The on-device copy of everything, so the app works offline and starts instantly.
/// JSON documents live in the store's folder; decrypted photos and pending uploads in `media/`.
struct LocalStore {
    enum File {
        static let profile = "profile.json"
        static let friends = "friends.json"
        static let feed = "feed.json"
        static let messages = "messages.json"
        static let outbox = "outbox.json"
        static let sync = "sync.json"
    }

    let directory: URL
    private let media: URL

    init(directory: URL? = nil) {
        let base = directory ?? (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        self.directory = base
        self.media = base.appendingPathComponent("media", isDirectory: true)
        try? FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
    }

    func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        write(data, to: directory.appendingPathComponent(name))
    }

    func remove(_ name: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    // MARK: Media

    func mediaData(_ name: String) -> Data? {
        guard let url = mediaURL(name) else { return nil }
        return try? Data(contentsOf: url)
    }

    func writeMedia(_ data: Data, _ name: String) {
        guard let url = mediaURL(name) else { return }
        write(data, to: url)
    }

    func removeMedia(_ name: String) {
        guard let url = mediaURL(name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Media names include record names received from other phones, so only plain names are allowed.
    private func mediaURL(_ name: String) -> URL? {
        let allowed = name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }
        guard !name.isEmpty, !name.hasPrefix("."), allowed else { return nil }
        return media.appendingPathComponent(name)
    }

    private func write(_ data: Data, to url: URL) {
        #if os(iOS)
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try? data.write(to: url, options: [.atomic])
        #endif
    }
}
