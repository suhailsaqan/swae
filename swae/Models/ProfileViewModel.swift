//
//  ProfileViewModel.swift
//  swae
//
//  Created by Suhail Saqan on 3/1/25.
//

import Combine
import NostrSDK

class ProfileViewModel: ObservableObject {
    @Published var appState: AppState
    let publicKeyHex: String
    @Published var followState: FollowState  // Now a mutable, stored property
    
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState, publicKeyHex: String) {
        self.appState = appState
        self.publicKeyHex = publicKeyHex
        // Initialize followState from appState.
        self.followState = appState.followedPubkeys.contains(publicKeyHex) ? .follows : .unfollows
        
        // Listen for changes in appState and update followState accordingly.
        appState.objectWillChange.sink { [weak self] _ in
            guard let self = self else { return }
            let newState: FollowState = self.appState.followedPubkeys.contains(self.publicKeyHex) ? .follows : .unfollows
            if self.followState != newState {
                self.followState = newState
            }
        }
        .store(in: &cancellables)
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
        return appState.followListEvents[publicKeyHex]?.followedPubkeys.contains(activePublicKey) ?? false
    }
    
    // Encapsulated follow/unfollow action that updates followState.
    func followButtonAction(target: [String]) {
        switch followState {
        case .follows:
            followState = .unfollowing
            var pubkeys: [String] = appState.activeFollowList?.followedPubkeys ?? []
            pubkeys.removeAll { target.contains($0) }
            notify(.unfollow(pubkeys))
        case .following:
            followState = .following
        case .unfollowing:
            followState = .unfollowing
        case .unfollows:
            followState = .following
            var pubkeys: [String] = appState.activeFollowList?.followedPubkeys ?? []
            pubkeys.append(contentsOf: target)
            notify(.follow(pubkeys))
        }
    }
}
