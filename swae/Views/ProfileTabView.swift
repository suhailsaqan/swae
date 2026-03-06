//
//  ProfileTabView.swift
//  swae
//
//  Created by Suhail Saqan on 2/26/25.
//

import Kingfisher
import NostrSDK
import SwiftUI

// MARK: - LiveActivitiesView
struct LiveActivitiesView: View {
    @EnvironmentObject var appState: AppState
    @State private var timeTabFilter: TimeTabs = .past
    @State private var isInitialLoad = true
    @State private var hasLoadedOnce = false
    var publicKeyHex: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Live activities list
            if let key = (publicKeyHex ?? appState.publicKey?.hex) {
                let events = appState.profileEvents(key)

                if events.isEmpty {
                    // Show skeleton loading on initial load, otherwise show "No streams found"
                    if isInitialLoad && !hasLoadedOnce {
                        ProfileStreamsSkeleton()
                            .onAppear {
                                // After a short delay, mark as loaded to show "No streams found" if still empty
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    hasLoadedOnce = true
                                    isInitialLoad = false
                                }
                            }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "video.slash")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary.opacity(0.5))
                                .padding(.top, 40)
                            
                            Text("No streams yet")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("Your live streams will appear here")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 40)
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(events, id: \.id) { event in
                            ProfileStreamCard(event: event)
                                .onTapGesture {
                                    appState.playerConfig.selectedLiveActivitiesEvent = event
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        appState.playerConfig.setFullscreenWithChatState()
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .onAppear {
                        // Mark as loaded once we have events
                        hasLoadedOnce = true
                        isInitialLoad = false
                    }
                }
            } else {
                VStack {
                    Text("Please sign in to view your streams")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
            }
        }
        .onAppear {
            isInitialLoad = true
        }
    }
}

// MARK: - Second Tab Content
struct ShortsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("No shorts yet")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.top, 16)
            Spacer()
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Profile Stream Card
struct ProfileStreamCard: View {
    @EnvironmentObject var appState: AppState
    let event: LiveActivitiesEvent
    @State private var isImageLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Thumbnail
            ZStack(alignment: .topLeading) {
                KFImage.url(event.image)
                    .placeholder {
                        // Show skeleton while loading
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(UIColor.systemGray6),
                                        Color(UIColor.systemGray5),
                                        Color(UIColor.systemGray6)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .frame(height: 180)
                    }
                    .onSuccess { _ in
                        withAnimation {
                            isImageLoading = false
                        }
                    }
                    .onFailure { _ in
                        isImageLoading = false
                    }
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(height: 180)
                    .clipped()
                    .cornerRadius(12)

                // Live/Ended badge
                HStack {
                    Text(event.status != .live ? "ENDED" : "LIVE")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(event.status != .live ? Color.gray : Color.red)
                        .cornerRadius(4)

                    Spacer()
                }
                .padding(8)
            }

            // Stream info
            VStack(alignment: .leading) {
                Text(event.title ?? "Untitled Stream")
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let startTime = event.startsAt {
                    Text(formatStreamTime(startTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
