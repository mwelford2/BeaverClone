import Foundation
import Security

public final class KeychainStore {
    public static let shared = KeychainStore()

    private init() {}

    private let service = "com.example.beaverclone"

    public func write(key: String, value: String) {
        let data = Data(value.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        if value.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }

        query[kSecValueData as String] = data
        query[kSecAttrSynchronizable as String] = kCFBooleanTrue

        let attributesToUpdate: [String: Any] = [kSecValueData as String: data]
        let status = SecItemCopyMatching(query as CFDictionary, nil)

        if status == errSecSuccess {
            let matchQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]
            SecItemUpdate(matchQuery as CFDictionary, attributesToUpdate as CFDictionary)
        } else {
            SecItemAdd(query as CFDictionary, nil)
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
