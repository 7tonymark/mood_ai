import Foundation
import Security

/// Keeps the player's private keys in iCloud Keychain.
///
/// The item is marked synchronizable, so Apple's end-to-end encrypted keychain sync carries it
/// to the owner's other devices, and to a replacement phone. Without iCloud Keychain the keys
/// stay on this phone only, and a new phone means a new player.
struct KeychainIdentityStore: IdentityStoring {
    struct KeychainError: Error {
        var status: OSStatus
    }

    private let service = "proximity.identity"
    private let account = "player"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true,
        ]
    }

    func load() -> Identity? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? Identity(exported: data)
    }

    func save(_ identity: Identity) throws {
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = try identity.exported()
        // Synchronizable items can't be "this device only"; after-first-unlock lets a
        // notification-triggered launch read the keys too.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}
