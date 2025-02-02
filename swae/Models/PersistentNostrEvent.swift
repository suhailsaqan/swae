//
//  PersistentNostrEvent.swift
//  gibbe
//
//  Created by Suhail Saqan on 7/23/24.
//

import Foundation
import NostrSDK
import SwiftData

@Model
class PersistentNostrEvent {
    @Attribute(.unique) let eventId: String

    @Attribute(.transformable(by: NostrEventValueTransformer.self)) let nostrEvent: NostrEvent

    var relays: [URL] = []

    init(nostrEvent: NostrEvent, relays: [URL] = []) {
        self.eventId = nostrEvent.id
        self.nostrEvent = nostrEvent
        self.relays = relays
    }
}
