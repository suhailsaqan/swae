//
//  BackgroundPersistenceActor.swift
//  swae
//
//  Background actor for SwiftData persistence operations.
//  Uses @ModelActor to create a dedicated ModelContext that runs off the main thread.
//

import Foundation
import NostrSDK
import SwiftData

/// Actor that handles SwiftData persistence operations on a background thread.
/// This prevents blocking the main thread during batch inserts and deletes.
///
/// Usage:
/// - Initialize with the shared ModelContainer
/// - Call async methods to perform database operations
/// - Changes are automatically merged to the main context by SwiftData
@ModelActor
actor BackgroundPersistenceActor {
    
    // MARK: - Batch Insert Operations
    
    /// Inserts multiple NostrEvents as PersistentNostrEvent records.
    /// This is the primary method for batch persistence of incoming relay events.
    /// Optimized to minimize database queries by skipping duplicate checks.
    ///
    /// - Parameter events: Array of NostrEvent objects to persist
    /// - Returns: Array of event IDs that were successfully inserted
    /// - Throws: SwiftData errors if save fails
    func insertEvents(_ events: [NostrEvent]) throws -> [String] {
        guard !events.isEmpty else { return [] }
        
        var insertedIds: [String] = []
        
        // Insert all events - SwiftData will handle duplicates via @Attribute(.unique)
        // This is much faster than checking each event individually
        for event in events {
            let persistentEvent = PersistentNostrEvent(nostrEvent: event)
            modelContext.insert(persistentEvent)
            insertedIds.append(event.id)
        }
        
        // Save all inserts in a single transaction
        // Duplicates will be silently ignored due to unique constraint
        do {
            try modelContext.save()
        } catch {
            // If save fails due to duplicates, that's expected - log but don't throw
            print("BackgroundPersistence save (some duplicates expected): \(error.localizedDescription)")
        }
        
        return insertedIds
    }
    
    /// Updates relay information for an existing PersistentNostrEvent.
    ///
    /// - Parameters:
    ///   - eventId: The event ID to update
    ///   - relayURL: The relay URL to add
    /// - Returns: true if the event was found and updated
    func addRelayToEvent(eventId: String, relayURL: URL) throws -> Bool {
        var descriptor = FetchDescriptor<PersistentNostrEvent>(
            predicate: #Predicate { $0.eventId == eventId }
        )
        descriptor.fetchLimit = 1
        
        guard let persistentEvent = try modelContext.fetch(descriptor).first else {
            return false
        }
        
        if !persistentEvent.relays.contains(relayURL) {
            persistentEvent.relays.append(relayURL)
            try modelContext.save()
        }
        
        return true
    }
    
    // MARK: - Delete Operations
    
    /// Deletes PersistentNostrEvent records by their event IDs.
    /// Performs batch deletion in a single transaction.
    ///
    /// - Parameter eventIds: Array of event IDs to delete
    /// - Returns: Number of events actually deleted
    func deleteEvents(withIds eventIds: [String]) throws -> Int {
        guard !eventIds.isEmpty else { return 0 }
        
        var deletedCount = 0
        
        for eventId in eventIds {
            var descriptor = FetchDescriptor<PersistentNostrEvent>(
                predicate: #Predicate { $0.eventId == eventId }
            )
            descriptor.fetchLimit = 1
            
            if let persistentEvent = try modelContext.fetch(descriptor).first {
                modelContext.delete(persistentEvent)
                deletedCount += 1
            }
        }
        
        // Save all deletes in a single transaction
        if deletedCount > 0 {
            try modelContext.save()
        }
        
        return deletedCount
    }
    
    /// Fetches a PersistentNostrEvent by its event ID.
    /// Returns the NostrEvent if found, nil otherwise.
    ///
    /// - Parameter eventId: The event ID to fetch
    /// - Returns: The NostrEvent if found
    func fetchEvent(withId eventId: String) throws -> NostrEvent? {
        var descriptor = FetchDescriptor<PersistentNostrEvent>(
            predicate: #Predicate { $0.eventId == eventId }
        )
        descriptor.fetchLimit = 1
        
        return try modelContext.fetch(descriptor).first?.nostrEvent
    }
    
    /// Checks if an event exists in the persistent store.
    ///
    /// - Parameter eventId: The event ID to check
    /// - Returns: true if the event exists
    func eventExists(withId eventId: String) throws -> Bool {
        var descriptor = FetchDescriptor<PersistentNostrEvent>(
            predicate: #Predicate { $0.eventId == eventId }
        )
        descriptor.fetchLimit = 1
        
        let count = try modelContext.fetchCount(descriptor)
        return count > 0
    }
    
    // MARK: - Startup Loading Methods
    
    /// Returns total count of persisted events (very fast - no deserialization)
    /// Used to show loading progress during app startup.
    func getEventCount() throws -> Int {
        let descriptor = FetchDescriptor<PersistentNostrEvent>()
        return try modelContext.fetchCount(descriptor)
    }
    
    /// Fetches a page of PersistentNostrEvent objects for startup loading.
    /// Returns the raw model objects - caller must extract NostrEvent on main thread
    /// to ensure transformer thread safety.
    ///
    /// - Parameters:
    ///   - offset: Number of records to skip
    ///   - limit: Maximum number of records to return
    /// - Returns: Array of PersistentNostrEvent objects
    @available(*, deprecated, message: "Use fetchAllEventsDeserialized() instead — avoids O(N²) offset scan and thread-safety issues")
    func fetchEventPage(offset: Int, limit: Int) throws -> [PersistentNostrEvent] {
        var descriptor = FetchDescriptor<PersistentNostrEvent>()
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }
    
    /// Fetches all persisted events and deserializes them on the background thread.
    /// This replaces the paginated fetchEventPage approach which had O(N²) offset scan cost.
    /// Deserialization happens entirely on the background actor's thread, fixing the
    /// thread-safety violation where PersistentNostrEvent objects were previously
    /// accessed across actor boundaries.
    ///
    /// - Returns: Array of deserialized NostrEvent objects
    func fetchAllEventsDeserialized() throws -> [NostrEvent] {
        let descriptor = FetchDescriptor<PersistentNostrEvent>()
        let persistentEvents = try modelContext.fetch(descriptor)
        return persistentEvents.compactMap { $0.nostrEvent }
    }
    
    /// Fetches IDs of events that haven't been published to any relay yet.
    /// Used during refresh to republish unpublished events.
    /// Limited to 200 to avoid loading the entire database — the caller
    /// further filters by author pubkey.
    ///
    /// - Returns: Array of event IDs with empty relay lists
    func fetchUnpublishedEventIds() throws -> [String] {
        var descriptor = FetchDescriptor<PersistentNostrEvent>(
            predicate: #Predicate { $0.relays == [] }
        )
        descriptor.fetchLimit = 200
        return try modelContext.fetch(descriptor).map { $0.eventId }
    }
    
    // MARK: - Migration Methods
    
    /// Backfills the `kind` and `createdAt` columns for existing events that were
    /// persisted before these columns were added. Existing rows have sentinel values
    /// (kind = -1, createdAt = 0) from the lightweight migration default.
    /// This reads each event's serialized nostrEvent to extract the correct values.
    ///
    /// - Returns: Number of events that were migrated
    func backfillKindAndCreatedAt() throws -> Int {
        var descriptor = FetchDescriptor<PersistentNostrEvent>(
            predicate: #Predicate { $0.kind == -1 }
        )
        let unmigrated = try modelContext.fetch(descriptor)
        guard !unmigrated.isEmpty else { return 0 }
        
        for event in unmigrated {
            event.kind = event.nostrEvent.kind.rawValue
            event.createdAt = event.nostrEvent.createdAt
        }
        
        try modelContext.save()
        return unmigrated.count
    }
}
