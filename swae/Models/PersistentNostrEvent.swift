//
//  PersistentNostrEvent.swift
//  swae
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

    /// Stored event kind for efficient predicate filtering (e.g., preloading only follow lists).
    /// Default -1 is a sentinel meaning "not yet migrated" for existing rows after schema update.
    /// New inserts always get the correct value from the init.
    var kind: Int = -1
    
    /// Stored creation timestamp for potential future cursor-based pagination.
    /// Default 0 is a sentinel meaning "not yet migrated" for existing rows after schema update.
    var createdAt: Int64 = 0

    var relays: [URL] = []

    init(nostrEvent: NostrEvent, relays: [URL] = []) {
        self.eventId = nostrEvent.id
        self.nostrEvent = nostrEvent
        self.kind = nostrEvent.kind.rawValue
        self.createdAt = nostrEvent.createdAt
        self.relays = relays
    }
}
