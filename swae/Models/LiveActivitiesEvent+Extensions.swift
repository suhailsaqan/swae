//
//  LiveActivitiesEvent+Extensions.swift
//  swae
//
//  Created by Suhail Saqan on 12/7/24.
//

import Foundation

#if canImport(NostrSDK)
    import NostrSDK

    extension LiveActivitiesEvent {
        
        // MARK: - Staleness Detection (NIP-53 Compliance)
        
        /// Maximum age (in seconds) before a "live" event is considered stale.
        /// Per NIP-53: "Clients MAY choose to consider status=live events after 1hr without any update as ended"
        private static let maxLiveAge: TimeInterval = 3600  // 1 hour
        
        /// Maximum age (in seconds) before a "live" status is considered a ghost stream.
        /// Even if status == .live, if no update in 24 hours, it's definitely dead.
        private static let maxGhostAge: TimeInterval = 86400  // 24 hours
        
        /// Whether this event is stale (hasn't been updated in over 1 hour).
        /// Uses `createdDate` which represents when the event was last created/updated.
        var isStale: Bool {
            let eventAge = Date.now.timeIntervalSince(createdDate)
            return eventAge > Self.maxLiveAge
        }
        
        /// Whether this event is a ghost stream (claims live but no update in 24+ hours).
        /// This catches streams where the streamer's software crashed without sending `ended`.
        var isGhostStream: Bool {
            let eventAge = Date.now.timeIntervalSince(createdDate)
            return eventAge > Self.maxGhostAge
        }
        
        /// Improved isLive that accounts for staleness per NIP-53 recommendation.
        /// Use this instead of `isLive` to avoid showing ghost streams.
        ///
        /// Logic:
        /// 1. If explicitly ended → not live
        /// 2. If explicitly live but ghost (24hr+ stale) → not live (crashed streamer)
        /// 3. If explicitly live and recent → trust it (handles long-running streams)
        /// 4. If no status and stale (1hr+) → not live (NIP-53 recommendation)
        /// 5. Otherwise use timestamp-based logic
        var isActuallyLive: Bool {
            // If explicitly ended, definitely not live
            if status == .ended { return false }
            
            // If explicitly live, check for ghost stream
            if status == .live {
                // Ghost stream detection: 24hr+ without update = dead
                // This catches "Woodstock 99" type streams
                if isGhostStream { return false }
                
                // Trust recent "live" status (handles "NoGood Radio" type streams)
                return true
            }
            
            // No explicit status: use 1hr staleness heuristic (NIP-53)
            if isStale { return false }
            
            // Otherwise use existing isLive logic (based on startsAt/endsAt)
            return isLive
        }
        
        // MARK: - Original Status Properties
        
        var isLive: Bool {
            if status == .live { return true }
            if let startsAt {
                if let endsAt { return startsAt <= Date.now && endsAt >= Date.now }
                return startsAt <= Date.now
            }
            return false
        }

        var isReplay: Bool {
            // A stream is a replay if:
            // 1. It has explicitly ended (status == .ended), OR
            // 2. It's a ghost stream (status == .live but 24hr+ stale), OR
            // 3. It's stale (no update in 1hr per NIP-53) AND has a past start time
            //
            // Ghost streams (Woodstock 99) should appear in replays, not live
            if status == .ended {
                return true   // Explicitly ended = is a replay
            }
            if status == .live {
                // Ghost stream goes to replays
                if isGhostStream { return true }
                return false  // Recent live = not a replay
            }
            // No explicit status: use staleness + past check
            return isStale && isPast
        }
        
        var isUpcoming: Bool {
            guard let startsAt else {
                return false
            }

            guard let endsAt else {
                return startsAt >= Date.now
            }
            return startsAt >= Date.now || endsAt >= Date.now
        }

        var isPast: Bool {
            guard let startsAt else {
                return false
            }

            guard let endsAt else {
                return startsAt < Date.now
            }
            return endsAt < Date.now
        }

        /// Best-effort current participants count per NIP-53. Falls back to participant list size.
        var currentParticipants: Int {
            if let raw = firstValueForRawTagName("current_participants"), let value = Int(raw) {
                return value
            }
            // Fallback: derive from participants array if tag missing
            return participants.count
        }

        /// Internal category tags (only tags that start with "internal:").
        /// NOTE: Kept for backwards compatibility but largely empty for real streams.
        var internalTags: [String] {
            hashtags.filter { $0.hasPrefix("internal:") }
        }

        /// Returns all matching StreamCategories based on the event's `t` tags.
        /// Uses the precomputed `StreamCategory.tagLookup` for O(1) per-tag matching.
        var matchedCategories: [StreamCategory] {
            var seen = Set<String>()
            var result: [StreamCategory] = []
            for tag in hashtags {
                if let cats = StreamCategory.tagLookup[tag.lowercased()] {
                    for cat in cats where seen.insert(cat.id).inserted {
                        result.append(cat)
                    }
                }
            }
            return result
        }

        /// Convenience popularity score used for sorting lists.
        var popularityScore: Int { currentParticipants }
    }
#endif
