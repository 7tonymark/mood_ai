import Foundation
import Observation

/// A queued delivery: the sealed envelopes for one post or message, plus its photo if it has one.
struct OutboxItem: Codable, Equatable {
    /// The post or message this delivers, so its status can be updated.
    var id: UUID
    /// A photo that still needs uploading. Its ciphertext waits in the media folder.
    var attachment: String?
    var envelopes: [OutgoingEnvelope]
}

struct SyncState: Codable, Equatable {
    struct Cursor: Codable, Equatable {
        var date: Date
        /// Records at exactly `date` that were already handled, since each fetch includes that instant.
        var seen: Set<String>
    }

    var cursors: [String: Cursor] = [:]
    var lastRead: [UUID: Date] = [:]
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case loading
        /// A player exists in iCloud, but their keys haven't reached this phone through iCloud Keychain.
        case restore
        case setup
        case ready
    }

    enum AddResult: Equatable {
        case added, alreadyFriends, listFull, isMe
    }

    /// Keeps the circle close-knit (roughly Dunbar's number).
    static let maxFriends = 150
    static let maxPostLength = 500
    static let maxMessageLength = 1000

    private(set) var phase: Phase = .loading
    private(set) var profile: Profile?
    private(set) var myCard: PlayerCard?
    private(set) var friends: [Friend] = []
    /// Newest first.
    private(set) var feed: [FeedPost] = []
    /// Oldest first, across all conversations.
    private(set) var messages: [ChatMessage] = []
    private(set) var lastRead: [UUID: Date] = [:]
    /// Shown on the main screen when something is keeping posts and messages from moving.
    private(set) var cloudWarning: String?
    private(set) var isSyncing = false
    /// The player found in iCloud during the `.restore` phase.
    private(set) var pendingRestore: CloudProfile?

    @ObservationIgnored private(set) var identity: Identity?

    private let store: LocalStore
    private let backend: (any CloudBackend)?
    private let identityStore: any IdentityStoring
    private let now: () -> Date
    @ObservationIgnored private var outbox: [OutboxItem] = []
    @ObservationIgnored private var syncState = SyncState()
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var subscribedToInbox = false

    init(store: LocalStore, backend: (any CloudBackend)?, identityStore: any IdentityStoring, now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.backend = backend
        self.identityStore = identityStore
        self.now = now
    }

    var myID: UUID? { identity?.id }

    // MARK: - Boot

    func boot() async {
        guard phase == .loading else { return }
        loadLocal()
        if let saved = identityStore.load() {
            identity = saved
        } else if let found = await fetchCloudProfile() {
            // This is probably a new phone. Wait for the keys rather than silently making new ones.
            pendingRestore = found
            phase = .restore
            return
        } else {
            createIdentity()
        }
        await finishBoot()
    }

    /// From the restore screen, once the user has checked iCloud Keychain is on.
    func retryRestore() async {
        guard phase == .restore, let saved = identityStore.load() else { return }
        identity = saved
        pendingRestore = nil
        await finishBoot()
    }

    /// From the restore screen: give up on the old keys. Friends pinned those keys,
    /// so old friendships can't carry over and are cleared here and in iCloud.
    func startAsNewPlayer() async {
        guard phase == .restore else { return }
        let previous = pendingRestore
        pendingRestore = nil
        createIdentity()
        var stale = Set(friends.map(\.id))
        friends = []
        feed = []
        messages = []
        outbox = []
        lastRead = [:]
        syncState = SyncState()
        saveEverything()
        if let backend, let remote = try? await backend.fetchFriends() {
            stale.formUnion(remote.map(\.id))
        }
        if !stale.isEmpty {
            try? await backend?.deleteFriends(Array(stale))
        }
        if let previous {
            profile = previous.profile
            store.save(previous.profile, to: LocalStore.File.profile)
        }
        await finishBoot()
    }

    private func finishBoot() async {
        if profile == nil, let found = await fetchCloudProfile() {
            profile = found.profile
            store.save(found.profile, to: LocalStore.File.profile)
        }
        refreshCard()
        if backend == nil {
            cloudWarning = "OFFLINE BUILD - NOTHING LEAVES THIS PHONE"
        }
        phase = myCard == nil ? .setup : .ready
        await sync(full: true)
    }

    private func loadLocal() {
        profile = store.load(Profile.self, from: LocalStore.File.profile)
        friends = store.load([Friend].self, from: LocalStore.File.friends) ?? []
        feed = store.load([FeedPost].self, from: LocalStore.File.feed) ?? []
        messages = store.load([ChatMessage].self, from: LocalStore.File.messages) ?? []
        outbox = store.load([OutboxItem].self, from: LocalStore.File.outbox) ?? []
        syncState = store.load(SyncState.self, from: LocalStore.File.sync) ?? SyncState()
        lastRead = syncState.lastRead
    }

    private func fetchCloudProfile() async -> CloudProfile? {
        guard let backend else { return nil }
        do {
            try await backend.checkAccount()
            return try await backend.fetchProfile()
        } catch {
            return nil
        }
    }

    private func createIdentity() {
        let fresh = Identity.generate()
        do {
            try identityStore.save(fresh)
        } catch {
            cloudWarning = "COULDN'T SAVE YOUR KEYS TO THE KEYCHAIN"
        }
        identity = fresh
    }

    private func refreshCard() {
        guard let identity, let profile else {
            myCard = nil
            return
        }
        myCard = try? PlayerCard.make(identity: identity, profile: profile)
    }

    // MARK: - Profile

    func saveProfile(_ newProfile: Profile) {
        guard let identity, Profile.isValidName(newProfile.name) else { return }
        let changed = newProfile != profile
        profile = newProfile
        store.save(newProfile, to: LocalStore.File.profile)
        refreshCard()
        guard let card = myCard else { return }

        let firstTime = phase != .ready
        phase = .ready
        let cloudCopy = CloudProfile(playerID: identity.id, profile: newProfile)
        Task { try? await backend?.saveProfile(cloudCopy) }
        if changed, !friends.isEmpty {
            deliver(.profile(card), to: friends, archive: false)
        }
        if firstTime {
            Task { await sync(full: true) }
        }
    }

    // MARK: - Friends

    func friend(_ id: UUID) -> Friend? {
        friends.first { $0.id == id }
    }

    func isFriend(_ id: UUID) -> Bool {
        friend(id) != nil
    }

    /// The card for a friend, or for me.
    func card(for id: UUID) -> PlayerCard? {
        id == identity?.id ? myCard : friend(id)?.card
    }

    @discardableResult
    func addFriend(_ introduction: Introduction, via method: Friend.Method) -> AddResult {
        guard let identity else { return .listFull }
        guard introduction.card.id != identity.id else { return .isMe }
        if let index = friends.firstIndex(where: { $0.id == introduction.card.id }) {
            friends[index].card = introduction.card
            friends[index].inbox = introduction.inbox
            persistFriends(changed: [friends[index]])
            return .alreadyFriends
        }
        guard friends.count < Self.maxFriends else { return .listFull }
        let friend = Friend(card: introduction.card, inbox: introduction.inbox, addedAt: now(), method: method)
        friends.insert(friend, at: 0)
        persistFriends(changed: [friend])
        return .added
    }

    /// Removes a friend and everything they shared, and tells their phone to remove you too.
    func removeFriend(_ id: UUID) {
        guard let friend = friend(id) else { return }
        deliver(.unfriend, to: [friend], archive: false)
        forget(id)
    }

    private func forget(_ id: UUID) {
        friends.removeAll { $0.id == id }
        feed.removeAll { $0.author == id }
        messages.removeAll { $0.conversation == id }
        lastRead[id] = nil
        syncState.lastRead = lastRead
        saveEverything()
        Task { try? await backend?.deleteFriends([id]) }
    }

    private func persistFriends(changed: [Friend]) {
        store.save(friends, to: LocalStore.File.friends)
        guard !changed.isEmpty else { return }
        Task { try? await backend?.saveFriends(changed) }
    }

    // MARK: - Feed

    func post(text: String, photo: CapturedPhoto?) {
        guard let identity else { return }
        let text = Self.clean(text, limit: Self.maxPostLength)
        let attachment = photo.flatMap(stage)
        guard !text.isEmpty || attachment != nil else { return }
        let id = UUID()
        feed.insert(FeedPost(id: id, author: identity.id, text: text, photo: attachment, createdAt: now(), status: .sending), at: 0)
        store.save(feed, to: LocalStore.File.feed)
        deliver(.post(PostBody(id: id, text: text, photo: attachment)), to: friends, archive: true, id: id, attachment: attachment?.recordName)
    }

    func deletePost(_ id: UUID) {
        guard let identity, let post = feed.first(where: { $0.id == id }), post.author == identity.id else { return }
        feed.removeAll { $0.id == id }
        store.save(feed, to: LocalStore.File.feed)
        outbox.removeAll { $0.id == id }
        deliver(.deletePost(id), to: friends, archive: true)
        if let photo = post.photo {
            store.removeMedia(photo.recordName)
            store.removeMedia(photo.recordName + ".upload")
            Task { try? await backend?.deleteAttachment(recordName: photo.recordName) }
        }
    }

    // MARK: - Chat

    func sendMessage(_ text: String, photo: CapturedPhoto? = nil, to friendID: UUID) {
        guard let identity, let friend = friend(friendID) else { return }
        let text = Self.clean(text, limit: Self.maxMessageLength)
        let attachment = photo.flatMap(stage)
        guard !text.isEmpty || attachment != nil else { return }
        let id = UUID()
        let sentAt = now()
        messages.append(ChatMessage(
            id: id, conversation: friendID, from: identity.id, text: text, photo: attachment,
            sentAt: sentAt, receivedAt: sentAt, status: .sending
        ))
        store.save(messages, to: LocalStore.File.messages)
        deliver(.chat(ChatBody(id: id, peer: friendID, text: text, photo: attachment)), to: [friend], archive: true, id: id, attachment: attachment?.recordName)
    }

    func messages(with friendID: UUID) -> [ChatMessage] {
        messages.filter { $0.conversation == friendID }
    }

    func lastMessage(with friendID: UUID) -> ChatMessage? {
        messages.last { $0.conversation == friendID }
    }

    func unreadCount(with friendID: UUID) -> Int {
        guard let me = identity?.id else { return 0 }
        let since = lastRead[friendID] ?? .distantPast
        return messages.filter { $0.conversation == friendID && $0.from != me && $0.receivedAt > since }.count
    }

    var totalUnread: Int {
        friends.reduce(0) { $0 + unreadCount(with: $1.id) }
    }

    func markRead(_ friendID: UUID) {
        lastRead[friendID] = now()
        syncState.lastRead = lastRead
        store.save(syncState, to: LocalStore.File.sync)
    }

    // MARK: - Photos

    /// The decrypted JPEG for a photo, downloading it the first time.
    func photo(_ ref: AttachmentRef) async -> Data? {
        guard ref.isValid else { return nil }
        if let cached = store.mediaData(ref.recordName) { return cached }
        guard let backend,
              let ciphertext = try? await backend.downloadAttachment(recordName: ref.recordName),
              let plaintext = try? AttachmentCrypto.decrypt(ciphertext, key: ref.key) else { return nil }
        store.writeMedia(plaintext, ref.recordName)
        return plaintext
    }

    /// Encrypts a photo once. The key travels inside each envelope that mentions it.
    private func stage(_ photo: CapturedPhoto) -> AttachmentRef? {
        guard let sealed = try? AttachmentCrypto.encrypt(photo.jpeg) else { return nil }
        let ref = AttachmentRef(
            recordName: AttachmentRef.newRecordName(),
            key: sealed.key,
            width: min(max(photo.width, 1), 10_000),
            height: min(max(photo.height, 1), 10_000)
        )
        store.writeMedia(photo.jpeg, ref.recordName)
        store.writeMedia(sealed.ciphertext, ref.recordName + ".upload")
        return ref
    }

    // MARK: - Sending

    private struct Recipient {
        var id: UUID
        var key: Data
        var inbox: String
    }

    /// Seals one envelope per recipient (plus one for my own archive) and queues them.
    private func deliver(_ body: Envelope.Body, to recipients: [Friend], archive: Bool, id: UUID = UUID(), attachment: String? = nil) {
        guard let identity else { return }
        guard backend != nil else {
            // Offline build: there's nowhere to send to, so don't leave it "sending" forever.
            setStatus(id, .sent)
            return
        }
        var targets = recipients.map { Recipient(id: $0.id, key: $0.card.agreementKey, inbox: $0.inbox.hex) }
        if archive {
            targets.append(Recipient(id: identity.id, key: identity.agreementPublicKey, inbox: identity.archive.hex))
        }
        let sentAt = now()
        let envelopes = targets.compactMap { target -> OutgoingEnvelope? in
            let envelope = Envelope(from: identity.id, to: target.id, sentAt: sentAt, body: body)
            guard let blob = try? EnvelopeCodec.seal(envelope, identity: identity, recipientKey: target.key) else { return nil }
            return OutgoingEnvelope(recordName: "env-" + UUID().uuidString, inbox: target.inbox, blob: blob)
        }
        guard !envelopes.isEmpty else { return }
        outbox.append(OutboxItem(id: id, attachment: attachment, envelopes: envelopes))
        store.save(outbox, to: LocalStore.File.outbox)
        Task { await flushOutbox() }
    }

    /// Tries a failed post or message again.
    func retry(_ id: UUID) {
        guard outbox.contains(where: { $0.id == id }) else { return }
        setStatus(id, .sending)
        Task { await flushOutbox() }
    }

    /// Uploads whatever is waiting. Only one flush runs at a time: a call made during a flush
    /// waits for it, then flushes anything still queued, so on return everything queued before
    /// the call has been attempted.
    func flushOutbox() async {
        while let running = flushTask {
            await running.value
        }
        guard let backend, !outbox.isEmpty else { return }
        let task = Task {
            await performFlush(backend: backend)
            flushTask = nil
        }
        flushTask = task
        await task.value
    }

    private func performFlush(backend: any CloudBackend) async {
        var attempted = Set<UUID>()
        while let item = outbox.first(where: { !attempted.contains($0.id) }) {
            attempted.insert(item.id)
            do {
                if let recordName = item.attachment {
                    // Missing ciphertext means an earlier attempt already uploaded it.
                    if let ciphertext = store.mediaData(recordName + ".upload") {
                        try await backend.uploadAttachment(recordName: recordName, ciphertext: ciphertext)
                        store.removeMedia(recordName + ".upload")
                    }
                    if let index = outbox.firstIndex(where: { $0.id == item.id }) {
                        outbox[index].attachment = nil
                    }
                }
                try await backend.send(item.envelopes)
                outbox.removeAll { $0.id == item.id }
                setStatus(item.id, .sent)
            } catch {
                setStatus(item.id, .failed)
            }
            store.save(outbox, to: LocalStore.File.outbox)
        }
    }

    private func setStatus(_ id: UUID, _ status: DeliveryStatus) {
        if let index = feed.firstIndex(where: { $0.id == id }) {
            feed[index].status = status
            store.save(feed, to: LocalStore.File.feed)
        } else if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].status = status
            store.save(messages, to: LocalStore.File.messages)
        }
    }

    // MARK: - Receiving

    /// Sends what's waiting and fetches what's new. `full` also re-syncs the friend list and
    /// your own archive of sent posts and messages, which is how a new phone gets its history back.
    /// Like `flushOutbox`, a call made during a sync waits for it and then syncs again.
    func sync(full: Bool = false) async {
        while let running = syncTask {
            await running.value
        }
        guard phase == .ready, let identity, let backend else { return }
        let task = Task {
            isSyncing = true
            await performSync(full: full, identity: identity, backend: backend)
            isSyncing = false
            syncTask = nil
        }
        syncTask = task
        await task.value
    }

    private func performSync(full: Bool, identity: Identity, backend: any CloudBackend) async {
        do {
            try await backend.checkAccount()
            if full {
                try await syncPrivateData(identity: identity, backend: backend)
            }
            if !subscribedToInbox {
                do {
                    try await backend.subscribe(inbox: identity.inbox.hex)
                    subscribedToInbox = true
                } catch {
                    // Notifications are a nicety; polling still delivers everything.
                }
            }
            await flushOutbox()
            try await receive(from: identity.inbox.hex, backend: backend)
            if full {
                try await receive(from: identity.archive.hex, backend: backend)
            }
            cloudWarning = nil
        } catch BackendError.noAccount {
            cloudWarning = "SIGN IN TO ICLOUD TO SEND AND RECEIVE"
        } catch {
            cloudWarning = "OFFLINE - WILL RETRY"
        }
    }

    private func syncPrivateData(identity: Identity, backend: any CloudBackend) async throws {
        if let profile {
            try await backend.saveProfile(CloudProfile(playerID: identity.id, profile: profile))
        }
        let remote = try await backend.fetchFriends()
        let localIDs = Set(friends.map(\.id))
        let remoteIDs = Set(remote.map(\.id))
        let restored = remote.filter { !localIDs.contains($0.id) && $0.id != identity.id }
        if !restored.isEmpty {
            friends = (friends + restored).sorted { $0.addedAt > $1.addedAt }
            store.save(friends, to: LocalStore.File.friends)
        }
        let missing = friends.filter { !remoteIDs.contains($0.id) }
        if !missing.isEmpty {
            try await backend.saveFriends(missing)
        }
    }

    private func receive(from inbox: String, backend: any CloudBackend) async throws {
        let cursor = syncState.cursors[inbox]
        let records = try await backend.fetchEnvelopes(inbox: inbox, since: cursor?.date)
        guard !records.isEmpty else { return }

        var next = cursor ?? SyncState.Cursor(date: .distantPast, seen: [])
        for record in records {
            if let cursor {
                if record.createdAt < cursor.date { continue }
                if record.createdAt == cursor.date, cursor.seen.contains(record.recordName) { continue }
            }
            process(record)
            if record.createdAt > next.date {
                next = SyncState.Cursor(date: record.createdAt, seen: [record.recordName])
            } else if record.createdAt == next.date {
                next.seen.insert(record.recordName)
            }
        }
        syncState.cursors[inbox] = next
        feed.sort { $0.createdAt > $1.createdAt }
        messages.sort { $0.sentAt < $1.sentAt }
        saveEverything()
    }

    private func process(_ record: ReceivedEnvelope) {
        guard let identity else { return }
        let friendKeys = Dictionary(friends.map { ($0.id, $0.card.signingKey) }, uniquingKeysWith: { first, _ in first })
        let opened = EnvelopeCodec.open(record.blob, identity: identity) { id in
            id == identity.id ? identity.signingPublicKey : friendKeys[id]
        }
        guard let envelope = opened else { return }
        let fromMe = envelope.from == identity.id
        // Never trust a sender's clock to put something above what the server saw.
        let at = min(envelope.sentAt, record.createdAt)

        switch envelope.body {
        case .post(let post):
            guard !feed.contains(where: { $0.id == post.id }) else { return }
            feed.append(FeedPost(
                id: post.id, author: envelope.from, text: Self.clean(post.text, limit: Self.maxPostLength),
                photo: post.photo.flatMap(Self.validPhoto), createdAt: at, status: .sent
            ))

        case .deletePost(let id):
            feed.removeAll { $0.id == id && $0.author == envelope.from }

        case .chat(let chat):
            let conversation = fromMe ? chat.peer : envelope.from
            guard fromMe || chat.peer == identity.id,
                  isFriend(conversation),
                  !messages.contains(where: { $0.id == chat.id }) else { return }
            messages.append(ChatMessage(
                id: chat.id, conversation: conversation, from: envelope.from,
                text: Self.clean(chat.text, limit: Self.maxMessageLength),
                photo: chat.photo.flatMap(Self.validPhoto), sentAt: at, receivedAt: now(), status: .sent
            ))

        case .profile(let card):
            guard !fromMe, card.id == envelope.from,
                  let index = friends.firstIndex(where: { $0.id == card.id }) else { return }
            friends[index].card = card
            let updated = friends[index]
            Task { try? await backend?.saveFriends([updated]) }

        case .unfriend:
            guard !fromMe else { return }
            forget(envelope.from)
        }
    }

    // MARK: - Helpers

    private static func clean(_ text: String, limit: Int) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    private static func validPhoto(_ ref: AttachmentRef) -> AttachmentRef? {
        ref.isValid ? ref : nil
    }

    private func saveEverything() {
        store.save(friends, to: LocalStore.File.friends)
        store.save(feed, to: LocalStore.File.feed)
        store.save(messages, to: LocalStore.File.messages)
        store.save(outbox, to: LocalStore.File.outbox)
        store.save(syncState, to: LocalStore.File.sync)
    }
}
