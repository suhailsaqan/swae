//
//  ProfileSettings.swift
//  swae
//
//  Created by Suhail Saqan on 7/6/24.
//

import SwiftData

@Model
final class ProfileSettings {

    @Attribute(.unique) var publicKeyHex: String?

    @Relationship(deleteRule: .cascade) var relayPoolSettings: RelayPoolSettings?
    @Relationship(deleteRule: .cascade) var appearanceSettings: AppearanceSettings?

    init(publicKeyHex: String? = nil) {
        self.publicKeyHex = publicKeyHex
        relayPoolSettings = RelayPoolSettings(publicKeyHex: publicKeyHex)
        appearanceSettings = AppearanceSettings(publicKeyHex: publicKeyHex)
    }
}
