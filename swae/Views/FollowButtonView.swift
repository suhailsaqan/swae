//
//  FollowButtonView.swift
//  swae
//
//  Created by Suhail Saqan on 2/26/25.
//


import SwiftUI
import NostrSDK

struct FollowButtonView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var profileViewModel: ProfileViewModel
    
    private var isLoading: Bool {
        profileViewModel.followState == .following || profileViewModel.followState == .unfollowing
    }

    var body: some View {
        Button {
            guard !isLoading else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            profileViewModel.followButtonAction(target: [profileViewModel.publicKeyHex])
        } label: {
            Text(verbatim: follow_btn_txt(profileViewModel.followState, follows_you: profileViewModel.followsYou))
                .frame(width: 100, height: 30)
                .font(.caption.weight(.bold))
                .foregroundColor(textColor())
                .background(backgroundColor())
                .cornerRadius(10)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(strokeColor(), lineWidth: strokeColor() == .clear ? 0 : 1)
                }
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.7 : 1.0)
        // Update followState on notifications.
        .onReceive(handle_notify(.followed)) { follow in
            if follow.contains(profileViewModel.publicKeyHex) {
                print("changing to follows")
                profileViewModel.followState = .follows
            }
        }
        .onReceive(handle_notify(.unfollowed)) { unfollow in
            if !unfollow.contains(profileViewModel.publicKeyHex) {
                print("changing to unfollows")
                profileViewModel.followState = .unfollows
            }
        }
    }
    
    func textColor() -> Color {
        switch profileViewModel.followState {
        case .unfollows:
            return colorScheme == .light ? .white : .black
        case .following:
            return colorScheme == .light ? .white : .black  // Keep filled look during loading
        case .unfollowing:
            return .gray
        case .follows:
            return .gray
        }
    }
    
    func backgroundColor() -> Color {
        switch profileViewModel.followState {
        case .unfollows:
            return .purple
        case .following:
            return .purple.opacity(0.6)  // Dimmed purple shows loading
        case .unfollowing:
            return .clear
        case .follows:
            return .clear
        }
    }
    
    func strokeColor() -> Color {
        switch profileViewModel.followState {
        case .unfollows, .following:
            return .clear
        case .unfollowing, .follows:
            return .gray
        }
    }
}

func follow_btn_txt(_ fs: FollowState, follows_you: Bool) -> String {
    switch fs {
    case .follows:
        return NSLocalizedString("Unfollow", comment: "Button to unfollow a user.")
    case .following:
        return NSLocalizedString("Following...", comment: "Label to indicate that the user is in the process of following another user.")
    case .unfollowing:
        return NSLocalizedString("Unfollowing...", comment: "Label to indicate that the user is in the process of unfollowing another user.")
    case .unfollows:
        return follows_you ? NSLocalizedString("Follow Back", comment: "Button to follow a user back.")
                         : NSLocalizedString("Follow", comment: "Button to follow a user.")
    }
}

enum FollowState {
    case follows
    case following
    case unfollowing
    case unfollows
}
