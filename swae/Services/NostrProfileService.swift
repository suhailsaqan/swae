//
//  NostrProfileService.swift
//  swae
//
//  Created by Suhail Saqan on 3/8/25.
//

import Combine
import Foundation
import NostrSDK
import SwiftData

/// Service that manages Nostr profile data and zap statistics
class NostrProfileService: ObservableObject {
    @Published var profile: MetadataEvent?
    @Published var isLoading = false
    @Published var error: String?
    @Published var zapStats: ZapStats?

    private var cancellables = Set<AnyCancellable>()

    func loadProfile(pubkey: String, appState: AppState) {
        isLoading = true
        error = nil

        // First try to get profile from existing metadata events
        if let existingProfile = appState.metadataEvents.values.first(where: { $0.pubkey == pubkey }
        ) {
            DispatchQueue.main.async {
                self.profile = existingProfile
                self.isLoading = false
                self.loadZapStats(pubkey: pubkey, appState: appState)
            }
            return
        }

        // If not found, subscribe to get the profile
        subscribeToProfileEvents(pubkey: pubkey, appState: appState)

        // Also load zap statistics
        loadZapStats(pubkey: pubkey, appState: appState)
    }

    private func subscribeToProfileEvents(pubkey: String, appState: AppState) {
        // Create filter for metadata events (kind 0)
        let filter = Filter(
            authors: [pubkey],
            kinds: [0],  // Metadata events
            limit: 1
        )

        guard let filter = filter else {
            error = "Failed to create profile filter"
            isLoading = false
            return
        }

        // Listen for changes in metadata events
        appState.$metadataEvents
            .sink { [weak self] metadataEvents in
                self?.processMetadataEvents(metadataEvents, targetPubkey: pubkey)
            }
            .store(in: &cancellables)
    }

    private func processMetadataEvents(
        _ metadataEvents: [String: MetadataEvent], targetPubkey: String
    ) {
        guard let profile = metadataEvents[targetPubkey] else { return }

        DispatchQueue.main.async {
            self.profile = profile
            self.isLoading = false
        }
    }

    private func loadZapStats(pubkey: String, appState: AppState) {
        // Calculate zap statistics for this pubkey
        let sentZaps = appState.zapReceipts.filter { $0.pubkey == pubkey }
        let receivedZaps = appState.zapRequests.filter { $0.recipientPubkey == pubkey }

        let totalSentAmount = sentZaps.reduce(0) { $0 + Int64($1.description?.amount ?? 0) }
        let totalReceivedAmount = receivedZaps.reduce(0) { $0 + Int64($1.amount ?? 0) }

        DispatchQueue.main.async {
            self.zapStats = ZapStats(
                totalSent: sentZaps.count,
                totalReceived: receivedZaps.count,
                totalSentAmount: totalSentAmount,
                totalReceivedAmount: totalReceivedAmount
            )
        }
    }

    func updateProfile(_ profileData: [String: Any], appState: AppState) async throws {
        guard let keypair = appState.keypair else {
            throw NostrProfileError.noKeypair
        }

        // Create new metadata event using Builder pattern
        let userMetadata = UserMetadata(
            name: nil,
            displayName: profileData["display_name"] as? String,
            about: profileData["about"] as? String,
            website: (profileData["website"] as? String).flatMap(URL.init),
            nostrAddress: profileData["nip05"] as? String,
            pictureURL: (profileData["picture"] as? String).flatMap(URL.init),
            bannerPictureURL: (profileData["banner"] as? String).flatMap(URL.init),
            lightningAddress: profileData["lud16"] as? String
        )

        let metadataEvent = try MetadataEvent.Builder()
            .userMetadata(userMetadata)
            .build(signedBy: keypair)

        // Publish the event
        appState.relayWritePool.publishEvent(metadataEvent)

        // Update local profile
        DispatchQueue.main.async {
            self.profile = metadataEvent
        }
    }

    func followUser(pubkey: String, appState: AppState) async throws {
        var currentFollows = appState.activeFollowList?.followedPubkeys ?? []
        if !currentFollows.contains(pubkey) {
            currentFollows.append(pubkey)
        }
        notify(.follow(currentFollows))
    }

    func unfollowUser(pubkey: String, appState: AppState) async throws {
        var currentFollows = appState.activeFollowList?.followedPubkeys ?? []
        currentFollows.removeAll { $0 == pubkey }
        notify(.unfollow(currentFollows))
    }

    func isFollowing(pubkey: String, appState: AppState) -> Bool {
        let currentFollows = Array(appState.followedPubkeys)
        return currentFollows.contains(pubkey)
    }
}

enum NostrProfileError: Error, LocalizedError {
    case noKeypair
    case invalidProfileData
    case failedToCreateEvent

    var errorDescription: String? {
        switch self {
        case .noKeypair:
            return "No keypair available"
        case .invalidProfileData:
            return "Invalid profile data"
        case .failedToCreateEvent:
            return "Failed to create profile event"
        }
    }
}
