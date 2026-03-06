//
//  InstagramFeedView.swift
//  swae
//
//  Created by AI Assistant
//

import NostrSDK
import SwiftUI

/// Wrapper for the UIKit-based MainTabBarController
/// This is used by InstagramNavigationView to show the feed content
struct InstagramFeedView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var model: Model
    @Binding var selectedTab: ScreenTabs

    let onCameraButtonTapped: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            // UIKit-based MainTabBarController
            // This handles all tabs (home, zaps, wallet, profile)
            MainTabBarRepresentable()
                .background(Color.black)
                .ignoresSafeArea(.all, edges: .all)  // Ensure black background extends everywhere
                .offset(
                    y: (appState.playerConfig.playerState == .fullscreen
                        || appState.playerConfig.playerState == .fullscreenWithChat)
                        ? tabBarHeight : 0)
        }
    }
}

// MARK: - Unused Code (Dead Code - Removed)
// The following components were never used in the app:
// - CustomTabBar() - tabs are managed by MainTabBarController
// - CameraTabButton - not needed
// - InstagramNavigationBar - header is now in VideoListViewController (AmbientHeader)
// - InstagramFeedHeader - not needed
// - InstagramFeedViewWithHeader - never used
//
// The app correctly uses:
// InstagramFeedView → MainTabBarRepresentable → MainTabBarController → VideoListViewController
