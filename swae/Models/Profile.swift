//
//  Profile.swift
//  swae
//
//  Created by Suhail Saqan on 7/6/24.
//

import SwiftData

@Model
final class Profile: Hashable {

    @Attribute(.unique) var publicKeyHex: String?

    /// Cached display name from Nostr metadata, persisted locally so the account
    /// picker can show meaningful names before relay metadata loads.
    var cachedDisplayName: String?
    var cachedUsername: String?
    var cachedProfilePictureURL: String?

    @Relationship(deleteRule: .cascade) var profileSettings: ProfileSettings?

    @Relationship(deleteRule: .cascade) var relaySubscriptionMetadata: RelaySubscriptionMetadata?

    init(publicKeyHex: String? = nil) {
        self.publicKeyHex = publicKeyHex
        self.profileSettings = ProfileSettings(publicKeyHex: publicKeyHex)
        self.relaySubscriptionMetadata = RelaySubscriptionMetadata(publicKeyHex: publicKeyHex)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(publicKeyHex)
    }
}
