//
//  Utilities.swift
//  swae
//
//  Created by Suhail Saqan on 7/9/24.
//

import Foundation
import NostrSDK
import SwiftUI

class Utilities {
    static let shared = Utilities()

    func profileName(publicKeyHex: String?, appState: AppState) -> String {
        if let publicKeyHex {
            if let resolvedName = appState.metadataEvents[publicKeyHex]?.resolvedName {
                return resolvedName
            } else {
                return abbreviatedPublicKey(publicKeyHex)
            }
        } else {
            //            return String(localized: .localizable.guest)
            return String("guest")
        }
    }

    func abbreviatedPublicKey(_ publicKeyHex: String) -> String {
        if let publicKey = PublicKey(hex: publicKeyHex) {
            return abbreviatedPublicKey(publicKey)
        } else {
            return publicKeyHex
        }
    }

    func abbreviatedPublicKey(_ publicKey: PublicKey) -> String {
        return "\(publicKey.npub.prefix(12)):\(publicKey.npub.suffix(12))"
    }

    func externalNostrProfileURL(npub: String) -> URL? {
        if let nostrURL = URL(string: "nostr:\(npub)"), UIApplication.shared.canOpenURL(nostrURL) {
            return nostrURL
        }
        if let njumpURL = URL(string: "https://njump.me/\(npub)"),
            UIApplication.shared.canOpenURL(njumpURL)
        {
            return njumpURL
        }
        return nil
    }
}
