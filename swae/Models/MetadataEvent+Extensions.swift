//
//  MetadataEvent+Extensions.swift
//  swae
//
//  Created by Suhail Saqan on 6/29/24.
//

import NostrSDK

extension MetadataEvent {
    var resolvedName: String {
        guard let userMetadata else {
            return Utilities.shared.abbreviatedPublicKey(pubkey)
        }

        if let trimmedDisplayName = userMetadata.displayName?.trimmingCharacters(
            in: .whitespacesAndNewlines), !trimmedDisplayName.isEmpty
        {
            return trimmedDisplayName
        }

        if let trimmedName = userMetadata.name?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmedName.isEmpty
        {
            return trimmedName
        }

        return Utilities.shared.abbreviatedPublicKey(pubkey)
    }
}
