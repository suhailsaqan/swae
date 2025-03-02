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

    var body: some View {
        Button {
            // Call the action on the view model to handle follow/unfollow logic.
            profileViewModel.followButtonAction(target: [profileViewModel.publicKeyHex])
        } label: {
            Text(verbatim: follow_btn_txt(profileViewModel.followState, follows_you: profileViewModel.followsYou))
                .frame(width: 100, height: 30)
                .font(.caption.weight(.bold))
                .foregroundColor(profileViewModel.followState == .unfollows ? filledTextColor() : borderColor())
                .background(profileViewModel.followState == .unfollows ? fillColor() : emptyColor())
                .cornerRadius(10)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(profileViewModel.followState == .unfollows ? .clear : borderColor(), lineWidth: 1)
                }
        }
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
    
    func filledTextColor() -> Color {
        colorScheme == .light ? .white : .black
    }
    
    func fillColor() -> Color {
        .purple
    }
    
    func emptyColor() -> Color {
        Color.black.opacity(0)
    }
    
    func borderColor() -> Color {
        .gray
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
