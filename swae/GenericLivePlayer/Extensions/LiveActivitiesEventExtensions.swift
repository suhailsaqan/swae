//
//  LiveActivitiesEventExtensions.swift
//  swae
//
//  Extension to convert LiveActivitiesEvent to LiveStream for GenericLivePlayer
//

import Foundation
import NostrSDK

extension LiveActivitiesEvent {
    /// Convert LiveActivitiesEvent to LiveStream for use with GenericLivePlayer
    func toLiveStream() -> LiveStream {
        // Use staleness-aware live check (matches StreamCardCell badge logic)
        // This prevents ghost streams (status == .live but 24hr+ stale) from
        // showing "LIVE" in the player while the card shows "ENDED"
        let isCurrentlyLive = isActuallyLive

        // Use recording URL if available, otherwise use streaming URL —
        // but ONLY use streaming URL if the stream is actually live.
        // A dead streaming URL (ghost/ended stream) causes an infinite spinner.
        let videoURL: URL? = {
            if let rec = recording { return rec }
            if isCurrentlyLive, let stream = streaming { return stream }
            return nil  // Not playable: ended with no recording
        }()

        // Extract thumbnail from image
        let thumbnailURL = image

        // Use the startsAt date for when stream started, or convert createdAt from timestamp
        let startDate: Date = {
            if let startsAt = startsAt {
                return startsAt
            }
            return Date(timeIntervalSince1970: TimeInterval(createdAt))
        }()

        // Get host participant pubkey (for future metadata lookup)
        let hostPubkey =
            hostPubkeyHex

        return LiveStream(
            id: id,
            title: title ?? "Untitled Stream",
            thumbnailURL: thumbnailURL,
            videoURL: videoURL,
            isLive: isCurrentlyLive,
            viewerCount: currentParticipants,
            startDate: startDate,
            streamerName: "Streamer",  // Can be enhanced to fetch from AppState.metadataEvents
            streamerAvatarURL: nil,
            status: status?.rawValue ?? "live",
            hasRecording: recording != nil,
            recordingURL: recording,
            streamingURL: streaming
        )
    }
}
