//
//  TeslaKeyStorage.swift
//  swae
//
//  Stores the Tesla P256 private key in the iOS Keychain instead of UserDefaults.
//

import Foundation
import Security

final class TeslaKeyStorage {
    static let shared = TeslaKeyStorage()

    private let service = "swae-tesla-keys"
    private let account = "tesla-private-key"

    private init() {}

    func store(privateKeyPem: String) {
        guard let data = privateKeyPem.data(using: .utf8) else { return }

        let query = [
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ] as [CFString: Any] as CFDictionary

        let status = SecItemAdd(query, nil)

        if status == errSecDuplicateItem {
            let searchQuery = [
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecClass: kSecClassGenericPassword,
            ] as [CFString: Any] as CFDictionary

            let updates = [
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ] as [CFString: Any] as CFDictionary

            SecItemUpdate(searchQuery, updates)
        }
    }

    func load() -> String? {
        let query = [
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
            kSecReturnData: kCFBooleanTrue!,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as [CFString: Any] as CFDictionary

        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func delete() {
        let query = [
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
        ] as [CFString: Any] as CFDictionary

        SecItemDelete(query)
    }
}
