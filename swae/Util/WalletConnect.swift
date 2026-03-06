//
//  WalletConnectURL.swift
//  swae
//
//  Created by Suhail Saqan on 3/6/25.
//

import Foundation
import NostrSDK

struct WalletConnectURL: Equatable {
    static func == (lhs: WalletConnectURL, rhs: WalletConnectURL) -> Bool {
        return lhs.pubkey == rhs.pubkey && lhs.relay == rhs.relay
    }

    let relay: Relay
    let secret: Data  // Shared secret for encryption, not a private key
    let pubkey: PublicKey
    let lud16: String?

    func to_url() -> URL {
        var urlComponents = URLComponents()
        urlComponents.scheme = "nostr+walletconnect"
        urlComponents.host = pubkey.hex
        urlComponents.queryItems = [
            URLQueryItem(name: "relay", value: relay.url.absoluteString),
            URLQueryItem(name: "secret", value: secret.map { String(format: "%02x", $0) }.joined()),
        ]

        if let lud16 {
            urlComponents.queryItems?.append(URLQueryItem(name: "lud16", value: lud16))
        }

        return urlComponents.url!
    }

    init?(str: String) {

        guard let components = URLComponents(string: str) else {
            print("❌ WalletConnectURL: Failed to parse URL components")
            return nil
        }

        guard components.scheme == "nostr+walletconnect" else {
            print("❌ WalletConnectURL: Invalid scheme: \(components.scheme ?? "nil")")
            return nil
        }

        guard let encoded_pubkey = components.path == "" ? components.host : components.path else {
            print("❌ WalletConnectURL: No pubkey found")
            return nil
        }

        guard let pubkey = hex_decode_pubkey(encoded_pubkey) else {
            print("❌ WalletConnectURL: Failed to decode pubkey")
            return nil
        }

        guard let items = components.queryItems else {
            print("❌ WalletConnectURL: No query items")
            return nil
        }

        guard let relay = items.first(where: { qi in qi.name == "relay" })?.value else {
            print("❌ WalletConnectURL: No relay found")
            return nil
        }

        guard let relayURL = URL(string: relay) else {
            print("❌ WalletConnectURL: Invalid relay URL")
            return nil
        }

        guard let relay_url = try? Relay(url: relayURL) else {
            print("❌ WalletConnectURL: Failed to create Relay")
            return nil
        }

        guard let secret = items.first(where: { qi in qi.name == "secret" })?.value else {
            print("❌ WalletConnectURL: No secret found")
            return nil
        }

        print("🔍 WalletConnectURL: Secret length: \(secret.utf8.count)")

        guard secret.utf8.count == 64 else {
            print("❌ WalletConnectURL: Invalid secret length: \(secret.utf8.count)")
            return nil
        }

        guard let decoded = secret.hexDecoded() else {
            print("❌ WalletConnectURL: Failed to decode secret")
            return nil
        }

        let lud16 = items.first(where: { qi in qi.name == "lud16" })?.value

        self = WalletConnectURL(
            pubkey: pubkey, relay: relay_url, secret: Data(decoded), lud16: lud16)

    }

    init(pubkey: PublicKey, relay: Relay, secret: Data, lud16: String?) {
        self.pubkey = pubkey
        self.relay = relay
        self.secret = secret
        self.lud16 = lud16
    }
}

struct WalletRequest<T: Codable>: Codable {
    let method: String
    let params: T?
}

// These types are now defined in NWCModels.swift

// These enums are now defined in NostrWalletConnectService.swift

// FullWalletResponse removed - now handled by NostrWalletConnectService

// WalletResponse is now defined in NostrWalletConnectService.swift
