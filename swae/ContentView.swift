//
//  ContentView.swift
//  swae
//
//  Created by Suhail Saqan on 8/11/24.
//

import AVFoundation
import NostrSDK
import SwiftData
import SwiftUI

struct ContentView: View {
    let modelContext: ModelContext

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var orientationMonitor: OrientationMonitor

    @SceneStorage("ContentView.selected_tab") var selected_tab: ScreenTabs = .home
    
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    @State var hide_bar: Bool = false

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView(appState: appState)
            } else {
                MainAppView()
            }
        }
    }

    func MainAppView() -> some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selected_tab) {
                MainContent()
            }
            
            if appState.playerConfig.showMiniPlayer {
                ZStack {
                    Rectangle()
                        .fill(Color(UIColor.systemBackground))
                        .opacity(1.0 - appState.playerConfig.progress)
                        .zIndex(1)
                    
                    GeometryReader { geometry in
                        let size = geometry.size
                        
                        if appState.playerConfig.showMiniPlayer {
                            PlayerView(size: size, playerConfig: $appState.playerConfig) {
                                withAnimation(.easeInOut(duration: 0.3), completionCriteria: .logicallyComplete) {
                                    appState.playerConfig.showMiniPlayer = false
                                } completion: {
                                    appState.playerConfig.resetPosition()
                                    appState.playerConfig.selectedLiveActivitiesEvent = nil
                                }
                            }
                        }
                    }
                    .zIndex(2)
                }
            }
            
            CustomTabBar()
                .offset(y: appState.playerConfig.showMiniPlayer || hide_bar ? tabBarHeight - (appState.playerConfig.progress * tabBarHeight) : 0)
        }
        .ignoresSafeArea()
        .onReceive(handle_notify(.display_tabbar)) { display in
            let show = display
            self.hide_bar = !show
        }
        .onReceive(handle_notify(.unfollow)) { target in
            if (appState.saveFollowList(pubkeys: target)) {
                notify(.unfollowed(target))
            }
        }
        .onReceive(handle_notify(.unfollowed)) { pubkeys in
            appState.followedPubkeys.subtract(pubkeys)
            print("unfollowed************")
            appState.refreshFollowedPubkeys()
//            print("unfollowed: ", pubkeys)
        }
        .onReceive(handle_notify(.follow)) { target in
            if (appState.saveFollowList(pubkeys: target)) {
                notify(.followed(target))
            }
        }
        .onReceive(handle_notify(.followed)) { pubkeys in
            appState.followedPubkeys.formUnion(pubkeys)
            print("**********followed************")
            appState.refreshFollowedPubkeys()
//            print("followed: ", pubkeys)
        }
        .onReceive(handle_notify(.attached_wallet)) { nwc in
            // update the lightning address on our profile when we connect a wallet
            // TODO
            
            // add nwc relay to read and write
            appState.addRelay(relayURL: nwc.relay.url)
        }
    }
    
    func MainContent() -> some View {
        return Group {
//            if selected_tab == .home {
                VideoListView(eventListType: .all)
                    .setupTab(.home)
//            }
                
            if selected_tab == .live {
                IngestView()
                    .setupTab(.live)
            }
            
            if selected_tab == .wallet {
                if let wallet = appState.wallet {
                    WalletView(model: wallet)
                        .setupTab(.wallet)
                }
            }
            
            if selected_tab == .profile {
                ProfileView(appState: appState)
                    .setupTab(.profile)
            }
        }
    }
    
    /// Custom Tab Bar
    @ViewBuilder
    func CustomTabBar() -> some View {
        HStack(spacing: 0) {
            ForEach(ScreenTabs.allCases, id: \.rawValue) { tab in
                TabItemView(tab: tab, isSelected: selected_tab == tab)
                    .onTapGesture {
                        selected_tab = tab
                    }
            }
        }
        .frame(height: 49)
        .overlay(alignment: .top) {
            Divider()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .frame(height: tabBarHeight)
        .background(.background)
    }
}

var safeArea: UIEdgeInsets {
    if let safeArea = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.safeAreaInsets {
        return safeArea
    }
    
    return .zero
}
