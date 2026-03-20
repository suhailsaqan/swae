//
//  StreamingBridge.swift
//  swae
//
//  Converts camera streaming data (Model) to live viewer format (LiveStream/LiveActivitiesEvent)
//

import Foundation
import NostrSDK

/// Bridge between camera streaming system and live viewer system
class StreamingBridge {
    
    // MARK: - LiveStream Creation
    
    /// Creates a LiveStream from Model's streaming data
    static func createLiveStream(from model: Model) -> LiveStream {
        return LiveStream(
            id: model.currentStreamId.uuidString,
            title: model.stream.name.isEmpty ? "Untitled Stream" : model.stream.name,
            thumbnailURL: nil,  // Camera app doesn't have thumbnail
            videoURL: createVideoURL(from: model),
            isLive: model.isLive,
            viewerCount: 0,  // TODO: Get from model if available
            startDate: model.streamStartTime.map { Date(timeIntervalSinceNow: -$0.duration(to: .now).seconds) } ?? Date(),
            streamerName: "You",  // It's the user's own stream
            streamerAvatarURL: nil,
            status: model.isLive ? "live" : "offline"
        )
    }
    
    /// Updates an existing LiveStream with current Model data
    static func updateLiveStream(_ liveStream: inout LiveStream, from model: Model) {
        // LiveStream is a struct, so we need to create a new one
        liveStream = createLiveStream(from: model)
    }
    
    // MARK: - LiveActivitiesEvent Creation
    
    /// Creates a LiveActivitiesEvent from Model's streaming data
    /// Returns the event if the user is streaming to a Nostr-compatible platform
    /// and has an active live activities event in AppState
    static func createLiveActivitiesEvent(from model: Model, appState: AppState?) -> LiveActivitiesEvent? {
        guard let appState = appState else {
            print("⚠️ StreamingBridge: No AppState available")
            return nil
        }
        
        // Check if user is streaming to ZapStreamCore (Nostr-based platform)
        if model.stream.zapStreamCoreEnabled {
            // Look for an existing live activities event for this stream
            // The event should have been created when the stream started
            return findLiveActivitiesEvent(for: model, in: appState)
        }
        
        // For non-Nostr platforms, we can't create a LiveActivitiesEvent
        // Chat will show a placeholder instead
        print("ℹ️ StreamingBridge: Not streaming to Nostr platform, chat unavailable")
        return nil
    }
    
    /// Finds the most recent live LiveActivitiesEvent for the current stream.
    /// Uses highest `createdAt` to avoid picking stale events from previous streams.
    private static func findLiveActivitiesEvent(for model: Model, in appState: AppState) -> LiveActivitiesEvent? {
        guard let userPubkey = appState.keypair?.publicKey.hex else {
            print("⚠️ StreamingBridge: No user keypair available")
            return nil
        }
        
        // Find the most recent live event for this user (highest createdAt).
        // Multiple live events can exist if the server crashed without sending "ended"
        // for a previous stream, or if relay propagation is delayed.
        let result = appState.liveActivitiesEvents.values
            .flatMap { $0 }
            .filter { $0.hostPubkeyHex == userPubkey && $0.status == .live }
            .max(by: { $0.createdAt < $1.createdAt })
        
        if result != nil {
            print("✅ StreamingBridge: Found active LiveActivitiesEvent")
        } else {
            print("ℹ️ StreamingBridge: No active LiveActivitiesEvent found for user")
        }
        return result
    }
    
    // MARK: - Chat Availability
    
    /// Checks if chat is available for the current streaming configuration
    static func isChatAvailable(for model: Model, appState: AppState?) -> Bool {
        // Chat requires:
        // 1. User to be logged in (has keypair)
        // 2. Streaming to a Nostr-compatible platform OR viewing a Nostr stream
        // 3. An active LiveActivitiesEvent
        
        guard let appState = appState, appState.keypair != nil else {
            return false
        }
        
        // Check if streaming to ZapStreamCore
        if model.stream.zapStreamCoreEnabled && model.isLive {
            return findLiveActivitiesEvent(for: model, in: appState) != nil
        }
        
        return false
    }
    
    /// Returns a user-friendly message explaining why chat is unavailable
    static func chatUnavailableReason(for model: Model, appState: AppState?) -> String {
        guard let appState = appState else {
            return "Sign in to use chat"
        }
        
        guard appState.keypair != nil else {
            return "Sign in to use chat"
        }
        
        if !model.isLive {
            return "Start streaming to enable chat"
        }
        
        if !model.stream.zapStreamCoreEnabled {
            return "Chat available with Nostr streams"
        }
        
        return "Connecting to chat..."
    }
    
    // MARK: - Helper Methods
    
    /// Creates a video URL from Model's stream configuration
    private static func createVideoURL(from model: Model) -> URL? {
        // For camera streaming, we might not have a playback URL
        // This would be the RTMP/SRT output URL if we want to show it
        
        // Check if streaming to a platform
        if !model.stream.url.isEmpty {
            return URL(string: model.stream.url)
        }
        
        // Check if using RTMP server
        let rtmpServer = model.database.rtmpServer
        if rtmpServer.enabled {
            let port = rtmpServer.port
            return URL(string: "rtmp://localhost:\(port)/live/stream")
        }
        
        return nil
    }
    
    /// Gets viewer count from Model (if available)
    static func getViewerCount(from model: Model) -> Int {
        // TODO: Implement viewer count tracking in Model
        return 0
    }
    
    /// Gets stream duration from Model
    static func getStreamDuration(from model: Model) -> TimeInterval {
        guard let startTime = model.streamStartTime else {
            return 0
        }
        return startTime.duration(to: .now).seconds
    }
    
    /// Formats stream duration as string (e.g., "00:05:23")
    static func formatStreamDuration(from model: Model) -> String {
        let duration = getStreamDuration(from: model)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
