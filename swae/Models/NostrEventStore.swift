//
//  NostrEventStore.swift
//  swae
//
//  Centralized dedupe/replace logic for Nostr events, optimized for LiveActivities (NIP-53).
//

import Foundation
import NostrSDK

private struct ReplaceKey: Hashable {
    let pubkey: String
    let kind: Int
}

private struct AddrKey: Hashable {
    let pubkey: String
    let kind: Int
    let d: String
}

private enum EventClass {
    case ephemeral
    case delete
    case parameterizedReplaceable(AddrKey)
    case replaceable(ReplaceKey)
    case regular
}

private func extractD(_ event: NostrEvent) -> String? {
    // Use SDK helper to fetch the first value for raw tag name "d"
    return event.firstValueForRawTagName("d")
}

private func isEphemeral(kind: Int) -> Bool {
    kind >= 20000 && kind < 30000
}

private func classify(_ event: NostrEvent) -> EventClass {
    if isEphemeral(kind: event.kind.rawValue) { return .ephemeral }
    if event.kind.rawValue == 5 { return .delete }

    // Live chat messages (NIP-53): kind 1311 should be treated as ephemeral for deduplication purposes
    // They don't need strict deduplication since multiple users can send the same content
    if event.kind.rawValue == 1311 { return .ephemeral }
    
    // Live stream raids (NIP-53): kind 1312 should be treated as ephemeral for deduplication purposes
    // Each raid event is unique and should be displayed
    if event.kind.rawValue == 1312 { return .ephemeral }

    // Zap receipts (NIP-57): kind 9735 should be treated as ephemeral for deduplication purposes
    // Multiple zap receipts can have the same content/amount and should all be displayed
    if event.kind.rawValue == 9735 { return .ephemeral }

    // Parameterized replaceable (NIP-33): 30_000–39_999 (e.g., 30311/30312/30313)
    if event.kind.rawValue >= 30000 && event.kind.rawValue < 40000, let d = extractD(event) {
        return .parameterizedReplaceable(
            .init(pubkey: event.pubkey, kind: event.kind.rawValue, d: d))
    }

    // Replaceable (NIP-16): examples include 0, 3, 10000–19999, and 10312 presence is replaceable per NIP-53 text
    if event.kind.rawValue == 0 || event.kind.rawValue == 3
        || (event.kind.rawValue >= 10000 && event.kind.rawValue < 20000)
    {
        return .replaceable(.init(pubkey: event.pubkey, kind: event.kind.rawValue))
    }

    return .regular
}

// Basic expiration handling (NIP-40)
private func isExpired(_ event: NostrEvent, now: Int64) -> Bool {
    if let expirationStr = event.firstValueForRawTagName("expiration"),
        let t = Int64(expirationStr)
    {
        return t <= now
    }
    return false
}

public actor NostrEventStore {
    
    // MARK: - NIP-16 Deduplication Logic
    
    /// NIP-16 tie-breaker for replaceable events: latest created_at wins; if equal, lowest id wins.
    /// This is the single source of truth for Nostr replaceable event deduplication.
    /// Use this for all replaceable event comparisons across the codebase.
    ///
    /// - Parameters:
    ///   - old: The existing event
    ///   - new: The incoming event to compare
    /// - Returns: `true` if the new event should replace the old event
    @inline(__always)
    public static func shouldReplace(old: NostrEvent, with new: NostrEvent) -> Bool {
        if new.createdAt > old.createdAt { return true }
        if new.createdAt < old.createdAt { return false }
        return new.id.lexicographicallyPrecedes(old.id)
    }
    
    // MARK: - Storage
    
    // Set of event IDs for fast deduplication (memory-efficient: only stores IDs, not full events)
    // This replaces the previous [String: NostrEvent] dictionary, saving ~98% memory
    private var seenIds: Set<String> = []

    // Replaceable indexes - these MUST store full events for NIP-16 comparison
    private var replaceable: [ReplaceKey: NostrEvent] = [:]
    private var parameterized: [AddrKey: NostrEvent] = [:]

    // Collection limits to prevent unbounded memory growth
    private let maxSeenIds = 100000  // IDs are small (~64 bytes each), so we can store more
    private let maxReplaceableEntries = 10000
    private let maxParameterizedEntries = 10000

    public init() {}

    public func ingest(_ event: NostrEvent, now: Int64 = Int64(Date().timeIntervalSince1970))
        -> Bool
    {
        // expiration
        if isExpired(event, now: now) { return false }

        // id dedupe (except deletions, live chat messages, raids, and zap receipts which we keep for tombstoning/display)
        if event.kind.rawValue != 5 && event.kind.rawValue != 1311 && event.kind.rawValue != 1312 && event.kind.rawValue != 9735,
            seenIds.contains(event.id)
        {
            return false
        }

        switch classify(event) {
        case .ephemeral:
            // For live chat messages (kind 1311), raids (kind 1312), and zap receipts (kind 9735), 
            // accept them but don't store in indexes. This allows multiple identical messages/zaps 
            // while still tracking them for deduplication.
            if event.kind.rawValue == 1311 || event.kind.rawValue == 1312 || event.kind.rawValue == 9735 {
                seenIds.insert(event.id)
                enforceCollectionLimits()
                return true
            }
            return false

        case .delete:
            // Deletion events are tracked by ID for deduplication, but the actual deletion
            // logic is handled by AppState.deleteFromEventIds() which uses SwiftData
            seenIds.insert(event.id)
            enforceCollectionLimits()
            return true

        case .parameterizedReplaceable(let key):
            if let old = parameterized[key] {
                if Self.shouldReplace(old: old, with: event) {
                    seenIds.insert(event.id)
                    parameterized[key] = event
                    enforceCollectionLimits()
                    return true
                } else {
                    return false
                }
            } else {
                seenIds.insert(event.id)
                parameterized[key] = event
                enforceCollectionLimits()
                return true
            }

        case .replaceable(let key):
            if let old = replaceable[key] {
                if Self.shouldReplace(old: old, with: event) {
                    seenIds.insert(event.id)
                    replaceable[key] = event
                    enforceCollectionLimits()
                    return true
                } else {
                    return false
                }
            } else {
                seenIds.insert(event.id)
                replaceable[key] = event
                enforceCollectionLimits()
                return true
            }

        case .regular:
            seenIds.insert(event.id)
            enforceCollectionLimits()
            return true
        }
    }
    
    /// Enforces memory limits on all collections by removing arbitrary entries when limits are exceeded
    private func enforceCollectionLimits() {
        // Limit seenIds - Sets have no order, so we just remove arbitrary entries
        if seenIds.count > maxSeenIds {
            let toRemoveCount = seenIds.count - maxSeenIds
            for _ in 0..<toRemoveCount {
                if let first = seenIds.first {
                    seenIds.remove(first)
                }
            }
        }
        
        // Limit replaceable - remove oldest entries (by createdAt)
        if replaceable.count > maxReplaceableEntries {
            let sortedByAge = replaceable.sorted { $0.value.createdAt < $1.value.createdAt }
            let toRemove = sortedByAge.prefix(replaceable.count - maxReplaceableEntries)
            for (key, _) in toRemove {
                replaceable.removeValue(forKey: key)
            }
        }
        
        // Limit parameterized - remove oldest entries (by createdAt)
        if parameterized.count > maxParameterizedEntries {
            let sortedByAge = parameterized.sorted { $0.value.createdAt < $1.value.createdAt }
            let toRemove = sortedByAge.prefix(parameterized.count - maxParameterizedEntries)
            for (key, _) in toRemove {
                parameterized.removeValue(forKey: key)
            }
        }
    }

}
