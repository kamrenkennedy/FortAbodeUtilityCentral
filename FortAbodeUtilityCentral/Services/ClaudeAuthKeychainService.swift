import Foundation
import Security

// MARK: - Claude Auth Keychain Service

/// Stores the user's Claude Code OAuth token in the macOS Keychain so the
/// embedded engine runner can authenticate without relying on `launchctl
/// setenv` (which resets on reboot) or shell-only `export` (which a GUI app
/// never inherits). Keychain survives reboots and is encrypted at rest.
///
/// Token format is `sk-ant-oat01-...` produced by `claude setup-token`.
enum ClaudeAuthKeychainService {

    private static let service = "com.kamstudios.fortabodeutilitycentral.claudeauth"
    private static let account = "claude-oauth-token"

    private static let expectedPrefix = "sk-ant-oat01-"

    // MARK: - Public

    /// Whether a token is currently stored. Cheap — just checks Keychain
    /// presence, not whether the token is still valid against the API.
    static var hasToken: Bool {
        readKeychain() != nil
    }

    /// Read the stored token. Returns nil if absent. Whitespace-trimmed on
    /// the way out as a belt-and-suspenders against any storage that snuck
    /// in despite the on-write sanitization.
    static func readToken() -> String? {
        guard let raw = readKeychain() else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Sanitize and store a token. Strips all whitespace + newlines and
    /// validates the `sk-ant-oat01-` prefix. Returns true on success.
    /// Designed to absorb pasted input that contains terminal line-wrap
    /// newlines — the most common shape of broken token input.
    @discardableResult
    static func storeToken(_ raw: String) -> Bool {
        let cleaned = raw.unicodeScalars
            .filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
            .map { String($0) }
            .joined()

        guard cleaned.hasPrefix(expectedPrefix), cleaned.count > expectedPrefix.count else {
            return false
        }

        saveToKeychain(cleaned)
        return true
    }

    /// Remove the stored token.
    static func deleteToken() {
        deleteFromKeychain()
    }

    // MARK: - Keychain Operations
    //
    // Mirrors the pattern in KeychainService.swift. Same accessibility class
    // (kSecAttrAccessibleWhenUnlocked) so the runner can read the token
    // whenever the user is logged in to their Mac.

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
