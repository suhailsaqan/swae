//
//  RelaySubscriptionMetadata.swift
//  swae
//
//  Created by Suhail Saqan on 8/3/24.
//

import Foundation
import SwiftData

@Model
final class RelaySubscriptionMetadata {

    @Attribute(.unique) var publicKeyHex: String?

    var lastBootstrapped = [URL: Date]()
    var lastPulledLiveActivityEvents = [URL: Date]()
    var lastPulledEventsFromFollows = [URL: Date]()

    init(publicKeyHex: String? = nil) {
        self.publicKeyHex = publicKeyHex
    }
}
