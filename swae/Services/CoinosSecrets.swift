//
//  CoinosSecrets.swift
//  swae
//
//  Secure storage for the Coinos API key using the iOS Keychain.
//

import Foundation
import Security

/// Manages secure storage and retrieval of the Coinos API key via the iOS Keychain.
///
/// The API key is never hardcoded in source. It is written to the Keychain once
/// (e.g. on first launch or via a config step) and read from there on every request.
enum CoinosSecrets {

    private static let service = "io.swae.coinos"
    private static let account = "api-key"

    /// Stores the API key in the Keychain. Overwrites any existing value.
    @discardableResult
    static func setApiKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        // Delete any existing entry first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieves the API key from the Keychain. Returns `nil` if not found.
    static func getApiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes the API key from the Keychain.
    @discardableResult
    static func deleteApiKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Seeds the API key into the Keychain if it isn't already present.
    /// Call this once during app startup.
    static func bootstrapIfNeeded() {
        if getApiKey() == nil {
            // Read from the gitignored CoinosApiKey.swift constant
            setApiKey(coinosApiKey)
        }
    }
}
