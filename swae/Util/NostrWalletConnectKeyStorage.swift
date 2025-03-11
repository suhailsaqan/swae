//
//  NostrWalletConnectKeyStorage.swift
//  swae
//
//  Created by Suhail Saqan on 3/6/25.
//

import Foundation
import NostrSDK
import Security

class NostrWalletConnectKeyStorage {

    static let shared = NostrWalletConnectKeyStorage()

    private let service = "swae-nostr-wallet-connect-keys"

    func nostrWalletConnectURL(for publicKey: PublicKey) -> WalletConnectURL? {
        let query =
            [
                kSecAttrService: service,
                kSecAttrAccount: publicKey.hex,
                kSecClass: kSecClassGenericPassword,
                kSecReturnData: kCFBooleanTrue!,
                kSecMatchLimit: kSecMatchLimitOne
            ] as [CFString: Any] as CFDictionary

        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)

        if status == errSecSuccess, let data = result as? Data {
            return WalletConnectURL(str: String(decoding: data, as: UTF8.self))
        } else {
            return nil
        }
    }

    func store(publicKey: PublicKey, walletConnectURL: WalletConnectURL) {
        let query =
            [
                kSecAttrService: service,
                kSecAttrAccount: publicKey.hex,
                kSecClass: kSecClassGenericPassword,
                kSecValueData: walletConnectURL.to_url().absoluteString.data(using: .utf8) as Any,
            ] as [CFString: Any] as CFDictionary

        var status = SecItemAdd(query, nil)

        if status == errSecDuplicateItem {
            let query =
                [
                    kSecAttrService: service,
                    kSecAttrAccount: walletConnectURL.pubkey.hex,
                    kSecClass: kSecClassGenericPassword,
                ] as [CFString: Any] as CFDictionary

            let updates =
                [
                    kSecValueData: walletConnectURL.to_url().absoluteString.data(using: .utf8) as Any
                ] as CFDictionary

            status = SecItemUpdate(query, updates)
        }
    }

    func delete(for publicKey: PublicKey) {
        let query =
            [
                kSecAttrService: service,
                kSecAttrAccount: publicKey.hex,
                kSecClass: kSecClassGenericPassword,
            ] as [CFString: Any] as CFDictionary

        _ = SecItemDelete(query)
    }
}
