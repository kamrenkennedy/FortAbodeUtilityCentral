import Foundation
import Security
import CryptoKit

// MARK: - Keychain Service

/// Manages family activation state via the macOS Keychain.
/// Stores a flag indicating the app has been activated with the correct family code.
/// Keychain entries persist across app updates, are encrypted by macOS, and are
/// tied to the user's macOS account.
enum KeychainService {

    private static let service = "com.kamstudios.fortabodeutilitycentral"
    private static let account = "family-activation"

    // SHA-256 hash of the family code — the plaintext code is never stored in the binary.
    // To generate: echo -n "YOUR_CODE" | shasum -a 256
    private static let activationCodeHash = "d814e6ed57d4005258e8bdc6ca6f98b4d70e842bc496544820c266655d7c5f9f"

    // MARK: - Public

    /// Check if the app is already activated via Keychain.
    static var isActivated: Bool {
        readKeychain() == "activated"
    }

    /// Validate a code against the stored hash. If correct, persist activation to Keychain.
    /// Returns `true` if the code was correct and activation was saved.
    @discardableResult
    static func activate(with code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hash(trimmed) == activationCodeHash else { return false }
        saveToKeychain("activated")
        return true
    }

    /// Remove activation (for debugging/testing only).
    static func deactivate() {
        deleteFromKeychain()
    }

    // MARK: - Hashing

    /// SHA-256 hash of the input string, returned as a lowercase hex string.
    static func hash(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Keychain Operations

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveToKeychain(_ value: String) {
        // Delete existing entry first (idempotent)
        deleteFromKeychain()

        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    private static func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
