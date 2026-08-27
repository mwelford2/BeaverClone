import Foundation
import Security

public final class KeychainStore {
    public static let shared = KeychainStore()

    private init() {}

    private let service = "com.example.beaverclone"

    /// Writes to the Keychain and reports whether it actually succeeded. `kSecAttrSynchronizable`
    /// is deliberately NOT set: syncing requires an iCloud Keychain entitlement this app doesn't
    /// declare, and requesting it anyway makes SecItemAdd fail with errSecMissingEntitlement on
    /// ad-hoc/self-signed builds (Feather, AltStore, etc.) — silently, if the caller ignores the
    /// status, which is exactly what made this bug invisible before.
    @discardableResult
    public func write(key: String, value: String) -> Bool {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        if value.isEmpty {
            let status = SecItemDelete(baseQuery as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }

        let data = Data(value.utf8)

        var searchQuery = baseQuery
        searchQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        let searchStatus = SecItemCopyMatching(searchQuery as CFDictionary, nil)

        if searchStatus == errSecSuccess {
            let attributesToUpdate: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)
            if updateStatus != errSecSuccess {
                print("KeychainStore: update failed for key \(key), status \(updateStatus)")
            }
            return updateStatus == errSecSuccess
        } else {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecDuplicateItem {
                // Lost a race with an existing item — fall back to update.
                let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
                if updateStatus != errSecSuccess {
                    print("KeychainStore: fallback update failed for key \(key), status \(updateStatus)")
                }
                return updateStatus == errSecSuccess
            }
            if addStatus != errSecSuccess {
                print("KeychainStore: add failed for key \(key), status \(addStatus)")
            }
            return addStatus == errSecSuccess
        }
    }

    public func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
