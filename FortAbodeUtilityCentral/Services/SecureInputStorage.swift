import Foundation
import Security

/// Keychain wrapper for storing secrets collected during setup wizards.
/// Uses the same Keychain patterns as KeychainService but with per-component scoping.
enum SecureInputStorage {

    private static let serviceBase = "com.kamstudios.fortabodeutilitycentral.setup"

    // MARK: - Public API

    /// Save a secret value for a component's field.
    @discardableResult
    static func save(componentId: String, fieldName: String, value: String) -> Bool {
        let account = "\(componentId).\(fieldName)"
        deleteFromKeychain(account: account)

        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceBase,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Read a stored secret for a component's field.
    static func read(componentId: String, fieldName: String) -> String? {
        let account = "\(componentId).\(fieldName)"
        return readFromKeychain(account: account)
    }

    /// Delete a specific field's secret.
    static func delete(componentId: String, fieldName: String) {
        let account = "\(componentId).\(fieldName)"
        deleteFromKeychain(account: account)
    }

    /// Delete all stored secrets for a component (used during uninstall).
    static func deleteAll(componentId: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceBase,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return }

        let prefix = "\(componentId)."
        for item in items {
            if let account = item[kSecAttrAccount as String] as? String,
               account.hasPrefix(prefix) {
                deleteFromKeychain(account: account)
            }
        }
    }

    // MARK: - Private Keychain Operations

    private static func readFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceBase,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private static func deleteFromKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceBase,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
