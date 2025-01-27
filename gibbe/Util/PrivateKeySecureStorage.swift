//
//  PrivateKeySecureStorage.swift
//  gibbe
//
//  Created by Suhail Saqan on 8/22/24.
//

import Foundation
import NostrSDK
import Security

class PrivateKeySecureStorage {

    static let shared = PrivateKeySecureStorage()

    private let service = "gibbe-private-keys"

    func keypair(for publicKey: PublicKey) -> Keypair? {
        let query = [
            kSecAttrService: service,
            kSecAttrAccount: publicKey.hex,
            kSecClass: kSecClassGenericPassword,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as [CFString: Any] as CFDictionary

        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)

        if status == errSecSuccess, let data = result as? Data {
            return Keypair(hex: String(decoding: data, as: UTF8.self))
        } else {
            return nil
        }
    }

    func store(for keypair: Keypair) {
        let query = [
            kSecAttrService: service,
            kSecAttrAccount: keypair.publicKey.hex,
            kSecClass: kSecClassGenericPassword,
            kSecValueData: keypair.privateKey.hex.data(using: .utf8) as Any
        ] as [CFString: Any] as CFDictionary

        var status = SecItemAdd(query, nil)

        if status == errSecDuplicateItem {
            let query = [
                kSecAttrService: service,
                kSecAttrAccount: keypair.publicKey.hex,
                kSecClass: kSecClassGenericPassword
            ] as [CFString: Any] as CFDictionary

            let updates = [
                kSecValueData: keypair.privateKey.hex.data(using: .utf8) as Any
            ] as CFDictionary

            status = SecItemUpdate(query, updates)
        }
    }

    func delete(for publicKey: PublicKey) {
        let query = [
            kSecAttrService: service,
            kSecAttrAccount: publicKey.hex,
            kSecClass: kSecClassGenericPassword
        ] as [CFString: Any] as CFDictionary

        _ = SecItemDelete(query)
    }
}
