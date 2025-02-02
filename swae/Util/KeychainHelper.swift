//
//  KeychainHelper.swift
//  swae
//
//  Created by Suhail Saqan on 9/8/24.
//

import Foundation
import Security

class KeychainHelper: ObservableObject {
    static let shared = KeychainHelper()

    @Published var secretKey: String? = nil

    private init() {
        loadSecretKey()
    }

    func save(key: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]

        SecItemDelete(query as CFDictionary)  // Delete any existing items

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            loadSecretKey()
            return true
        }
        return false
    }

    func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var dataTypeRef: AnyObject? = nil
        let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess {
            return dataTypeRef as? Data
        } else {
            return nil
        }
    }

    private func loadSecretKey() {
        if let data = load(key: "my_secret_key") {
            secretKey = String(data: data, encoding: .utf8)
        }
    }

    func saveSecretKey(_ key: String) -> Bool {
        if let data = key.data(using: .utf8) {
            return save(key: "my_secret_key", data: data)
        }
        return false
    }

    func deleteSecretKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "my_secret_key",
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            secretKey = nil
            return true
        }
        return false
    }
}
