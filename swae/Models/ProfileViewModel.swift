//
//  ProfileViewModel.swift
//  swae
//
//  Created by Suhail Saqan on 3/1/25.
//

import Combine
import Foundation
import NostrSDK

class ProfileViewModel: ObservableObject {
    @Published var appState: AppState
    @Published var publicKeyHex: String
    @Published var followState: FollowState  // Now a mutable, stored property

    /// Profilestr API data — provides followers count, note count, trust scores, etc.
    @Published var profilestrUser: ProfilestrUser?
    private var profilestrFetchTask: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState, publicKeyHex: String) {
        self.appState = appState
        self.publicKeyHex = publicKeyHex
        // Initialize followState from appState.
        self.followState = appState.followedPubkeys.contains(publicKeyHex) ? .follows : .unfollows
        
        // Note: We don't observe appState.objectWillChange here because:
        // 1. It fires BEFORE the change happens, causing race conditions
        // 2. The notification handlers (.followed/.unfollowed) manage state transitions properly
        // 3. ProfileViewController listens to those notifications directly
    }

    // Method to update the publicKeyHex when active profile changes
    func updatePublicKeyHex(_ newPublicKeyHex: String) {
        guard publicKeyHex != newPublicKeyHex else { return }
        publicKeyHex = newPublicKeyHex
        profilestrUser = nil
        // Update follow state for the new profile
        if !newPublicKeyHex.isEmpty {
            followState = appState.followedPubkeys.contains(newPublicKeyHex) ? .follows : .unfollows
            fetchProfilestrData()
        } else {
            followState = .unfollows
        }
    }

    // Other computed properties remain unchanged.
    var profileMetadata: UserMetadata? {
        appState.metadataEvents[publicKeyHex]?.userMetadata
    }

    var profileFollowList: [String] {
        if publicKeyHex == appState.appSettings?.activeProfile?.publicKeyHex {
            return appState.activeFollowList?.followedPubkeys ?? []
        } else {
            return appState.followListEvents[publicKeyHex]?.followedPubkeys ?? []
        }
    }

    var followsYou: Bool {
        guard let activePublicKey = appState.appSettings?.activeProfile?.publicKeyHex else {
            return false
        }
        return appState.followListEvents[publicKeyHex]?.followedPubkeys.contains(activePublicKey)
            ?? false
    }
    
    /// Followers count from Profilestr API (0 if not yet loaded)
    var followersCount: Int {
        profilestrUser?.followersCount ?? 0
    }

    /// Note count from Profilestr API
    var noteCount: Int {
        profilestrUser?.noteCount ?? 0
    }

    /// Total zap amount received from Profilestr API
    var totalZapsReceived: Int {
        profilestrUser?.totalAmountReceived ?? 0
    }

    /// Unix timestamp of when the user joined Nostr
    var timeJoined: Int? {
        profilestrUser?.timeJoined
    }

    /// Combined trust score (0-100) from Profilestr API
    var trustScore: Int? {
        profilestrUser?.trustScores?.combined?.score
    }

    /// Trust level string from Profilestr API
    var trustLevel: String? {
        profilestrUser?.trustScores?.combined?.level
    }

    /// Whether NIP-05 is actually validated (not just present in metadata)
    var isNip05Validated: Bool {
        profilestrUser?.trustScores?.relatr?.components?.validators?.nip05Valid == 1
    }

    /// Fetch enriched profile data from Profilestr API
    func fetchProfilestrData() {
        guard !publicKeyHex.isEmpty else { return }
        profilestrFetchTask?.cancel()
        profilestrFetchTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let user = await ProfilestrAPIClient.shared.fetchUser(pubkey: self.publicKeyHex)
            guard !Task.isCancelled else { return }
            self.profilestrUser = user
        }
    }

    // Encapsulated follow/unfollow action that updates followState.
    func followButtonAction(target: [String]) {
        switch followState {
        case .follows:
            followState = .unfollowing
            var pubkeys: [String] = appState.activeFollowList?.followedPubkeys ?? []
            pubkeys.removeAll { target.contains($0) }
            // Defer notification to next run loop so UI can render loading state
            DispatchQueue.main.async {
                notify(.unfollow(pubkeys))
            }
        case .following:
            // Already in progress, ignore
            break
        case .unfollowing:
            // Already in progress, ignore
            break
        case .unfollows:
            followState = .following
            var pubkeys: [String] = appState.activeFollowList?.followedPubkeys ?? []
            pubkeys.append(contentsOf: target)
            // Defer notification to next run loop so UI can render loading state
            DispatchQueue.main.async {
                notify(.follow(pubkeys))
            }
        }
    }
}
