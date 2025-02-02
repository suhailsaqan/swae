//
//  RelaySettings.swift
//  gibbe
//
//  Created by Suhail Saqan on 7/11/24.
//

import SwiftData

@Model
final class RelayPoolSettings {

    @Attribute(.unique) var publicKeyHex: String?

    var relaySettingsList: [RelaySettings]

    init(publicKeyHex: String?) {
        self.publicKeyHex = publicKeyHex
        self.relaySettingsList = []
    }
}
